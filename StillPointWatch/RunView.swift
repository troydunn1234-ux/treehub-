import SwiftUI

/// Runs a plan: optional warm-up, then the practice, then a gentle "Well done."
struct RunView: View {
    let plan: SessionPlan
    let onClose: () -> Void

    enum Stage { case warmUp, practice, done }

    @EnvironmentObject var prefs: Prefs
    @State private var stage: Stage = .practice
    @State private var movement: MovementSession? = nil
    @State private var breath: BreathSession? = nil
    @State private var records: [SessionRecord] = []
    @State private var hrv: Double? = nil
    @State private var detail: SessionRecord? = nil
    @StateObject private var runtime = WatchRuntime.shared
    @State private var haptics = WatchHaptics()
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch stage {
            case .warmUp:
                if let m = movement { MovementRunView(session: m, onEnd: { finishWarmUp() }) }
            case .practice:
                if let b = breath { BreathRunView(session: b, heartRate: runtime.heartRate, onEnd: { b.finish() }) }
            case .done:
                NavigationStack {
                    SummaryView(records: records, startHR: runtime.startHR, endHR: runtime.heartRate, minHR: runtime.minHR,
                                hrv: hrv, detail: detail, onDone: onClose)
                }
            }
        }
        .onAppear(perform: setUp)
        .onDisappear {
            movement?.finish()
            breath?.finish()
            runtime.end(discard: false)
        }
    }

    private func setUp() {
        guard !started else { return }
        started = true
        let s = prefs.settings
        haptics.sound = s.sound
        haptics.silent = s.silentHaptics
        runtime.begin(trackHeartRate: s.trackHeartRate, saveWorkout: s.saveAsWorkout)

        let mainIsMovement = plan.practice.isMovement
        if let w = plan.warmUp, !mainIsMovement {
            let m = MovementSession(practice: w, minutes: plan.warmUpMinutes, settings: s)
            m.feedback = haptics
            m.onFinish = { ms in
                var r = ms.record(device: "Watch")
                r.kind = "movement"; r.minutesPlanned = plan.warmUpMinutes
                logRecord(r, mindful: s.logMovementAsMindful)
                DispatchQueue.main.async { startPractice() }
            }
            movement = m
            stage = .warmUp
            m.start()
        } else if mainIsMovement {
            let m = MovementSession(practice: plan.practice, minutes: plan.minutes, settings: s)
            m.feedback = haptics
            m.onFinish = { ms in
                var r = ms.record(device: "Watch")
                r.kind = "movement"; r.minutesPlanned = plan.minutes
                enrich(&r)
                logRecord(r, mindful: s.logMovementAsMindful)
                DispatchQueue.main.async { complete() }
            }
            movement = m
            stage = .warmUp
            m.start()
        } else {
            startPractice()
        }
    }

    private func finishWarmUp() {
        movement?.finish()
    }

    private func startPractice() {
        guard !plan.practice.isMovement else { complete(); return }
        let b = BreathSession(practice: plan.practice, minutes: plan.minutes, settings: prefs.settings,
                              patternOverride: plan.patternOverride)
        b.feedback = haptics
        b.onFinish = { bs in
            var r = bs.record(device: "Watch", hrStart: runtime.startHR, hrEnd: runtime.heartRate)
            r.kind = plan.practice.kind
            r.minutesPlanned = plan.minutes
            r.warmUpId = plan.warmUp?.id
            enrich(&r)
            logRecord(r, mindful: true)
            DispatchQueue.main.async { complete() }
        }
        breath = b
        withAnimation(.easeInOut(duration: 1.2)) { stage = .practice }
        b.start()
    }

    /// Fold the live heart-rate capture into a record (start, lowest, average, every ~5 s sample).
    private func enrich(_ r: inout SessionRecord) {
        guard let s = runtime.startHR else { return }
        r.hrStart = s
        r.hrEnd = runtime.heartRate
        r.hrMin = runtime.minHR
        r.hrAvg = runtime.avgHR
        let offset = r.start.timeIntervalSince(runtime.sessionStart)
        // Samples are timed from when the Watch started measuring; re-base them on this record's own start.
        let mine = runtime.samples.filter { $0.t >= offset - 1 }.map { HRSample(t: max(0, $0.t - offset), bpm: $0.bpm) }
        r.hrSamples = mine.isEmpty ? nil : mine
    }

    private func complete() {
        runtime.end(discard: false)
        let main = records.last ?? records.first
        detail = main
        withAnimation(.easeInOut(duration: 1.6)) { stage = .done }
        guard let m = main else { return }
        // HRV and breathing rate land in Health a little after the session; fetch, patch, and re-send.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MindfulHealth.shared.sessionHRV(start: m.start, end: m.end) { v in
                let value = v ?? (ProcessInfo.processInfo.arguments.contains("-demo") ? 52 : nil)
                hrv = value
                guard let value else { return }
                SessionLog.shared.update(m.id) { $0.hrv = value }
                detail = SessionLog.shared.record(m.id)
                if let updated = detail { WatchLink.shared.send(updated) }
            }
            MindfulHealth.shared.respiratoryRate(start: m.start, end: m.end) { v in
                guard let v else { return }
                SessionLog.shared.update(m.id) { $0.respiratoryRate = v }
                detail = SessionLog.shared.record(m.id)
                if let updated = detail { WatchLink.shared.send(updated) }
            }
        }
    }

    private func logRecord(_ r: SessionRecord, mindful: Bool) {
        guard r.seconds >= 10 else { return }
        records.append(r)
        SessionLog.shared.add(r)
        WatchLink.shared.send(r)
        if mindful { MindfulHealth.shared.saveMindful(start: r.start, end: r.end) }
    }
}

