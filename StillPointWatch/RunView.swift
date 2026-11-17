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
    /// The HRV lookup came back empty (or never answered): the summary says so instead of waiting for good.
    @State private var hrvMissing = false
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
                                hrv: hrv, hrvMissing: hrvMissing, detail: detail, onDone: onClose)
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
        r.calmSeconds = SessionRecord.calmSeconds(samples: r.hrSamples, start: r.hrStart, total: r.seconds)
    }

    private func complete() {
        runtime.end(discard: false)
        let main = records.last ?? records.first
        detail = main
        withAnimation(.easeInOut(duration: 1.6)) { stage = .done }
        // Nothing was saved (too short), so there is no HRV to wait for.
        guard let m = main else { hrvMissing = true; return }
        // Never leave the HRV placeholder up for good: stop waiting after 3 minutes even if Health never answers.
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            if hrv == nil { hrvMissing = true }
        }
        // HRV and breathing rate land in Health a little after the session; fetch, patch, and re-send.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MindfulHealth.shared.sessionHRV(start: m.start, end: m.end) { v in
                let value = v ?? (ProcessInfo.processInfo.arguments.contains("-demo") ? 52 : nil)
                hrv = value
                // Health had no HRV for this session: show "No HRV reading" rather than a placeholder forever.
                guard let value else { hrvMissing = true; return }
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
        // Movement routines count as exercise (unless the whole session is already saved as a workout).
        if !prefs.settings.saveAsWorkout, let type = MindfulHealth.activity(for: r.practiceId) {
            MindfulHealth.shared.saveWorkout(type, start: r.start, end: r.end, title: r.title)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color? { PracticeLibrary.shared.tradition(session.practice.traditionId)?.tint }

    var body: some View {
        let st = session.state
        ZStack {
            DuskBackground(glow: accent ?? SP.indigo)
                .opacity(luminanceReduced ? 0.0 : 0.85)
            VStack(spacing: 4) {
                ZStack {
                    if session.pattern != nil && prefs.settings.showNumbers && !dimmed {
                        CountdownRing(progress: st.phaseProgress, color: (accent ?? SP.accent).opacity(0.7), lineWidth: 2.5)
                            .padding(2)
                    }
                    // Reduce Motion: one steady size; the ring, colour and words carry the rhythm.
                    BreathOrb(scale: reduceMotion ? 0.82 : st.orb, phase: st.phase, hum: session.pattern?.hum ?? false,
                              simplified: luminanceReduced, accent: accent)
                        .padding(dimmed ? 0 : 8)
                    if prefs.settings.showNumbers && session.pattern != nil && !dimmed {
                        Text("\(Int(st.phaseRemaining.rounded(.up)))")
                            .font(SP.numbers(22)).foregroundStyle(Color.white.opacity(0.9))
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                .frame(maxHeight: .infinity)
                // The cue stays readable when dimmed or in Always-On, so you can follow along.
                Text(session.pattern == nil ? (session.cue ?? "Be still") : st.label)
                    .font(SP.serif(17, .light)).foregroundStyle(SP.ink.opacity(dimmed || luminanceReduced ? 0.8 : 1))
                    .lineLimit(3).minimumScaleFactor(0.85).multilineTextAlignment(.center)
                if !dimmed && !luminanceReduced {
                    if let n = st.nostril {
                        SideIndicator(left: n == .left, right: n == .right, color: SP.accent)
                    } else if let c = session.cue, session.pattern != nil {
                        Text(c).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(3).minimumScaleFactor(0.85).multilineTextAlignment(.center)
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
                            WatchRunGlyph(icon: session.isPaused ? "play.fill" : "pause.fill", height: 44, fill: AnyShapeStyle(SP.accentFill))
                        }
                        .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                        Button(role: .destructive, action: onEnd) {
                            WatchRunGlyph(icon: "stop.fill", height: 44, fill: AnyShapeStyle(Color.red.opacity(0.55)))
                        }
                        .accessibilityLabel("End")
                    }
                    .buttonStyle(.plain)
                    Text(spFormatClock(session.remaining) + (heartRate.map { " · \(Int($0)) bpm" } ?? ""))
                        .font(SP.rounded(11)).monospacedDigit().foregroundStyle(SP.dim)
                }
                .padding(.horizontal, 4)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, SP.nightBottom.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90).ignoresSafeArea().allowsHitTesting(false)
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

    /// Hides the buttons after a few seconds, but never fades the screen: the orb, cue and count stay
    /// bright so you can always see what's happening (the old dark "sleep" layer looked frozen).
    private func scheduleDim() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard !session.isFinished else { return }
            withAnimation(.easeInOut(duration: 1)) { showControls = false }
        }
    }
}

/// A run-screen control: a white glyph on a capsule of a set height, sharing the row's width.
private struct WatchRunGlyph: View {
    let icon: String
    let height: CGFloat
    let fill: AnyShapeStyle
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: height >= 40 ? 17 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
    }
}

