import Foundation
import Combine

/// Plays a movement / warm-up routine step by step: auto-advance, pause, skip,
/// a haptic on every step and a double tap 3 s before switching sides.
final class MovementSession: ObservableObject {
    let practice: Practice
    let steps: [MoveStep]
    let settings: SessionSettings
    let plannedSeconds: Double

    @Published private(set) var index = 0
    @Published private(set) var stepElapsed: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var isFinished = false

    weak var feedback: BreathFeedback?
    var onFinish: ((MovementSession) -> Void)?
    private(set) var startDate = Date()

    private var timer: DispatchSourceTimer?
    private var last: Date?
    private var warnedForIndex = -1

    init(practice: Practice, minutes: Int, settings: SessionSettings) {
        self.practice = practice
        self.settings = settings
        let s = practice.scaledSteps(minutes: minutes)
        self.steps = s.isEmpty ? [MoveStep(name: practice.title, seconds: Double(max(1, minutes)) * 60)] : s
        self.plannedSeconds = self.steps.reduce(0) { $0 + $1.seconds }
    }

    var step: MoveStep { steps[min(index, steps.count - 1)] }
    var next: MoveStep? { index + 1 < steps.count ? steps[index + 1] : nil }
    var stepRemaining: Double { max(0, step.seconds - stepElapsed) }
    var stepProgress: Double { step.seconds > 0 ? min(1, stepElapsed / step.seconds) : 0 }
    var progress: Double { plannedSeconds > 0 ? min(1, elapsed / plannedSeconds) : 0 }
    var remaining: Double { max(0, plannedSeconds - elapsed) }

    func start() {
        guard timer == nil, !isFinished else { return }
        startDate = Date()
        last = Date()
        if settings.bells { feedback?.bell(.start) }
        feedback?.stepBegan(style: settings.haptics)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func pause() { guard !isFinished else { return }; isPaused = true; last = nil }
    func resume() { guard isPaused, !isFinished else { return }; isPaused = false; last = Date() }

    func skip() {
        guard !isFinished else { return }
        elapsed += stepRemaining
        advance()
    }

    func finish() {
        guard !isFinished else { return }
        timer?.cancel()
        timer = nil
        isFinished = true
        feedback?.stopAll()
        if settings.bells { feedback?.bell(.end) }
        onFinish?(self)
    }

    private func tick() {
        guard !isPaused, let l = last else { return }
        let now = Date()
        let dt = now.timeIntervalSince(l)
        last = now
        stepElapsed += dt
        elapsed += dt
        // Double tap 3 s before the routine switches to the other side.
        if let n = next, warnedForIndex != index, stepRemaining <= 3,
           let a = step.side, let b = n.side, a != b, a != "both", b != "both" {
            warnedForIndex = index
            feedback?.sideSwitchSoon(style: settings.haptics)
        }
        if stepElapsed >= step.seconds { advance() }
    }

    private func advance() {
        if index + 1 >= steps.count {
            finish()
            return
        }
        index += 1
        stepElapsed = 0
        feedback?.stepBegan(style: settings.haptics)
    }

    func record(device: String) -> SessionRecord {
        SessionRecord(practiceId: practice.id, title: practice.title, start: startDate,
                      seconds: elapsed, cycles: index + (isFinished ? 1 : 0), device: device)
    }
}

/// A chosen "warm up → then meditate" pair, or a single practice.
struct SessionPlan: Hashable, Identifiable {
    var warmUp: Practice?
    var warmUpMinutes: Int
    var practice: Practice
    var minutes: Int
    var patternOverride: BreathPattern? = nil

    var id: String { (warmUp?.id ?? "") + ">" + practice.id + "\(minutes)" }
}