/// The breathing screen. Fades to near-black with only the orb after a few seconds (tap to bring controls back).
struct BreathRunView: View {
    @ObservedObject var session: BreathSession
    var heartRate: Double?
    let onEnd: () -> Void
    @EnvironmentObject var prefs: Prefs
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var dimmed = false
    @State private var showControls = false

    private var accent: Color? { PracticeLibrary.shared.tradition(session.practice.traditionId)?.tint }

    var body: some View {
        let st = session.state
        ZStack {
            DuskBackground(glow: accent ?? SP.amber)
                .opacity(dimmed || luminanceReduced ? 0.0 : 0.85)
            VStack(spacing: 4) {
                ZStack {
                    if session.pattern != nil && prefs.settings.showNumbers && !dimmed {
                        CountdownRing(progress: st.phaseProgress, color: (accent ?? SP.amber).opacity(0.7), lineWidth: 2)
                            .padding(2)
                    }
                    BreathOrb(scale: st.orb, phase: st.phase, hum: session.pattern?.hum ?? false,
                              simplified: luminanceReduced, accent: accent)
                        .padding(dimmed ? 0 : 8)
                    if prefs.settings.showNumbers && session.pattern != nil && !dimmed {
                        Text("\(Int(st.phaseRemaining.rounded(.up)))")
                            .font(SP.numbers(22)).foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .frame(maxHeight: .infinity)
                if !dimmed && !luminanceReduced {
                    Text(session.pattern == nil ? (session.cue ?? "Be still") : st.label)
                        .font(SP.serif(17, .light)).foregroundStyle(SP.ink)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .transition(.opacity)
                    if let n = st.nostril {
                        SideIndicator(left: n == .left, right: n == .right, color: SP.amber)
                    } else if let c = session.cue, session.pattern != nil {
                        Text(c).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(2).multilineTextAlignment(.center)
                    } else {
                        Text(spFormatClock(session.remaining)).font(SP.rounded(12)).foregroundStyle(SP.faint)
                    }
                }
            }
            .padding(.horizontal, 6)

            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button { session.isPaused ? session.resume() : session.pause() } label: {
                            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        }
                        Button(role: .destructive, action: onEnd) { Image(systemName: "xmark") }
                    }
                    .font(.system(size: 16))
                    Text(spFormatClock(session.remaining) + (heartRate.map { " · \(Int($0)) bpm" } ?? ""))
                        .font(SP.rounded(11)).foregroundStyle(SP.dim)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.8)) { showControls.toggle(); dimmed = false }
            scheduleDim()
        }
        .onAppear { scheduleDim() }
        .animation(.easeInOut(duration: 2.5), value: dimmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.pattern == nil ? "Silent practice" : st.label)
        .accessibilityAction(named: session.isPaused ? "Resume" : "Pause") { session.isPaused ? session.resume() : session.pause() }
        .accessibilityAction(named: "End") { onEnd() }
    }

    private func scheduleDim() {
        guard prefs.settings.dimScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard !session.isFinished else { return }
            withAnimation(.easeInOut(duration: 3)) { showControls = false; dimmed = true }
        }
    }
}