/// Warm-up / movement step player.
struct MovementRunView: View {
    @ObservedObject var session: MovementSession
    let onEnd: () -> Void
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        let s = session.step
        ZStack {
            DuskBackground(glow: SP.teal).opacity(luminanceReduced ? 0 : 0.85)
            VStack(spacing: 2) {
                GeometryReader { g in
                    HStack(spacing: 6) {
                        PoseFigureView(motion: PoseLibrary.motion(for: s), mirrored: PoseLibrary.mirrored(for: s), lineWidth: 2.2, captions: false)
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
                // Full description; turn the Digital Crown to read the rest.
                ScrollView {
                    VStack(spacing: 3) {
                        Text(s.name).font(SP.serif(16)).foregroundStyle(SP.ink).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !s.how.isEmpty {
                            Text(s.how).font(SP.rounded(12)).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            if s.side != nil { SideIndicator(left: s.side == "left" || s.side == "both", right: s.side == "right" || s.side == "both", color: SP.teal) }
                            Text(s.breathCue).font(SP.rounded(11)).foregroundStyle(SP.accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .id(session.index)
                }
                HStack(spacing: 6) {
                    Button { session.isPaused ? session.resume() : session.pause() } label: {
                        WatchRunGlyph(icon: session.isPaused ? "play.fill" : "pause.fill", height: 34, fill: AnyShapeStyle(SP.accentFill))
                    }
                    .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                    Button { session.skip() } label: {
                        WatchRunGlyph(icon: "forward.end.fill", height: 34, fill: AnyShapeStyle(Color.white.opacity(0.14)))
                    }
                    .accessibilityLabel("Next step")
                    Button(action: onEnd) {
                        WatchRunGlyph(icon: "stop.fill", height: 34, fill: AnyShapeStyle(Color.white.opacity(0.14)))
                    }
                    .accessibilityLabel("End")
                }
                .opacity(luminanceReduced ? 0 : 1)
                .buttonStyle(.plain)
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
    /// The HRV lookup finished (or gave up) without a reading.
    var hrvMissing = false
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
                        .fill(RadialGradient(colors: [SP.accent.opacity(0.55), SP.plum.opacity(0.25), .clear],
                                             center: .center, startRadius: 2, endRadius: 60))
                        .frame(width: 110, height: 110)
                        .scaleEffect(bloom ? 1.0 : 0.4)
                        .opacity(bloom ? 1 : 0)
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(SP.accent)
                            .accessibilityHidden(true)
                        Text("Well done.").font(SP.serif(22, .light)).foregroundStyle(SP.ink)
                    }
                }
                let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                LazyVGrid(columns: cols, spacing: 6) {
                    stat(String(format: "%.0f", max(1, minutes.rounded())), "MIN", SP.accent)
                    if cycles > 0 { stat("\(cycles)", "BREATHS", SP.teal) }
                    if let a = startHR, let b = minHR ?? endHR, a > 0 {
                        stat("\(Int(a))→\(Int(b))", "BPM", SP.rose)
                    }
                    if let h = hrv {
                        stat("\(Int(h))", "HRV MS", SP.violet)
                    } else if startHR != nil && hrvMissing {
                        // The lookup is over and Health had nothing: say so plainly.
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: "waveform.path.ecg").font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SP.faint)
                            Text("NO HRV READING").font(SP.rounded(9, .semibold)).tracking(0.8).foregroundStyle(SP.faint)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SP.card))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("No HRV reading for this session")
                        .transition(.opacity)
                    } else if startHR != nil {
                        // Skeleton tile while HRV is still on its way.
                        VStack(alignment: .leading, spacing: 4) {
                            SPSkeleton(height: 14, width: 44)
                            Text("HRV ON ITS WAY").font(SP.rounded(9, .semibold)).tracking(0.8).foregroundStyle(SP.faint)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SP.card))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Waiting for HRV")
                    }
                }
                if let t = detail?.takeaway {
                    Text(t).font(SP.rounded(13)).foregroundStyle(SP.ink)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                let streak = SessionLog.shared.streak
                if streak > 1 {
                    Label("\(streak) days in a row", systemImage: "flame.fill").font(SP.rounded(12, .medium)).foregroundStyle(SP.gold)
                }
                if let d = detail {
                    NavigationLink {
                        WatchSessionDetailView(record: d)
                    } label: {
                        Label("Details", systemImage: "waveform.path.ecg")
                            .font(SP.rounded(14, .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(SP.accent)
                }
                Button(action: onDone) {
                    Text(minutes < 1 ? "Keep" : "Done").font(SP.rounded(15, .semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Color(spHex: "#5B69DE"))
                .padding(.top, 4)
                if !records.isEmpty {
                    Button(role: .destructive) {
                        for r in records {
                            SessionLog.shared.remove(r.id)
                            WatchLink.shared.sendDelete(r.id)
                        }
                        onDone()
                    } label: {
                        Text("Discard").font(SP.rounded(13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SP.dim)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(SP.dawn.opacity(0.5).ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 3.0)) { bloom = true }
        }
    }

    private func stat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(SP.numbers(19)).foregroundStyle(SP.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(SP.rounded(9, .semibold)).tracking(0.8).foregroundStyle(c)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SP.card))
        .accessibilityElement(children: .combine)
    }
}
