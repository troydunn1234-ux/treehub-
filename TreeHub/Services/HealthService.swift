import Foundation
import HealthKit

/// Reads what Garmin Connect, Whoop, Strava and others save into Apple Health.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType()]
        let qty: [HKQuantityTypeIdentifier] = [.heartRate, .respiratoryRate, .restingHeartRate, .heartRateVariabilitySDNN]
        for id in qty { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { s.insert(mindful) }
        return s
    }

    /// Shows Apple's Health permission sheet the first time; later calls return immediately.
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    struct HeartStats {
        var avg: Double
        var min: Double
        var max: Double
        var samples: Int
    }

    func heartRate(from start: Date, to end: Date) async -> HeartStats? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let samples = await quantitySamples(type, start: start, end: end)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 25 && $0 < 230 }
        guard !values.isEmpty else { return nil }
        return HeartStats(avg: values.reduce(0, +) / Double(values.count),
                          min: values.min() ?? 0, max: values.max() ?? 0, samples: values.count)
    }

    func respiratoryRate(from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return nil }
        let samples = await quantitySamples(type, start: start, end: end)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 1 && $0 < 60 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    struct MindfulSession {
        var start: Date
        var end: Date
        var source: String
        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    /// Mindful / breathwork sessions near a moment (Garmin can save breathwork here).
    func mindfulSessions(around date: Date, hours: Double = 3) async -> [MindfulSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return [] }
        let start = date.addingTimeInterval(-hours * 3600)
        let end = date.addingTimeInterval(hours * 3600)
        let samples = await samples(of: type, start: start, end: end, limit: 20)
        return samples.map {
            MindfulSession(start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.name)
        }.sorted { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    struct WorkoutInfo: Identifiable {
        let id: UUID
        var kind: ActivityKind?
        var name: String
        var start: Date
        var end: Date
        var distanceM: Double?
        var energyKcal: Double?
        var source: String
    }

    /// Recent workouts from any app (Garmin, Strava, Whoop, Apple Watch…).
    func recentWorkouts(days: Int = 30) async -> [WorkoutInfo] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let raw = await samples(of: HKObjectType.workoutType(), start: start, end: Date(), limit: 200)
        return raw.compactMap { $0 as? HKWorkout }.map { w in
            let dist: Double?
            if #available(iOS 16.0, *) {
                let distTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                dist = distTypes.lazy
                    .compactMap { HKQuantityType.quantityType(forIdentifier: $0) }
                    .compactMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
                    .first
            } else {
                dist = nil
            }
            let kcal: Double? = {
                guard let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
                return w.statistics(for: t)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            }()
            let (k, n) = Self.describe(w.workoutActivityType)
            return WorkoutInfo(id: w.uuid, kind: k, name: n, start: w.startDate, end: w.endDate,
                               distanceM: dist, energyKcal: kcal, source: w.sourceRevision.source.name)
        }.sorted { $0.start > $1.start }
    }

    static func describe(_ t: HKWorkoutActivityType) -> (ActivityKind?, String) {
        switch t {
        case .running: return (.run, "Run")
        case .walking: return (.walk, "Walk")
        case .hiking: return (.hike, "Hike")
        case .cycling: return (.bike, "Ride")
        case .mindAndBody: return (nil, "Mind & Body")
        case .yoga: return (nil, "Yoga")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return (nil, "Strength")
        case .highIntensityIntervalTraining: return (nil, "HIIT")
        case .swimming: return (nil, "Swim")
        case .elliptical: return (nil, "Elliptical")
        case .rowing: return (nil, "Row")
        case .soccer: return (nil, "Soccer")
        case .basketball: return (nil, "Basketball")
        case .golf: return (nil, "Golf")
        case .tennis: return (nil, "Tennis")
        case .pilates: return (nil, "Pilates")
        case .stairClimbing: return (nil, "Stairs")
        default: return (nil, "Workout")
        }
    }

    // MARK: - Query helpers

    private func quantitySamples(_ type: HKQuantityType, start: Date, end: Date) async -> [HKQuantitySample] {
        await samples(of: type, start: start, end: end, limit: HKObjectQueryNoLimit).compactMap { $0 as? HKQuantitySample }
    }

    private func samples(of type: HKSampleType, start: Date, end: Date, limit: Int) async -> [HKSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, results, _ in
                cont.resume(returning: results ?? [])
            }
            store.execute(q)
        }
    }
}
