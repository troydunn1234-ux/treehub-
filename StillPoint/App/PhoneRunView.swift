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
    @State private var guide = GuidedFeedback()
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch stage {
            case .warmUp:
                if let m = movement { PhoneMovementView(session: m) { m.finish() } }
            case .practice:
                if let b = breath { PhoneBreathView(session: b, treeName: plan.treeName) { b.finish() } }
            case .done:
                PhoneSummaryView(records: records, treeName: plan.treeName, treeID: plan.treeID, onDone: onClose)
            }
        }
        .statusBarHidden(stage != .done)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Health access is asked for here, the first time a session runs, rather than at launch.
            MindfulHealth.shared.requestAuthorization()
            VoiceGuide.shared.begin()
            setUp()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            movement?.finish()
            breath?.finish()
            VoiceGuide.shared.end()
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
        guide.attach(m)
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
        guide.attach(b)
        b.onFinish = { bs in
            var r = bs.record(device: "iPhone")
            r.kind = plan.practice.kind; r.minutesPlanned = plan.minutes; r.warmUpId = plan.warmUp?.id
            if let tree = plan.treeName {
                if r.notes == nil { r.notes = "Breathing with \(tree)" }
                r.treeName = tree
                r.treeID = plan.treeID
            }
            log(r, mindful: true)
            DispatchQueue.main.async { complete() }
        }
        breath = b
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 1.2)) { stage = .practice }
        b.start()
    }

    private func complete() {
        UIApplication.shared.isIdleTimerDisabled = false
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 1.8)) { stage = .done }
    }

    private func log(_ r: SessionRecord, mindful: Bool) {
        guard r.seconds >= 10 else { return }
        records.append(r)
        SessionLog.shared.add(r)
        // Breathing with a Rootbound tree: publish now and fill heart data from Health, so it shows under the tree.
        if r.treeID != nil || r.treeName != nil { DispatchQueue.main.async { StillPointWellness.treeSessionFinished() } }
        // Fill heart rate, HRV and breathing rate from Apple Health as they arrive (the results screen updates live).
        let id = r.id
        DispatchQueue.main.async { StillPointWellness.sessionFinished(id) }
        Reviews.noteWin()
        if mindful { MindfulHealth.shared.saveMindful(start: r.start, end: r.end) }
        // Movement routines also count as exercise in Health.
        if let type = MindfulHealth.activity(for: r.practiceId) {
            MindfulHealth.shared.saveWorkout(type, start: r.start, end: r.end, title: r.title)
        }
    }
}

struct PhoneBreathView: View {
    @ObservedObject var session: BreathSession
    /// "Breathing with <tree>" when Rootbound started the session.
    var treeName: String? = nil
    let onEnd: () -> Void
    @EnvironmentObject var prefs: Prefs
    @State private var dimmed = false
    @State private var lastTouch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color? { PracticeLibrary.shared.tradition(session.practice.traditionId)?.tint }

    @ObservedObject private var voice = VoiceGuide.shared

    /// Soft phase colour for the background wash: teal in, sand on hold, lavender out.
    private func wash(_ phase: BreathPhase) -> Color {
        switch phase {
        case .inhale, .still: return accent ?? SP.teal
        case .holdIn: return SP.amber
        case .exhale: return SP.violet
        case .holdOut: return SP.indigo
        }
    }