/// Warm-up / movement step player.
struct MovementRunView: View {
    @ObservedObject var session: MovementSession
    let onEnd: () -> Void

    var body: some View {
        let s = session.step
        ZStack {
            DuskBackground(glow: SP.teal).opacity(0.85)
            VStack(spacing: 2) {
                GeometryReader { g in
                    HStack(spacing: 6) {
                        PoseFigureView(motion: PoseLibrary.motion(for: s), mirrored: PoseLibrary.mirrored(for: s), lineWidth: 2.2)
                            .id(session.index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ZStack {
                            CountdownRing(progress: session.stepProgress, color: SP.teal, lineWidth: 3)
                            VStack(spacing: 0) {
                                Text("\(Int(session.stepRemaining.rounded(.up)))").font(SP.numbers(22)).foregroundStyle(SP.ink)
                                Text("\(session.index + 1)/\(session.steps.count)").font(SP.rounded(9, .semibold)).tracking(1).foregroundStyle(SP.faint)
                            }
                        }
                        .frame(width: min(64, g.size.height), height: min(64, g.size.height))
                    }
                }
                .frame(height: 78)
                Text(s.name).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(2).multilineTextAlignment(.center)
                if !s.how.isEmpty {
                    Text(s.how).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(2).multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    if s.side != nil { SideIndicator(left: s.side == "left" || s.side == "both", right: s.side == "right" || s.side == "both", color: SP.teal) }
                    Text(s.breathCue).font(SP.rounded(11)).foregroundStyle(SP.amber)
                }
                HStack(spacing: 14) {
                    Button { session.isPaused ? session.resume() : session.pause() } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button { session.skip() } label: { Image(systemName: "forward.end.fill") }
                    Button(action: onEnd) { Image(systemName: "xmark") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(SP.dim)
            }
            .padding(.horizontal, 6)
        }
    }
}

/// "Well done." with a soft bloom.
struct SummaryView: View {
    let records: [SessionRecord]
    let startHR: Double?
    let endHR: Double?
    let minHR: Double?
    let hrv: Double?
    var detail: SessionRecord? = nil
    let onDone: () -> Void
    @State private var bloom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var minutes: Double { records.reduce(0) { $0 + $1.minutes } }
    private var cycles: Int { records.reduce(0) { $0 + $1.cycles } }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [SP.amber.opacity(0.55), SP.plum.opacity(0.2), .clear],
                                             center: .center, startRadius: 2, endRadius: 60))
                        .frame(width: 110, height: 110)
                        .scaleEffect(bloom ? 1.0 : 0.4)
                        .opacity(bloom ? 1 : 0)
                    Text("Well done.").font(SP.serif(22, .light)).foregroundStyle(SP.ink)
                }
                HStack(spacing: 14) {
                    stat(String(format: "%.0f", max(1, minutes.rounded())), "MIN")
                    if cycles > 0 { stat("\(cycles)", "BREATHS") }
                }
                if let a = startHR, let b = minHR ?? endHR, a > 0 {
                    stat("\(Int(a)) → \(Int(b))", "HEART BPM")
                }
                if let h = hrv { stat("\(Int(h)) ms", "HRV") }
                let streak = SessionLog.shared.streak
                if streak > 1 { Text("\(streak) days in a row").font(SP.rounded(12)).foregroundStyle(SP.amber) }
                if let d = detail {
                    NavigationLink {
                        WatchSessionDetailView(record: d)
                    } label: {
                        Label("Details", systemImage: "waveform.path.ecg")
                            .font(SP.rounded(13)).foregroundStyle(SP.teal)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                Button("Done", action: onDone)
                    .tint(SP.amber)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
        .background(SP.dawn.opacity(0.5).ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 3.0)) { bloom = true }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(SP.numbers(20)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(9, .semibold)).tracking(1).foregroundStyle(SP.faint)
        }
    }
}
