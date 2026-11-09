import Foundation
import HealthKit

/// Apple Health: save Mindful Minutes, read heart rate / HRV / mindful minutes.
final class MindfulHealth {
    static let shared = MindfulHealth()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var mindful: HKCategoryType { HKCategoryType(.mindfulSession) }
    private var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    private var hrv: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }

    var shareTypes: Set<HKSampleType> { [mindful, HKObjectType.workoutType()] }
    var readTypes: Set<HKObjectType> { [mindful, heartRate, hrv, HKObjectType.workoutType()] }

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

    static let bpm = HKUnit.count().unitDivided(by: .minute())
}
