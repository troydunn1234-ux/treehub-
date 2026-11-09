import Foundation
import Combine

enum BreathPhase: String, Equatable {
    case inhale, holdIn, exhale, holdOut, still

    var label: String {
        switch self {
        case .inhale: return "Breathe in"
        case .holdIn: return "Hold"
        case .exhale: return "Breathe out"
        case .holdOut: return "Rest"
        case .still: return "Be still"
        }
    }
}

enum NostrilSide: String { case left = "L", right = "R" }

/// Where the session is right now. Pure value, recomputed from elapsed time so it never drifts.
struct BreathState: Equatable {
    var phase: BreathPhase = .still
    var phaseProgress: Double = 0      // 0…1 within the phase
    var phaseRemaining: Double = 0     // seconds left in the phase
    var phaseIndex: Int = 0            // increases every phase; used to detect changes
    var cycle: Int = 0                 // completed breaths
    var orb: Double = 0.62             // 0.55 (empty) … 1.0 (full)
    var nostril: NostrilSide? = nil
    var topUp = false                  // physiological sigh second sip
    var label: String = BreathPhase.still.label
}

struct BreathTimeline {
    let pattern: BreathPattern?

    /// Ordered non-zero phases in one breath.
    var phases: [(BreathPhase, Double)] {
        guard let p = pattern else { return [] }
        return [(.inhale, p.inhale), (.holdIn, p.holdIn), (.exhale, p.exhale), (.holdOut, p.holdOut)].filter { $0.1 > 0 }
    }

    func state(at t: Double) -> BreathState {
        guard let p = pattern, p.cycleLength > 0 else {
            // Silent practice: a slow, gentle glow (about 10 s per swell), no phase changes.
            let s = (sin(t / 10 * 2 * .pi - .pi / 2) + 1) / 2
            var st = BreathState()
            st.orb = 0.66 + 0.16 * s
            st.phaseProgress = s
            return st
        }
        let L = p.cycleLength
        let cycle = Int(floor(max(0, t) / L))
        var within = max(0, t) - Double(cycle) * L
        var st = BreathState()
        st.cycle = cycle
        let list = phases
        var idx = 0
        for (i, ph) in list.enumerated() {
            if within < ph.1 || i == list.count - 1 {
                idx = i
                break
            }
            within -= ph.1
        }
        let (phase, dur) = list[idx]
        let prog = min(1, max(0, within / dur))
        st.phase = phase
        st.phaseProgress = prog
        st.phaseRemaining = max(0, dur - within)
        st.phaseIndex = cycle * list.count + idx
        let ease = (1 - cos(prog * .pi)) / 2
        switch phase {
        case .inhale: st.orb = 0.55 + 0.45 * ease
        case .holdIn: st.orb = 1.0
        case .exhale: st.orb = 1.0 - 0.45 * ease
        case .holdOut, .still: st.orb = 0.55
        }
        st.label = phase.label
        if p.sigh, phase == .inhale, prog > 0.7 {
            st.topUp = true
            st.label = "Sip in more"
        }
        if p.hum, phase == .exhale { st.label = "Hum out" }
        if p.nostril {
            // Nadi Shodhana: in left, out right, in right, out left…
            let inSide: NostrilSide = cycle % 2 == 0 ? .left : .right
            let outSide: NostrilSide = inSide == .left ? .right : .left
            switch phase {
            case .inhale, .holdIn: st.nostril = inSide
            case .exhale, .holdOut: st.nostril = outSide
            case .still: st.nostril = nil
            }
            if phase == .inhale { st.label = "In · \(inSide == .left ? "left" : "right")" }
            if phase == .exhale { st.label = "Out · \(outSide == .left ? "left" : "right")" }
        }
        return st
    }
}

/// Things a session wants to feel/hear. Implemented per platform.
protocol BreathFeedback: AnyObject {
    func phaseBegan(_ phase: BreathPhase, duration: Double, style: HapticStyle)
    func exhaleTick(style: HapticStyle)
    func topUp(style: HapticStyle)
    func bell(_ kind: BellKind)
    func stopAll()
    /// Movement routines: a new step began.
    func stepBegan(style: HapticStyle)
    /// Movement routines: about to switch sides (3 s warning) — a distinct double tap.
    func sideSwitchSoon(style: HapticStyle)
}

enum BellKind { case start, interval, end }

