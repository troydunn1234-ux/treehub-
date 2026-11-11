import Foundation
import HealthKit
import Observation
import SwiftData
import UIKit

/// Apple Health for Food Book.
/// - Writes every logged food as a Health "food" entry (calories, protein, carbs, fat, caffeine).
///   Edits replace the old entry and deletes remove it, so Health always matches Food Book.
/// - Reads what you burned today. Whoop and Apple Watch both write into Health, and Health
///   merges them by your source priority, so the numbers here don't double count.
@MainActor
@Observable
final class FoodHealth {
    static let shared = FoodHealth()

    struct Workout: Identifiable, Equatable {
        let id: UUID
        let name: String
        let kcal: Double
        let minutes: Double
        let source: String
        let symbol: String
    }

    private(set) var active: Double = 0
    private(set) var resting: Double = 0
    private(set) var exerciseMinutes: Double = 0
    private(set) var workouts: [Workout] = []
    private(set) var connected: Bool = UserDefaults.standard.bool(forKey: "healthOn")
    private(set) var lastSync: Date?
    private(set) var problem: String?

    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")
    var available: Bool { Self.demo || HKHealthStore.isHealthDataAvailable() }
    /// Show burned numbers (connected for real, or demo screenshots).
    var showing: Bool { Self.demo || connected }

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let entryKey = "FoodBookEntryID"
    private static let syncedKey = "hkSyncedEntries"

    private init() {
        if Self.demo {
            active = 540; resting = 1_720; exerciseMinutes = 48
            workouts = [
                Workout(id: UUID(), name: "Strength", kcal: 310, minutes: 42, source: "WHOOP", symbol: "dumbbell.fill"),
                Workout(id: UUID(), name: "Outdoor Walk", kcal: 140, minutes: 31, source: "Apple Watch", symbol: "figure.walk")
            ]
        }
    }

    // MARK: Setup

