import Foundation
import WatchKit
import HealthKit

/// Haptics on the wrist. Phase changes are distinct so you can breathe with eyes closed.
final class WatchHaptics: BreathFeedback {
    private let device = WKInterfaceDevice.current()
    var sound = false

    func phaseBegan(_ phase: BreathPhase, duration: Double, style: HapticStyle) {
        switch style {
        case .off: return
        case .subtle:
            switch phase {
            case .inhale, .exhale: device.play(.click)
            default: break
            }
        case .strong:
            switch phase {
            case .inhale: device.play(.directionUp)
            case .exhale: device.play(.directionDown)
            case .holdIn: device.play(.click)
            case .holdOut: device.play(.stop)
            case .still: break
            }
        }
    }

    func exhaleTick(style: HapticStyle) {
        guard style != .off else { return }
        device.play(.click)
    }

    func topUp(style: HapticStyle) {
        guard style != .off else { return }
        device.play(.click)
    }

    func bell(_ kind: BellKind) {
        switch kind {
        case .start: device.play(.start)
        case .interval: device.play(.notification)
        case .end: device.play(.success)
        }
    }

    func stepBegan(style: HapticStyle) {
        guard style != .off else { return }
        device.play(.directionUp)
    }

    func sideSwitchSoon(style: HapticStyle) {
        guard style != .off else { return }
        device.play(.click)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [device] in device.play(.click) }
    }

    func stopAll() {}
}

/// Keeps the app alive wrist-down and collects heart rate.
/// - With heart rate on: an HKWorkoutSession (Mind & Body). Saved as a workout only if the user wants.
/// - Otherwise: a WKExtendedRuntimeSession of type mindfulness (from WKBackgroundModes).
final class WatchRuntime: NSObject, ObservableObject {
    static let shared = WatchRuntime()

    @Published private(set) var heartRate: Double? = nil
    @Published private(set) var startHR: Double? = nil
    @Published private(set) var minHR: Double? = nil

    private let store = MindfulHealth.shared.store
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var runtime: WKExtendedRuntimeSession?
    private var saveWorkout = false
    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    func begin(trackHeartRate: Bool, saveWorkout: Bool) {
        end(discard: true)
        heartRate = nil; startHR = nil; minHR = nil
        self.saveWorkout = saveWorkout
        if isDemo {
            heartRate = 68; startHR = 68; minHR = 68
            return
        }
        if trackHeartRate, HKHealthStore.isHealthDataAvailable(), startWorkout() { return }
        let r = WKExtendedRuntimeSession()
        r.delegate = self
        r.start()
        runtime = r
    }

    private func startWorkout() -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = session.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            b.delegate = self
            workout = session
            builder = b
            let now = Date()
            session.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
            return true
        } catch {
            return false
        }
    }

    /// Stops everything. `discard` throws the workout away even if saving was on.
    func end(discard: Bool = false) {
        if let r = runtime {
            if r.state == .running || r.state == .scheduled { r.invalidate() }
            runtime = nil
        }
        guard let session = workout, let b = builder else { return }
        workout = nil
        builder = nil
        session.end()
        let keep = saveWorkout && !discard
        b.endCollection(withEnd: Date()) { _, _ in
            if keep {
                b.finishWorkout { _, _ in }
            } else {
                b.discardWorkout()
            }
        }
    }

    fileprivate func gotHeartRate(_ v: Double) {
        DispatchQueue.main.async {
            self.heartRate = v
            if self.startHR == nil { self.startHR = v }
            self.minHR = min(self.minHR ?? v, v)
        }
    }
}

extension WatchRuntime: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}

extension WatchRuntime: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchRuntime: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let q = workoutBuilder.statistics(for: hr)?.mostRecentQuantity() else { return }
        gotHeartRate(q.doubleValue(for: MindfulHealth.bpm))
    }
}
