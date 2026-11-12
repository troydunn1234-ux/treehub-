import SwiftUI
import UIKit

/// Runs a plan on iPhone: optional warm-up, then the practice, then "Well done."
struct PhoneRunView: View {
    let plan: SessionPlan
    let onClose: () -> Void

    enum Stage { case warmUp, practice, done }
    @EnvironmentObject var prefs: Prefs
    @State private var stage: Stage = .practice
    @State private var movement: MovementSession? = nil
    @State private var breath: BreathSession? = nil
    @State private var records: [SessionRecord] = []
    @State private var haptics = PhoneHaptics()
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch stage {
            case .warmUp:
                if let m = movement { PhoneMovementView(session: m) { m.finish() } }
            case .practice:
                if let b = breath { PhoneBreathView(session: b) { b.finish() } }
            case .done:
                PhoneSummaryView(records: records, onDone: onClose)
            }
        }
        .statusBarHidden(stage != .done)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            setUp()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            movement?.finish()
            breath?.finish()
        }
    }

    private func setUp() {
        guard !started else { return }
        started = true
        let s = prefs.settings
        if plan.practice.isMovement {
            runMovement(plan.practice, minutes: plan.minutes) { complete() }
        } else if let w = plan.warmUp {
            runMovement(w, minutes: plan.warmUpMinutes) { startPractice() }
        } else {
            startPractice()
        }
        _ = s
    }

    private func runMovement(_ p: Practice, minutes: Int, then next: @escaping () -> Void) {
        let s = prefs.settings
        let m = MovementSession(practice: p, minutes: minutes, settings: s)
        m.feedback = haptics
        m.onFinish = { ms in
            var r = ms.record(device: "iPhone")
            r.kind = "movement"; r.minutesPlanned = minutes
            log(r, mindful: s.logMovementAsMindful)
            DispatchQueue.main.async { next() }
        }
        movement = m
        stage = .warmUp
        m.start()
    }

    private func startPractice() {
        let b = BreathSession(practice: plan.practice, minutes: plan.minutes, settings: prefs.settings,
                              patternOverride: plan.patternOverride)
        b.feedback = haptics
        b.onFinish = { bs in
            var r = bs.record(device: "iPhone")
            r.kind = plan.practice.kind; r.minutesPlanned = plan.minutes; r.warmUpId = plan.warmUp?.id
            log(r, mindful: true)
            DispatchQueue.main.async { complete() }
        }
        breath = b
        withAnimation(.easeInOut(duration: 1.2)) { stage = .practice }
        b.start()
    }

    private func complete() {
        UIApplication.shared.isIdleTimerDisabled = false
        withAnimation(.easeInOut(duration: 1.8)) { stage = .done }
    }

    private func log(_ r: SessionRecord, mindful: Bool) {
        guard r.seconds >= 10 else { return }
        records.append(r)
        SessionLog.shared.add(r)
        Reviews.noteWin()
        if mindful { MindfulHealth.shared.saveMindful(start: r.start, end: r.end) }
    }
}

struct PhoneBreathView: View {
    @ObservedObject var session: BreathSession
    let onEnd: () -> Void
    @EnvironmentObject var prefs: Prefs
    @State private var dimmed = false
    @State private var lastTouch = Date()

    private var accent: Color? { PracticeLibrary.shared.tradition(session.practice.traditionId)?.tint }

    var body: some View {
        let st = session.state
        ZStack {
            DuskBackground(glow: accent ?? SP.amber).opacity(dimmed ? 0 : 1)
            Motes(color: accent ?? SP.amber).opacity(dimmed ? 0 : 0.8)
            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text(session.practice.title).font(SP.serif(20, .light)).foregroundStyle(SP.dim)
                    if prefs.settings.showNumbers {
                        Text(spFormatClock(session.remaining)).font(SP.rounded(14)).foregroundStyle(SP.faint).monospacedDigit()
                    }
                }
                .opacity(dimmed ? 0 : 1)
                .padding(.top, 30)

                Spacer()
                ZStack {
                    if session.pattern != nil && prefs.settings.showNumbers {
                        CountdownRing(progress: st.phaseProgress, color: (accent ?? SP.amber).opacity(0.55), lineWidth: 2)
                            .frame(width: 300, height: 300)
                            .opacity(dimmed ? 0.25 : 1)
                    }
                    BreathOrb(scale: st.orb, phase: st.phase, hum: session.pattern?.hum ?? false, accent: accent)
                        .frame(width: 290, height: 290)
                    if prefs.settings.showNumbers && session.pattern != nil {
                        Text("\(Int(st.phaseRemaining.rounded(.up)))")
                            .font(SP.numbers(40)).foregroundStyle(Color.white.opacity(dimmed ? 0.35 : 0.85))
                    }
                }
                Spacer()

                VStack(spacing: 12) {
                    Text(session.pattern == nil ? (session.cue ?? "Be still") : st.label)
                        .font(SP.serif(28, .light)).foregroundStyle(SP.ink.opacity(dimmed ? 0.5 : 1))
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 1.2), value: st.label)
                    if let n = st.nostril {
                        SideIndicator(left: n == .left, right: n == .right, color: SP.amber)
                    }
                    if let c = session.cue, session.pattern != nil {
                        Text(c).font(SP.rounded(15)).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                            .padding(.horizontal, 30).opacity(dimmed ? 0 : 1)
                    }
                }
                .frame(minHeight: 110)

                HStack(spacing: 40) {
                    Button { session.isPaused ? session.resume() : session.pause() } label: {
                        Image(systemName: session.isPaused ? "play" : "pause")
                            .font(.system(size: 20, weight: .light)).frame(width: 56, height: 56)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                    Button(action: onEnd) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .light)).frame(width: 56, height: 56)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("End session")
                }
                .foregroundStyle(SP.ink)
                .opacity(dimmed ? 0 : 1)
                .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { wake() }
        .onAppear { wake() }
        .animation(.easeInOut(duration: 3), value: dimmed)
    }

    private func wake() {
        dimmed = false
        let stamp = Date()
        lastTouch = stamp
        guard prefs.settings.dimScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if lastTouch == stamp && !session.isPaused && !session.isFinished { dimmed = true }
        }
    }
}