    var body: some View {
        let st = session.state
        let paced = session.pattern != nil
        let headline = paced ? st.label : (session.cue ?? "Be still")
        ZStack {
            DuskBackground(glow: accent ?? SP.indigo).opacity(dimmed ? 0 : 1)
            // One soft wash per phase, cross-faded (a fade, not movement, so it stays with Reduce Motion).
            ZStack {
                ForEach([BreathPhase.inhale, .holdIn, .exhale, .holdOut], id: \.self) { ph in
                    RadialGradient(colors: [wash(ph), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.45), startRadius: 20, endRadius: 420)
                        .opacity(washPhase(st.phase) == ph ? (dimmed ? 0.06 : 0.20) : 0)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: reduceMotion ? 0.8 : 2.0), value: st.phase)
            .accessibilityHidden(true)
            if !reduceMotion { Motes(count: 16, color: accent ?? SP.accent).opacity(dimmed ? 0 : 0.6) }
            VStack(spacing: SP.s4) {
                // Header: what you're doing, how long is left, overall progress.
                VStack(spacing: SP.s2) {
                    if let treeName {
                        Label("Breathing with \(treeName)", systemImage: "tree")
                            .font(.footnote.weight(.medium)).foregroundStyle(Color(spHex: "#8CCB7E"))
                    }
                    Text(session.practice.title).font(SP.serif(20, .light)).foregroundStyle(SP.ink.opacity(0.9))
                        .multilineTextAlignment(.center).lineLimit(2)
                    if prefs.settings.showNumbers {
                        HStack(spacing: SP.s2) {
                            Capsule().fill(Color.white.opacity(0.10)).frame(width: 120, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(SP.accent.opacity(0.8)).frame(width: 120 * CGFloat(session.progress), height: 4)
                                }
                                .accessibilityHidden(true)
                            Text(spFormatClock(session.remaining)).font(.footnote).monospacedDigit().foregroundStyle(SP.dim)
                                .contentTransition(.numericText())
                                .accessibilityLabel("\(Int(session.remaining.rounded(.up) / 60)) minutes \(Int(session.remaining.rounded(.up)) % 60) seconds left")
                        }
                    }
                }
                .opacity(dimmed ? 0 : 1)
                .padding(.top, SP.s6)
                .padding(.horizontal, SP.screenPadding)
                // Big text: the practice's name gets its two lines before the spacers take the room (at AX3 the
                // fixed-size orb left it one line, cut short to "Resonance Breathi…").
                .layoutPriority(1)

                Spacer(minLength: SP.s2)
                ZStack {
                    // The ring follows "Show numbers"; with Reduce Motion it always shows, as it carries the rhythm.
                    if paced && (prefs.settings.showNumbers || reduceMotion) {
                        CountdownRing(progress: st.phaseProgress, color: (accent ?? SP.accent).opacity(0.6), lineWidth: 2.5)
                            .frame(width: 304, height: 304)
                            .opacity(dimmed ? 0.25 : 1)
                    }
                    // Reduce Motion: the orb keeps one size and its glow brightens and softens with the breath;
                    // the ring, colour and words carry the rhythm instead.
                    BreathOrb(scale: reduceMotion ? 0.82 : st.orb, phase: st.phase, hum: session.pattern?.hum ?? false, accent: accent)
                        .frame(width: 290, height: 290)
                        .opacity(reduceMotion ? 0.5 + 0.5 * min(1, max(0, (st.orb - 0.55) / 0.45)) : 1)
                    if prefs.settings.showNumbers && paced {
                        Text("\(Int(st.phaseRemaining.rounded(.up)))")
                            .font(SP.numbers(44)).foregroundStyle(Color.white.opacity(dimmed ? 0.35 : 0.9))
                            .contentTransition(.numericText(countsDown: true))
                            .animation(reduceMotion ? nil : .snappy, value: Int(st.phaseRemaining.rounded(.up)))
                            .accessibilityHidden(true)
                    }
                }
                // A wide, soft glow that swells and settles with the orb, at this practice's own pace.
                .background {
                    BreathAura(level: st.orb, tint: accent ?? SP.teal, quiet: dimmed)
                        .frame(width: 470, height: 470)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: SP.s2)

                VStack(spacing: SP.s3) {
                    Text(headline)
                        .font(SP.serif(30, .light)).foregroundStyle(SP.ink.opacity(dimmed ? 0.5 : 1))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SP.screenPadding)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: headline)
                        .accessibilityAddTraits(.updatesFrequently)
                    if let n = st.nostril {
                        SideIndicator(left: n == .left, right: n == .right, color: SP.accent)
                    }
                    if let c = session.cue, paced {
                        Text(c).font(.body).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, SP.s8).opacity(dimmed ? 0 : 1)
                    }
                }
                .frame(minHeight: 110)

