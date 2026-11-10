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
}