    func attach(container: ModelContainer) {
        self.container = container
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshBurned()
                self?.scheduleSync()
            }
        })
    }

    private var writeTypes: Set<HKSampleType> {
        [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein), HKQuantityType(.dietaryCarbohydrates),
         HKQuantityType(.dietaryFatTotal), HKQuantityType(.dietaryCaffeine), HKQuantityType(.dietaryWater)]
    }
    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned), HKQuantityType(.appleExerciseTime),
         HKObjectType.workoutType()]
    }

    /// Ask for permission (the Health sheet), then backfill recent meals and read today's burn.
    func connect() async {
        problem = nil
        if Self.demo { connected = true; return }
        guard HKHealthStore.isHealthDataAvailable() else { problem = "Apple Health isn't available on this device."; return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            problem = "Apple Health didn't open: \(error.localizedDescription)"
            return
        }
        connected = true
        UserDefaults.standard.set(true, forKey: "healthOn")
        if !canWrite { problem = "Meals won't save to Health until you allow Food Book in Health → Sharing → Apps." }
        await refreshBurned()
        await syncMeals()
    }

    func disconnect() {
        connected = false
        UserDefaults.standard.set(false, forKey: "healthOn")
        if !Self.demo { active = 0; resting = 0; exerciseMinutes = 0; workouts = [] }
    }

    /// Whether Health lets us save calories (iOS only tells apps about write permission).
    var canWrite: Bool {
        guard !Self.demo, HKHealthStore.isHealthDataAvailable() else { return Self.demo }
        return store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized
    }

    // MARK: Reading what you burned

    func refreshBurned() async {
        guard connected, !Self.demo, HKHealthStore.isHealthDataAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        async let a = sum(.activeEnergyBurned, unit: .kilocalorie(), from: start)
        async let r = sum(.basalEnergyBurned, unit: .kilocalorie(), from: start)
        async let m = sum(.appleExerciseTime, unit: .minute(), from: start)
        async let w = todaysWorkouts(from: start)
        let (av, rv, mv, wv) = await (a, r, m, w)
        let changed = abs(active - av) >= 1
        active = av; resting = rv; exerciseMinutes = mv; workouts = wv
        if changed { FoodWatchBridge.shared.pushNow() }   // the watch shows burned calories too
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> Double {
        let type = HKQuantityType(id)
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let store = self.store
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func todaysWorkouts(from start: Date) async -> [Workout] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let store = self.store
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 20, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
        return samples.compactMap { $0 as? HKWorkout }.map { w in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let (name, symbol) = Self.describe(w.workoutActivityType)
            return Workout(id: w.uuid, name: name, kcal: kcal, minutes: w.duration / 60,
                           source: w.sourceRevision.source.name, symbol: symbol)
        }
    }

    private static func describe(_ t: HKWorkoutActivityType) -> (String, String) {
        switch t {
        case .running: return ("Run", "figure.run")
        case .walking: return ("Walk", "figure.walk")
        case .hiking: return ("Hike", "figure.hiking")
        case .cycling: return ("Ride", "figure.outdoor.cycle")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("Strength", "dumbbell.fill")
        case .highIntensityIntervalTraining: return ("HIIT", "flame.fill")
        case .crossTraining: return ("Cross training", "figure.cross.training")
        case .yoga: return ("Yoga", "figure.yoga")
        case .swimming: return ("Swim", "figure.pool.swim")
        case .basketball: return ("Basketball", "figure.basketball")
        case .soccer: return ("Soccer", "figure.soccer")
        case .boxing, .kickboxing, .martialArts: return ("Fight training", "figure.boxing")
        case .elliptical: return ("Elliptical", "figure.elliptical")
        case .rowing: return ("Row", "figure.rower")
        case .stairClimbing, .stairs: return ("Stairs", "figure.stairs")
        case .dance, .socialDance, .cardioDance: return ("Dance", "figure.dance")
        case .golf: return ("Golf", "figure.golf")
        case .mindAndBody, .flexibility, .cooldown: return ("Mobility", "figure.mind.and.body")
        default: return ("Workout", "figure.mixed.cardio")
        }
    }

    // MARK: Writing meals

    /// Coalesce bursts of saves (a 3-item plate) into one Health sync.
    private func scheduleSync() {
        guard connected, !Self.demo else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self.syncMeals()
        }
    }

    /// Make Health match Food Book for the last 3 days: new entries are saved, changed ones replaced,
    /// deleted ones removed. Older edits/deletes are still caught because every synced entry is remembered.
    func syncMeals() async {
        guard connected, !Self.demo, HKHealthStore.isHealthDataAvailable(), canWrite, let container else { return }
        let ctx = container.mainContext
        let all = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let byID = Dictionary(all.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var synced = UserDefaults.standard.dictionary(forKey: Self.syncedKey) as? [String: [String: Any]] ?? [:]
        let from = Day.shift(Day.key(Date()), by: -2)

        // Deleted in Food Book → delete from Health.
        for id in synced.keys where byID[id] == nil {
            if await removeFromHealth(id) { synced[id] = nil }
        }
        // New or changed in the last 3 days → (re)write.
        for e in all where e.day >= from {
            let id = e.id.uuidString
            let sig = Self.signature(e)
            let old = synced[id]
            if (old?["sig"] as? String) == sig { continue }
            let version = (old?["v"] as? Int ?? 0) + 1
            if old != nil { _ = await removeFromHealth(id) }
            guard let food = Self.correlation(for: e, version: version) else { synced[id] = ["sig": sig, "v": version, "day": e.day]; continue }
            do {
                try await store.save(food)
                synced[id] = ["sig": sig, "v": version, "day": e.day]
            } catch {
                problem = "Couldn't save to Health: \(error.localizedDescription)"
            }
        }
        // Forget entries older than 60 days (they won't be edited).
        let keepFrom = Day.shift(Day.key(Date()), by: -60)
        synced = synced.filter { ($0.value["day"] as? String ?? "") >= keepFrom }
        UserDefaults.standard.set(synced, forKey: Self.syncedKey)
        lastSync = Date()
    }

    private static func signature(_ e: FoodEntry) -> String {
        let s = e.servings
        return [e.name, String(format: "%.1f|%.1f|%.1f|%.1f|%.1f", e.cal * s, e.protein * s, e.carbs * s, e.fat * s, e.caffeine * s),
                String(Int(e.createdAt.timeIntervalSince1970))].joined(separator: "|")
    }

    private static func correlation(for e: FoodEntry, version: Int) -> HKCorrelation? {
        let id = e.id.uuidString
        let when = e.createdAt
        let s = e.servings
        var meta: [String: Any] = [HKMetadataKeyFoodType: e.name, entryKey: id]
        var parts = Set<HKSample>()
        func add(_ t: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit, _ suffix: String) {
            guard value > 0 else { return }
            var m = meta
            m[HKMetadataKeySyncIdentifier] = "\(id).\(suffix)"
            m[HKMetadataKeySyncVersion] = version
            parts.insert(HKQuantitySample(type: HKQuantityType(t), quantity: HKQuantity(unit: unit, doubleValue: value),
                                          start: when, end: when, metadata: m))
        }
        add(.dietaryEnergyConsumed, e.cal * s, .kilocalorie(), "kcal")
        add(.dietaryProtein, e.protein * s, .gram(), "protein")
        add(.dietaryCarbohydrates, e.carbs * s, .gram(), "carbs")
        add(.dietaryFatTotal, e.fat * s, .gram(), "fat")
        add(.dietaryCaffeine, e.caffeine * s, .gramUnit(with: .milli), "caffeine")
        guard !parts.isEmpty else { return nil }
        meta[HKMetadataKeySyncIdentifier] = id
        meta[HKMetadataKeySyncVersion] = version
        return HKCorrelation(type: HKCorrelationType(.food), start: when, end: when, objects: parts, metadata: meta)
    }

    // MARK: Quick log (water + coffee taps)

    private static let quickKey = "FoodBookQuickLog"

    /// Make Health match the day's water / caffeine tap counters: one water sample (ml) and one caffeine
    /// sample (mg) per day, replaced whenever the counters change. Same permission gate as meals.
    func syncQuickLog(day: String, waterML: Double, caffeineMG: Double) async {
        guard connected, !Self.demo, HKHealthStore.isHealthDataAvailable() else { return }
        // Water was added after the first release: people who connected earlier get asked once more.
        if store.authorizationStatus(for: HKQuantityType(.dietaryWater)) == .notDetermined {
            try? await store.requestAuthorization(toShare: [HKQuantityType(.dietaryWater)], read: [])
        }
        let when = Calendar.current.isDateInToday(Day.date(day)) ? Date() : Day.date(day).addingTimeInterval(12 * 3600)
        await replaceQuick(.dietaryWater, tag: "water." + day, value: waterML, unit: .literUnit(with: .milli), when: when)
        await replaceQuick(.dietaryCaffeine, tag: "coffee." + day, value: caffeineMG, unit: .gramUnit(with: .milli), when: when)
    }

    private func replaceQuick(_ id: HKQuantityTypeIdentifier, tag: String, value: Double, unit: HKUnit, when: Date) async {
        let type = HKQuantityType(id)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let pred = HKQuery.predicateForObjects(withMetadataKey: Self.quickKey, allowedValues: [tag])
        let store = self.store
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.deleteObjects(of: type, predicate: pred) { success, _, error in cont.resume(returning: success || error == nil) }
        }
        guard value > 0 else { return }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: when, end: when,
                                      metadata: [Self.quickKey: tag])
        do { try await store.save(sample) } catch { problem = "Couldn't save to Health: \(error.localizedDescription)" }
    }

    /// Remove a Food Book entry (the food correlation and every nutrient in it) from Health.
    private func removeFromHealth(_ id: String) async -> Bool {
        let pred = HKQuery.predicateForObjects(withMetadataKey: Self.entryKey, allowedValues: [id])
        var ok = true
        let types: [HKObjectType] = [HKCorrelationType(.food)] + writeTypes.map { $0 as HKObjectType }
        for t in types {
            let store = self.store
            let done: Bool = await withCheckedContinuation { cont in
                store.deleteObjects(of: t, predicate: pred) { success, _, error in
                    // "Nothing matched" isn't a failure.
                    cont.resume(returning: success || error == nil)
                }
            }
            // Correlations can't be authorized directly, so a failure there isn't fatal; the nutrients are what count.
            if !(t is HKCorrelationType) { ok = ok && done }
        }
        return ok
    }
}