                HStack(spacing: SP.s8) {
                    SPRoundControl(icon: voice.on ? "speaker.wave.2.fill" : "speaker.slash.fill", title: String(localized: "Voice"),
                                   spoken: String(localized: "Voice guide"),
                                   value: voice.on ? String(localized: "On") : String(localized: "Off")) {
                        voice.toggle()
                    }
                    .accessibilityHint(Text("Speaks each step and counts the breath"))
                    SPRoundControl(icon: session.isPaused ? "play.fill" : "pause.fill",
                                   title: session.isPaused ? String(localized: "Resume") : String(localized: "Pause"), prominent: true) {
                        session.isPaused ? session.resume() : session.pause()
                        wake()
                    }
                    SPRoundControl(icon: "stop.fill", title: String(localized: "End"), action: onEnd)
                }
                .sensoryFeedback(.selection, trigger: session.isPaused)
                .opacity(dimmed ? 0 : 1)
                .padding(.bottom, SP.s6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { wake() }
        .onAppear { wake() }
        .animation(.easeInOut(duration: 3), value: dimmed)
    }

    /// Which wash is lit: "still" (silent practice) shares the in-breath colour.
    private func washPhase(_ phase: BreathPhase) -> BreathPhase { phase == .still ? .inhale : phase }

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
    @ObservedObject private var voice = VoiceGuide.shared

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
                        .fixedSize(horizontal: false, vertical: true)
                    if !s.how.isEmpty {
                        // Long instructions scroll here rather than getting cut off on smaller phones.
                        ScrollView(showsIndicators: false) {
                            Text(s.how).font(SP.rounded(16)).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 24)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: 150)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 14) {
                        if s.side != nil {
                            SideIndicator(left: s.side == "left" || s.side == "both", right: s.side == "right" || s.side == "both", color: SP.teal)
                        }
                        Text(s.breathCue).font(SP.rounded(15)).foregroundStyle(SP.accent)
                    }
                    if let n = session.next {
                        Text("Next: \(n.name)\(n.sideLetter.map { " · \($0)" } ?? "")").font(SP.rounded(13)).foregroundStyle(SP.faint)
                    }
                }
                Spacer()
                HStack(spacing: SP.s4) {
                    roundButton(session.isPaused ? "play.fill" : "pause.fill", label: session.isPaused ? String(localized: "Resume") : String(localized: "Pause")) {
                        session.isPaused ? session.resume() : session.pause()
                    }
                    roundButton("forward.end.fill", label: String(localized: "Next")) { session.skip() }
                    SPRoundControl(icon: voice.on ? "speaker.wave.2.fill" : "speaker.slash.fill", title: String(localized: "Voice"),
                                   spoken: String(localized: "Voice guide"),
                                   value: voice.on ? String(localized: "On") : String(localized: "Off")) {
                        voice.toggle()
                    }
                    .accessibilityHint(Text("Speaks each step and counts the breath"))
                    roundButton("stop.fill", label: String(localized: "End"), action: onEnd)
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        SPRoundControl(icon: icon, title: label, action: action)
    }
}

struct PhoneSummaryView: View {
    let records: [SessionRecord]
    /// Set when Rootbound started the session for a tree.
    var treeName: String? = nil
    var treeID: String? = nil
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

    /// The session to show results for: the practice itself rather than its warm-up.
    private var main: SessionRecord? { records.last(where: { !$0.isMovement }) ?? records.last }
    private var tint: Color {
        let lib = PracticeLibrary.shared
        return main.flatMap { lib.practice($0.practiceId) }.flatMap { lib.tradition($0.traditionId) }?.tint ?? SP.teal
    }

    private var title: String? { main.flatMap { PracticeLibrary.shared.practice($0.practiceId)?.title } ?? main?.title }

