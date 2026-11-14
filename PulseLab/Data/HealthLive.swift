import Foundation
import HealthKit

/// Keeps Pulse Lab fresh without opening it: one observer query per Health type, with background delivery,
/// and an anchored query per type that tells us *which days* new samples landed on. WHOOP often writes into
/// Health hours (or days) late, so a late sample marks its own day "dirty" and the next refresh re-reads from there.
final class HealthLive: @unchecked Sendable {
    static let shared = HealthLive()
    private var store: HKHealthStore { HealthPull.shared.store }
    private var observers: [HKObserverQuery] = []
    private let lock = NSLock()
    private var started = false

    /// Earliest day touched by new samples since the last refresh (nil = nothing outside the usual window).
    static var dirtyFrom: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "healthDirtyFrom")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let newValue { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "healthDirtyFrom") }
            else { UserDefaults.standard.removeObject(forKey: "healthDirtyFrom") }
        }
    }
    private static let dirtyLock = NSLock()
    static func markDirty(_ day: Date) {
        dirtyLock.lock(); defer { dirtyLock.unlock() }
        if let d = dirtyFrom, d <= day { return }
        dirtyFrom = day.dayStart
    }

    /// High-frequency types only need hourly wake-ups; the rest can come in as soon as Health allows.
    private static let hourly: Set<String> = [
        HKQuantityTypeIdentifier.heartRate.rawValue, HKQuantityTypeIdentifier.stepCount.rawValue,
        HKQuantityTypeIdentifier.activeEnergyBurned.rawValue, HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
        HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue, HKQuantityTypeIdentifier.distanceCycling.rawValue,
        HKQuantityTypeIdentifier.appleExerciseTime.rawValue, HKQuantityTypeIdentifier.appleStandTime.rawValue,
        HKQuantityTypeIdentifier.environmentalAudioExposure.rawValue, HKQuantityTypeIdentifier.flightsClimbed.rawValue,
        HKQuantityTypeIdentifier.timeInDaylight.rawValue, HKQuantityTypeIdentifier.physicalEffort.rawValue,
        HKQuantityTypeIdentifier.walkingSpeed.rawValue, HKQuantityTypeIdentifier.walkingStepLength.rawValue,
        HKQuantityTypeIdentifier.walkingAsymmetryPercentage.rawValue, HKQuantityTypeIdentifier.walkingDoubleSupportPercentage.rawValue,
        HKCategoryTypeIdentifier.appleStandHour.rawValue,
    ]

    /// Start observing every type we read. Safe to call more than once; called at launch (also background launches).
    func start(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) {
        guard HealthPull.available else { return }
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        for type in HealthPull.shared.sampleTypes {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard let self, error == nil else { completion(); return }
                Task {
                    await self.collectChanges(type)
                    onChange { completion() }
                }
            }
            observers.append(q)
            store.execute(q)
            let freq: HKUpdateFrequency = Self.hourly.contains(type.identifier) ? .hourly : .immediate
            store.enableBackgroundDelivery(for: type, frequency: freq) { _, _ in }
        }
    }

    // MARK: - Anchors

    private func anchorKey(_ type: HKSampleType) -> String { "hkAnchor." + type.identifier }

    private func loadAnchor(_ type: HKSampleType) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey(type)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor?, for type: HKSampleType) {
        guard let anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey(type))
    }

    /// Reads what was added since the saved anchor and marks the earliest day it belongs to.
    /// The first run only sets the anchor (from the last day), since the backfill already covers history.
    func collectChanges(_ type: HKSampleType) async {
        let anchor = loadAnchor(type)
        let pred: NSPredicate? = anchor == nil ? HKQuery.predicateForSamples(withStart: Date().adding(days: -1), end: nil, options: []) : nil
        let (added, newAnchor): ([HKSample], HKQueryAnchor?) = await withCheckedContinuation { cont in
            let q = HKAnchoredObjectQuery(type: type, predicate: pred, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, error in
                if error != nil { cont.resume(returning: ([], nil)); return }
                cont.resume(returning: (samples ?? [], newAnchor))
            }
            store.execute(q)
        }
        guard newAnchor != nil else { return }
        if anchor != nil, let earliest = added.map(\.startDate).min() {
            // Sleep is credited to the morning you wake up, and workouts/samples to their own day.
            Self.markDirty(earliest)
        }
        saveAnchor(newAnchor, for: type)
    }

    /// Forget anchors (used by "Rebuild full history").
    func resetAnchors() {
        for type in HealthPull.shared.sampleTypes { UserDefaults.standard.removeObject(forKey: anchorKey(type)) }
        Self.dirtyFrom = nil
    }
}
