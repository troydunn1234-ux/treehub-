import Foundation
import HealthKit

/// Reads what Apple Watch (and other apps such as Whoop or Strava) save into Apple Health.
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

    /// Mindful / breathwork sessions near a moment (Apple Watch Mindfulness, Still Pointz and others save them here).
    func mindfulSessions(around date: Date, hours: Double = 3) async -> [MindfulSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return [] }
        let start = date.addingTimeInterval(-hours * 3600)
        let end = date.addingTimeInterval(hours * 3600)
        let samples = await samples(of: type, start: start, end: end, limit: 20)
        return samples.map {
            MindfulSession(start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.name)
        }.sorted { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    /// Some watch apps save breathwork to Apple Health as a short "Mind & Body"-style workout rather than
    /// mindful minutes, so look for those too. Rootbound's own Watch hugs (also Mind & Body) are left out:
    /// they are the hug itself, not a breath session to link to it.
    func breathworkWorkouts(around date: Date, hours: Double = 3) async -> [MindfulSession] {
        let calm: Set<HKWorkoutActivityType> = [.mindAndBody, .yoga, .other, .flexibility, .preparationAndRecovery, .cooldown, .taiChi]
        let raw = await samples(of: HKObjectType.workoutType(),
                                start: date.addingTimeInterval(-hours * 3600),
                                end: date.addingTimeInterval(hours * 3600), limit: 30)
        return raw.compactMap { $0 as? HKWorkout }
            .filter { calm.contains($0.workoutActivityType) && $0.duration >= 60 && $0.duration <= 90 * 60 }
            .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix("com.troydunn.rootbound") }
            .map { MindfulSession(start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.name) }
            .sorted { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    /// The breathwork session closest to a moment, from either place watch apps save it.
    func nearestBreathSession(around date: Date) async -> MindfulSession? {
        let all = await mindfulSessions(around: date) + breathworkWorkouts(around: date)
        return all.filter { $0.minutes >= 1 }
            .min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
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

    /// Recent workouts from any app (Apple Watch, Strava, Whoop…).
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

    /// A walk, hike or run from any app in Apple Health (read-only), with what Rootbound shows under a hug.
    struct FootWorkout: Identifiable {
        let id: UUID
        var kind: ActivityKind
        var start: Date
        var end: Date
        var distanceM: Double
        var elevGainM: Double
        var avgHR: Double?
        var source: String
        var bundleID: String
    }

    /// Walking, hiking and running workouts that touch `from...to`, oldest first.
    func footWorkouts(from start: Date, to end: Date) async -> [FootWorkout] {
        let raw = await samples(of: HKObjectType.workoutType(), start: start, end: end, limit: 300)
        return raw.compactMap { $0 as? HKWorkout }.compactMap { w -> FootWorkout? in
            let kind: ActivityKind
            switch w.workoutActivityType {
            case .walking: kind = .walk
            case .hiking: kind = .hike
            case .running: kind = .run
            default: return nil
            }
            var dist = 0.0
            if let t = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
               let q = w.statistics(for: t)?.sumQuantity() {
                dist = q.doubleValue(for: .meter())
            }
            let climb = (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) ?? 0
            var hr: Double? = nil
            if let t = HKQuantityType.quantityType(forIdentifier: .heartRate),
               let q = w.statistics(for: t)?.averageQuantity() {
                hr = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            return FootWorkout(id: w.uuid, kind: kind, start: w.startDate, end: w.endDate, distanceM: dist,
                               elevGainM: climb, avgHR: hr, source: w.sourceRevision.source.name,
                               bundleID: w.sourceRevision.source.bundleIdentifier)
        }.sorted { $0.start < $1.start }
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

    /// Heart numbers for one breath session (read-only): average and lowest heart rate, the first reading
    /// (so "start -> lowest" gives the calm effect) and average HRV. Nil fields when nothing was recorded.
    struct BreathStats {
        var avgHR: Double?
        var minHR: Double?
        var startHR: Double?
        /// Last reading in the window (start -> end shows how the body settled).
        var endHR: Double?
        var hrv: Double?
        var hrDrop: Double? {
            guard let a = startHR, let b = minHR else { return nil }
            return a - b
        }
    }

    func breathStats(from start: Date, to end: Date) async -> BreathStats {
        var out = BreathStats()
        let unit = HKUnit.count().unitDivided(by: .minute())
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let s = await quantitySamples(hr, start: start, end: end).sorted { $0.startDate < $1.startDate }
            let v = s.map { $0.quantity.doubleValue(for: unit) }.filter { $0 > 25 && $0 < 230 }
            if !v.isEmpty {
                out.avgHR = v.reduce(0, +) / Double(v.count)
                out.minHR = v.min()
                out.startHR = v.first
                out.endHR = v.last
            }
        }
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let s = await quantitySamples(hrvType, start: start.addingTimeInterval(-60), end: end.addingTimeInterval(180))
            let v = s.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }.filter { $0 > 0 }
            if !v.isEmpty { out.hrv = v.reduce(0, +) / Double(v.count) }
        }
        return out
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