struct PhoneMovementView: View {
    @ObservedObject var session: MovementSession
    let onEnd: () -> Void

    var body: some View {
        let s = session.step
        ZStack {
            DuskBackground(glow: SP.teal)
            VStack(spacing: 22) {
                HStack {
                    Text("WARM UP · STEP \(session.index + 1) OF \(session.steps.count)")
                        .font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                    Spacer()
                    Text(spFormatClock(session.remaining)).font(SP.rounded(13)).foregroundStyle(SP.faint).monospacedDigit()
                }
                .padding(.top, 30)
                Spacer()
                ZStack(alignment: .topTrailing) {
                    PoseFigureView(motion: PoseLibrary.motion(for: s), mirrored: PoseLibrary.mirrored(for: s), lineWidth: 3.5)
                        .id(session.index)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                    ZStack {
                        CountdownRing(progress: session.stepProgress, color: SP.teal, lineWidth: 3)
                        VStack(spacing: 0) {
                            Text("\(Int(session.stepRemaining.rounded(.up)))").font(SP.numbers(30)).foregroundStyle(SP.ink)
                            Text("SEC").font(SP.rounded(9, .semibold)).tracking(1.4).foregroundStyle(SP.faint)
                        }
                    }
                    .frame(width: 84, height: 84)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(session.stepRemaining.rounded(.up))) seconds left")
                VStack(spacing: 10) {
                    Text(s.name).font(SP.serif(34, .light)).foregroundStyle(SP.ink).multilineTextAlignment(.center)
                    if !s.how.isEmpty {
                        Text(s.how).font(SP.rounded(16)).foregroundStyle(SP.dim).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                    HStack(spacing: 14) {
                        if s.side != nil {
                            SideIndicator(left: s.side == "left" || s.side == "both", right: s.side == "right" || s.side == "both", color: SP.teal)
                        }
                        Text(s.breathCue).font(SP.rounded(15)).foregroundStyle(SP.amber)
                    }
                    if let n = session.next {
                        Text("Next: \(n.name)\(n.sideLetter.map { " · \($0)" } ?? "")").font(SP.rounded(13)).foregroundStyle(SP.faint)
                    }
                }
                Spacer()
                HStack(spacing: 34) {
                    roundButton(session.isPaused ? "play" : "pause", label: session.isPaused ? "Resume" : "Pause") {
                        session.isPaused ? session.resume() : session.pause()
                    }
                    roundButton("forward.end", label: "Next step") { session.skip() }
                    roundButton("xmark", label: "End warm-up", action: onEnd)
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(SP.ink)
                .frame(width: 56, height: 56).background(Circle().fill(.ultraThinMaterial))
        }
        .accessibilityLabel(label)
    }
}

struct PhoneSummaryView: View {
    let records: [SessionRecord]
    let onDone: () -> Void
    @State private var bloom = false
    @State private var confirmDiscard = false
    /// Under a minute usually means a false start, so ask instead of just saving.
    private var short: Bool { records.reduce(0) { $0 + $1.seconds } < 60 }

    private func discard() {
        for r in records { SessionLog.shared.remove(r.id) }
        onDone()
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var minutes: Double { records.reduce(0) { $0 + $1.minutes } }
    private var cycles: Int { records.reduce(0) { $0 + $1.cycles } }

    var body: some View {
        ZStack {
            SP.dawn.ignoresSafeArea()
            Grain(opacity: 0.06).ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.7), SP.amber.opacity(0.45), .clear],
                                             center: .center, startRadius: 4, endRadius: 150))
                        .frame(width: 300, height: 300)
                        .scaleEffect(bloom ? 1 : 0.3)
                        .opacity(bloom ? 1 : 0)
                    Text("Well done.").font(SP.serif(44, .light)).foregroundStyle(SP.ink)
                }
                HStack(spacing: 40) {
                    stat(String(format: "%.0f", max(1, minutes.rounded())), "minutes")
                    if cycles > 0 { stat("\(cycles)", "breaths") }
                    let streak = SessionLog.shared.streak
                    if streak > 0 { stat("\(streak)", streak == 1 ? "day" : "days in a row") }
                }
                Spacer()
                if short && !records.isEmpty {
                    Text("That was under a minute. Keep it in your journey?")
                        .font(SP.rounded(14)).foregroundStyle(SP.ink.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Button(action: onDone) {
                    Text(short && !records.isEmpty ? "Keep it" : "Return").font(SP.rounded(17, .medium)).foregroundStyle(SP.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .padding(.horizontal, 40)
                if !records.isEmpty {
                    Button {
                        if short { discard() } else { confirmDiscard = true }
                    } label: {
                        Text("Discard this session").font(SP.rounded(15)).foregroundStyle(SP.ink.opacity(0.7))
                            .padding(.vertical, 8)
                    }
                }
                Spacer().frame(height: 20)
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 3.2)) { bloom = true } }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discard() }
        } message: { Text("It's removed from your journey and from Mindful Minutes in Apple Health.") }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(SP.numbers(34)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(12)).foregroundStyle(SP.ink.opacity(0.7))
        }
    }
}