/// Runs one session: a precise timer drives state + feedback. Works the same on Watch and iPhone.
final class BreathSession: ObservableObject {
    let practice: Practice
    let pattern: BreathPattern?
    let settings: SessionSettings
    /// Planned length in seconds.
    let plannedSeconds: Double

    @Published private(set) var state = BreathState()
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var isFinished = false
    @Published private(set) var cue: String? = nil

    weak var feedback: BreathFeedback?
    var onFinish: ((BreathSession) -> Void)?

    private let timeline: BreathTimeline
    private var timer: DispatchSourceTimer?
    private var startedAt: Date?
    private var accumulated: Double = 0
    private var lastPhaseIndex = -1
    private var lastTickSecond = -1
    private var lastInterval = 0
    private var didTopUp = false
    private(set) var startDate = Date()

    init(practice: Practice, minutes: Int, settings: SessionSettings, patternOverride: BreathPattern? = nil) {
        self.practice = practice
        self.settings = settings
        let pat = patternOverride ?? practice.pattern
        self.pattern = pat
        self.timeline = BreathTimeline(pattern: pat)
        if settings.mode == .cycles, let p = pat, p.cycleLength > 0 {
            plannedSeconds = Double(max(1, settings.cycles)) * p.cycleLength
        } else {
            plannedSeconds = Double(max(1, minutes)) * 60
        }
        state = timeline.state(at: 0)
    }

    var remaining: Double { max(0, plannedSeconds - elapsed) }
    var progress: Double { plannedSeconds > 0 ? min(1, elapsed / plannedSeconds) : 0 }
    var completedCycles: Int { pattern == nil ? 0 : state.cycle }

    func start() {
        guard timer == nil, !isFinished else { return }
        startDate = Date()
        startedAt = Date()
        if settings.bells { feedback?.bell(.start) }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func pause() {
        guard !isPaused, !isFinished, let s = startedAt else { return }
        accumulated += Date().timeIntervalSince(s)
        startedAt = nil
        isPaused = true
        feedback?.stopAll()
    }

    func resume() {
        guard isPaused, !isFinished else { return }
        startedAt = Date()
        isPaused = false
        lastPhaseIndex = -1 // re-announce the current phase
    }

    /// Ends early (or on time). Safe to call twice.
    func finish() {
        guard !isFinished else { return }
        if let s = startedAt { accumulated += Date().timeIntervalSince(s) }
        startedAt = nil
        elapsed = min(accumulated, plannedSeconds)
        timer?.cancel()
        timer = nil
        isFinished = true
        feedback?.stopAll()
        if settings.bells { feedback?.bell(.end) }
        onFinish?(self)
    }

    private func tick() {
        guard !isPaused, let s = startedAt else { return }
        let t = accumulated + Date().timeIntervalSince(s)
        elapsed = t
        if t >= plannedSeconds {
            finish()
            return
        }
        let st = timeline.state(at: t)
        if st != state { state = st }
        let newCue = practice.cue(at: t)
        if newCue != cue { cue = newCue }

        let style = settings.haptics
        if pattern != nil, st.phaseIndex != lastPhaseIndex {
            lastPhaseIndex = st.phaseIndex
            didTopUp = false
            let dur = timeline.phases.first(where: { $0.0 == st.phase })?.1 ?? 0
            feedback?.phaseBegan(st.phase, duration: dur, style: style)
        }
        if st.topUp, !didTopUp {
            didTopUp = true
            feedback?.topUp(style: style)
        }
        if settings.exhaleTicks, st.phase == .exhale {
            let sec = Int(t)
            if sec != lastTickSecond, st.phaseProgress > 0.05 {
                lastTickSecond = sec
                feedback?.exhaleTick(style: style)
            }
        }
        if settings.intervalMinutes > 0 {
            let n = Int(t / Double(settings.intervalMinutes * 60))
            if n > lastInterval {
                lastInterval = n
                feedback?.bell(.interval)
            }
        }
    }

    func record(device: String, hrStart: Double? = nil, hrEnd: Double? = nil, hrv: Double? = nil) -> SessionRecord {
        SessionRecord(practiceId: practice.id, title: practice.title, start: startDate,
                      seconds: elapsed, cycles: completedCycles, hrStart: hrStart, hrEnd: hrEnd, hrv: hrv, device: device)
    }
}