    var body: some View {
        ZStack {
            SP.dawn.ignoresSafeArea()
            RadialGradient(colors: [tint.opacity(0.25), .clear], center: UnitPoint(x: 0.5, y: 0.12), startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
            Grain(opacity: 0.05).ignoresSafeArea()
            ScrollView {
                VStack(spacing: SP.s6) {
                    VStack(spacing: SP.s2) {
                        ZStack {
                            Circle()
                                .fill(RadialGradient(colors: [Color.white.opacity(0.55), SP.accent.opacity(0.35), .clear],
                                                     center: .center, startRadius: 4, endRadius: 110))
                                .frame(width: 210, height: 210)
                                .scaleEffect(bloom ? 1 : 0.4)
                                .opacity(bloom ? 1 : 0)
                                .accessibilityHidden(true)
                            VStack(spacing: SP.s1) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white)
                                    .symbolEffect(.bounce, value: reduceMotion ? false : bloom)
                                    .accessibilityHidden(true)
                                Text("Well done.").font(SP.serif(40, .light)).foregroundStyle(SP.ink)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                        // The finish: rings spread out like a stone dropped into still water (none with Reduce Motion).
                        .background {
                            CalmRipple(tint: tint, rings: 3, duration: 3.0)
                                .frame(width: 340, height: 340)
                        }
                        if let title {
                            Text(title).font(.subheadline).foregroundStyle(SP.ink.opacity(0.8)).multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, SP.s6)

                    HStack(spacing: 0) {
                        stat(String(format: "%.0f", max(1, minutes.rounded())), String(localized: "minutes"))
                        if cycles > 0 { divider; stat("\(cycles)", String(localized: "breaths")) }
                        let streak = SessionLog.shared.streak
                        if streak > 0 { divider; stat("\(streak)", streak == 1 ? String(localized: "day") : String(localized: "days in a row")) }
                    }
                    .padding(.vertical, SP.s3)
                    .background(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).fill(SP.nightBottom.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .padding(.horizontal, SP.screenPadding)

                    if let m = main, !short {
                        VStack(alignment: .leading, spacing: SP.s3) {
                            Label("Your results", systemImage: "waveform.path.ecg")
                                .font(.headline).foregroundStyle(SP.ink)
                            SessionResultsPanel(recordId: m.id, tint: tint)
                        }
                        .padding(SP.s4)
                        .background(RoundedRectangle(cornerRadius: SP.radius + 4, style: .continuous).fill(SP.nightBottom.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: SP.radius + 4, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .padding(.horizontal, SP.s4)
                    }
                    if !short && !records.isEmpty {
                        // Rootbound link: back to the tree you just breathed with, or out to hug one.
                        RootboundLinkCard(title: treeName.map { "Back to \($0) in Rootbound" } ?? "Go hug a tree",
                                          subtitle: treeName == nil ? "Log a hug in Rootbound. It counts here too." : "This breath is saved under the tree, with your heart data.",
                                          url: treeName == nil ? WellnessLinks.hugLogger
                                              : treeID.map { WellnessLinks.rootboundTree($0) } ?? WellnessLinks.rootboundHome)
                            .padding(.horizontal, SP.screenPadding)
                    }
                    if short && !records.isEmpty {
                        Text("That was under a minute. Keep it in your journey?")
                            .font(.subheadline).foregroundStyle(SP.ink.opacity(0.85))
                            .multilineTextAlignment(.center).padding(.horizontal, SP.s8)
                    }
                    VStack(spacing: SP.s2) {
                        Button(action: onDone) {
                            Text(short && !records.isEmpty ? "Keep it" : "Done")
                        }
                        .buttonStyle(SPPrimaryButtonStyle())
                        .sensoryFeedback(.success, trigger: bloom)
                        if !records.isEmpty {
                            Button(role: .destructive) {
                                if short { discard() } else { confirmDiscard = true }
                            } label: {
                                Text("Discard this session").font(.subheadline).foregroundStyle(SP.ink.opacity(0.7))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, SP.s8)
                    Spacer().frame(height: SP.s4)
                }
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 2.4)) { bloom = true } }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discard() }
        } message: { Text("It's removed from your journey and from Mindful Minutes in Apple Health.") }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 34).accessibilityHidden(true)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(SP.numbers(32)).foregroundStyle(SP.ink).contentTransition(.numericText())
            Text(l).font(.caption).foregroundStyle(SP.ink.opacity(0.72)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
