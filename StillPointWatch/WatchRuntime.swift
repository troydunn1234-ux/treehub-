import Foundation
import WatchKit
import HealthKit

/// Haptics on the wrist. Phase changes are distinct so you can breathe with eyes closed.
final class WatchHaptics: BreathFeedback {
    private let device = WKInterfaceDevice.current()
    var sound = false
    /// Vibration only: every cue is built from the silent `.click` tap. Patterns keep
    /// the phases distinct — 1 tap in, 2 taps out, 3 quick taps for a hold.
    var silent = true

    private func taps(_ n: Int, gap: Double = 0.16) {
        for i in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * gap) { [device] in device.play(.click) }
        }
    }

    func phaseBegan(_ phase: BreathPhase, duration: Double, style: HapticStyle) {
        if silent {
            guard style != .off else { return }
            switch phase {
            case .inhale: taps(1)
            case .exhale: taps(2, gap: style == .subtle ? 0.14 : 0.2)
            case .holdIn, .holdOut: taps(style == .subtle ? 1 : 3, gap: 0.1)
            case .still: break
            }
            return
        }
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
        if silent {
            switch kind {
            case .start: taps(3, gap: 0.22)
            case .interval: taps(2, gap: 0.22)
            case .end: taps(4, gap: 0.22)
            }
            return
        }
        switch kind {
        case .start: device.play(.start)
        case .interval: device.play(.notification)
        case .end: device.play(.success)
        }
    }

    func stepBegan(style: HapticStyle) {
        guard style != .off else { return }
        if silent { taps(2, gap: 0.12); return }
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
    /// One reading every ~5 s while heart rate is on (time offset from `sessionStart`, bpm).
    @Published private(set) var samples: [HRSample] = []

    private(set) var sessionStart = Date()
    private var sumHR = 0.0
    private var countHR = 0
    private var sampler: Timer?

    private let store = MindfulHealth.shared.store
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var runtime: WKExtendedRuntimeSession?
    private var saveWorkout = false
    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// Mean of every reading so far.
    var avgHR: Double? { countHR > 0 ? sumHR / Double(countHR) : nil }

    func begin(trackHeartRate: Bool, saveWorkout: Bool) {
        end(discard: true)
        heartRate = nil; startHR = nil; minHR = nil
        samples = []; sumHR = 0; countHR = 0
        sessionStart = Date()
        self.saveWorkout = saveWorkout
        // Lowering the wrist keeps Still Point in front (dimmed, Always-On) instead of going back to the clock.
        WKApplication.shared().isFrontmostTimeoutExtended = true
        if isDemo {
            heartRate = 68; startHR = 68; minHR = 68
            startSampler(demo: true)
            return
        }
        if trackHeartRate, HKHealthStore.isHealthDataAvailable(), startWorkout() {
            startSampler(demo: false)
            return
        }
        let r = WKExtendedRuntimeSession()
        r.delegate = self
        r.start()
        runtime = r
    }

    private func startSampler(demo: Bool) {
        sampler?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if demo {
                // A slow, slightly wobbly settle for screenshots.
                let elapsed = Date().timeIntervalSince(self.sessionStart)
                let v = 68 - min(8, elapsed / 30) + sin(elapsed / 7) * 1.2
                self.gotHeartRate(v)
            }
            guard let hr = self.heartRate else { return }
            let offset = Date().timeIntervalSince(self.sessionStart)
            self.samples.append(HRSample(t: (offset * 10).rounded() / 10, bpm: hr.rounded()))
            if self.samples.count > 2000 { self.samples.removeFirst(self.samples.count - 2000) }
        }
        RunLoop.main.add(t, forMode: .common)
        sampler = t
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
        WKApplication.shared().isFrontmostTimeoutExtended = false
        sampler?.invalidate()
        sampler = nil
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
            self.sumHR += v
            self.countHR += 1
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
