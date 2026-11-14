import Foundation
import HealthKit

/// A mindful session another app (or the Watch's Mindfulness app) wrote to Apple Health.
struct ExternalMindfulSession: Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var source: String
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// Apple Health: save Mindful Minutes, read heart rate / HRV / respiratory rate / mindful minutes.
final class MindfulHealth {
    static let shared = MindfulHealth()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var mindful: HKCategoryType { HKCategoryType(.mindfulSession) }
    private var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    private var hrv: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    private var respiratory: HKQuantityType { HKQuantityType(.respiratoryRate) }

    var shareTypes: Set<HKSampleType> { [mindful, HKObjectType.workoutType()] }
    var readTypes: Set<HKObjectType> { [mindful, heartRate, hrv, respiratory, HKObjectType.workoutType()] }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        guard isAvailable, !ProcessInfo.processInfo.arguments.contains("-demo") else { done?(false); return }
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { ok, _ in
            DispatchQueue.main.async { done?(ok) }
        }
    }

    var canSaveMindful: Bool {
        isAvailable && store.authorizationStatus(for: mindful) == .sharingAuthorized
    }

    func saveMindful(start: Date, end: Date) {
        guard isAvailable, end.timeIntervalSince(start) >= 30,
              !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        let sample = HKCategorySample(type: mindful, value: HKCategoryValue.notApplicable.rawValue, start: start, end: end)
        store.save(sample) { _, _ in }
    }

    // MARK: Workouts (movement routines, sauna & steam)

    /// What kind of Health workout a practice counts as; nil for breathing / stillness.
    static func activity(for practiceId: String) -> HKWorkoutActivityType? {
        guard let p = PracticeLibrary.shared.practice(practiceId), p.isMovement else { return nil }
        switch p.id {
        case "taichi-cloud", "baduanjin": return .taiChi
        case "surya-gentle": return .yoga
        default: break
        }
        switch p.focus {
        case .joint?, .lymph?: return .preparationAndRecovery
        default: return .flexibility
        }
    }

    /// Save a finished routine or heat session as a workout, so it counts as exercise in Health and Fitness.
    func saveWorkout(_ type: HKWorkoutActivityType, start: Date, end: Date, title: String) {
        guard isAvailable, end.timeIntervalSince(start) >= 60,
              !ProcessInfo.processInfo.arguments.contains("-demo"),
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = type
        config.locationType = .indoor
        let b = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        b.beginCollection(withStart: start) { ok, _ in
            guard ok else { return }
            b.addMetadata([HKMetadataKeyWorkoutBrandName: "Still Pointz", HKMetadataKeyIndoorWorkout: true, "StillPointTitle": title]) { _, _ in
                b.endCollection(withEnd: end) { _, _ in
                    b.finishWorkout { _, _ in }
                }
            }
        }
    }

    /// Remove the Mindful Minutes (and workout) this app saved for a session that was discarded.
    func deleteMindful(start: Date, end: Date) {
        guard isAvailable, !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-5), end: end.addingTimeInterval(5), options: []),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        store.deleteObjects(of: mindful, predicate: pred) { _, _, _ in }
        store.deleteObjects(of: HKObjectType.workoutType(), predicate: pred) { _, _, _ in }
    }

    /// Mindful minutes recorded in Health since `since` (all apps).
    func mindfulMinutes(since: Date, _ done: @escaping (Double) -> Void) {
        guard isAvailable else { done(0); return }
        let pred = HKQuery.predicateForSamples(withStart: since, end: Date())
        let q = HKSampleQuery(sampleType: mindful, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let secs = (samples ?? []).reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            DispatchQueue.main.async { done(secs / 60) }
        }
        store.execute(q)
    }

    /// Mindful sessions written by other apps since `since`, newest first.
    func externalMindfulSessions(since: Date, _ done: @escaping ([ExternalMindfulSession]) -> Void) {
        guard isAvailable else { done([]); return }
        let pred = HKQuery.predicateForSamples(withStart: since, end: Date())
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let mine = Bundle.main.bundleIdentifier ?? ""
        let q = HKSampleQuery(sampleType: mindful, predicate: pred, limit: 200, sortDescriptors: sort) { _, samples, _ in
            let out: [ExternalMindfulSession] = (samples ?? []).compactMap { s in
                let bundle = s.sourceRevision.source.bundleIdentifier
                // Skip our own iPhone and Watch apps.
                guard !bundle.hasPrefix(mine), !bundle.contains("stillpoint"), !bundle.contains("StillPoint") else { return nil }
                return ExternalMindfulSession(id: s.uuid, start: s.startDate, end: s.endDate, source: s.sourceRevision.source.name)
            }
            DispatchQueue.main.async { done(out) }
        }
        store.execute(q)
    }

    /// Most recent HRV (SDNN, ms) recorded after `since`.
    func latestHRV(since: Date, _ done: @escaping (Double?) -> Void) {
        guard isAvailable else { done(nil); return }
        let pred = HKQuery.predicateForSamples(withStart: since, end: Date().addingTimeInterval(120))
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let q = HKSampleQuery(sampleType: hrv, predicate: pred, limit: 1, sortDescriptors: sort) { _, samples, _ in
            let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .secondUnit(with: .milli))
            DispatchQueue.main.async { done(v) }
        }
        store.execute(q)
    }

    /// Average HRV (SDNN, ms) inside a session window, padded a little either side. Nil if the Watch took none.
    func sessionHRV(start: Date, end: Date, _ done: @escaping (Double?) -> Void) {
        guard isAvailable else { done(nil); return }
        let pred = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(180))
        let q = HKStatisticsQuery(quantityType: hrv, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
            let v = stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
            DispatchQueue.main.async { done(v) }
        }
        store.execute(q)
    }

    /// Average respiratory rate (breaths/min) inside a session window, if the Watch recorded any.
    func respiratoryRate(start: Date, end: Date, _ done: @escaping (Double?) -> Void) {
        guard isAvailable else { done(nil); return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end.addingTimeInterval(60))
        let q = HKStatisticsQuery(quantityType: respiratory, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
            let v = stats?.averageQuantity()?.doubleValue(for: MindfulHealth.bpm)
            DispatchQueue.main.async { done(v) }
        }
        store.execute(q)
    }

    static let bpm = HKUnit.count().unitDivided(by: .minute())

    /// Heart rate from every source in Apple Health (WHOOP, Apple Watch, Garmin…) inside a time window.
    /// Nil when nothing was recorded (yet: WHOOP can take a few minutes to sync).
    func heartRateStats(start: Date, end: Date, _ done: @escaping (HeartWindow?) -> Void) {
        guard isAvailable, end > start else { done(nil); return }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let q = HKSampleQuery(sampleType: heartRate, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, _ in
            let qs = (samples as? [HKQuantitySample]) ?? []
            guard !qs.isEmpty else { DispatchQueue.main.async { done(nil) }; return }
            let values = qs.map { $0.quantity.doubleValue(for: MindfulHealth.bpm) }
            // Keep at most ~120 points for the chart.
            let stride = max(1, qs.count / 120)
            var points: [HRSample] = []
            for i in Swift.stride(from: 0, to: qs.count, by: stride) {
                points.append(HRSample(t: qs[i].startDate.timeIntervalSince(start), bpm: values[i]))
            }
            let names = Array(Set(qs.map { $0.sourceRevision.source.name })).sorted()
            let w = HeartWindow(avg: values.reduce(0, +) / Double(values.count),
                                max: values.max() ?? 0, min: values.min() ?? 0,
                                sources: names, points: points)
            DispatchQueue.main.async { done(w) }
        }
        store.execute(q)
    }
}

/// Heart-rate summary for one stretch of time, from Apple Health.
struct HeartWindow: Codable, Hashable {
    var avg: Double
    var max: Double
    var min: Double
    var sources: [String]
    var points: [HRSample]
}
