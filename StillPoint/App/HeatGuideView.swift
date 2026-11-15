import SwiftUI

// MARK: - Content

/// One step of the guided round.
enum HeatStep: Hashable {
    case breathe(String, Double)
    case move(String)

    var seconds: Double {
        switch self {
        case .breathe(_, let s): return s
        case .move(let id): return HeatMove.find(id).seconds
        }
    }
    var title: String {
        switch self {
        case .breathe(let id, _): return HeatBreath.find(id).title
        case .move(let id): return HeatMove.find(id).title
        }
    }

    /// About 12 minutes: settle, loosen the top, fold, release, then steady breathing.
    static let round: [HeatStep] = [
        .breathe("cool", 120), .move("neck"), .move("shoulders"),
        .breathe("long", 90), .move("twist"), .move("fold"),
        .breathe("sigh", 45), .move("jaw"), .move("lymph"), .move("ankles"),
        .breathe("even", 150),
    ]
}

// MARK: - Screen

struct HeatGuideView: View {
    @EnvironmentObject var heat: HeatStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0                 // 0 guided, 1 breathe, 2 move
    /// The guided round runs off the clock (not off screen refreshes), so it keeps time with the voice
    /// while the phone is locked. Skipping a step moves the start back by what was left of it.
    @State private var roundStart = Date()
    @State private var roundDone = false
    @State private var breathPick = "cool"
    @State private var breathStart = Date()
    @State private var movePick: String? = nil
    // Play-through of all the moves, like a routine (also clock-based: from `playBase`, starting at `playStart`).
    @State private var playing = false
    @State private var playBase = 0
    @State private var playStart = Date()
    @ObservedObject private var voice = VoiceGuide.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: HeatKind { heat.active?.kind ?? heat.history.first?.kind ?? .sauna }

    var body: some View {
        ZStack {
            LinearGradient(colors: [kind.tint2.opacity(0.55), Color.black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HeatShimmer(color: kind.tint).ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                Picker("Mode", selection: $mode) {
                    Text("Guided").tag(0); Text("Breathe").tag(1); Text("Move").tag(2)
                }
                .pickerStyle(.segmented)
                ScrollView {
                    VStack(spacing: 18) {
                        switch mode {
                        case 0: guided
                        case 1: breathe
                        default: move
                        }
                        safety
                    }
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            roundStart = Date()
            breathStart = Date()
            VoiceGuide.shared.begin()
            refreshVoice()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            VoiceGuide.shared.end()
        }
        .onChange(of: mode) { _, _ in
            if mode == 1 { breathStart = Date() }
            refreshVoice()
        }
        .onChange(of: breathPick) { _, _ in breathStart = Date(); refreshVoice() }
        .onChange(of: voice.on) { _, on in if on { refreshVoice() } }
    }

    // MARK: Clock

    private static let roundTotal = HeatStep.round.reduce(0) { $0 + $1.seconds }

    /// Where the guided round is at `date`: step, when that step began, seconds left in it.
    private func roundPosition(at date: Date) -> (index: Int, stepStart: Date, left: Double, done: Bool) {
        let steps = HeatStep.round
        var t = date.timeIntervalSince(roundStart)
        var begin = roundStart
        for (i, st) in steps.enumerated() {
            if t < st.seconds { return (i, begin, st.seconds - t, false) }
            t -= st.seconds
            begin = begin.addingTimeInterval(st.seconds)
        }
        return (steps.count - 1, begin, 0, true)
    }

    /// Which move the play-through is on at `date`.
    private func playPosition(at date: Date) -> (index: Int, left: Double, done: Bool) {
        let moves = HeatMove.all
        var t = date.timeIntervalSince(playStart)
        var i = max(0, min(playBase, moves.count - 1))
        while i < moves.count {
            if t < moves[i].seconds { return (i, moves[i].seconds - t, false) }
            t -= moves[i].seconds
            i += 1
        }
        return (moves.count - 1, 0, true)
    }

    // MARK: Voice

    /// Hand the voice the script for whatever is on screen, timed from the same clock.
    private func refreshVoice() {
        guard voice.on else { return }
        voice.hush()
        let now = Date()
        var cues: [VoiceCue] = []
        switch mode {
        case 0:
            guard !roundDone else { return }
            let pos = roundPosition(at: now)
            var at = pos.stepStart
            for (i, step) in HeatStep.round.enumerated() where i >= pos.index {
                switch step {
                case .breathe(let id, let secs):
                    let b = HeatBreath.find(id)
                    cues.append(VoiceCue(at: max(at, now), text: VoiceGuide.intro(b)))
                    cues += VoiceGuide.heatBreath(b, from: at, seconds: secs, firstCycle: 1).filter { $0.at >= now }
                case .move(let id):
                    cues.append(VoiceCue(at: max(at, now), text: VoiceGuide.intro(HeatMove.find(id))))
                }
                at = at.addingTimeInterval(step.seconds)
            }
            cues.append(VoiceCue(at: at, text: String(localized: "Round done. Step out, cool down slowly and drink some water.")))
        case 1:
            let b = HeatBreath.find(breathPick)
            cues.append(VoiceCue(at: now, text: VoiceGuide.intro(b)))
            cues += VoiceGuide.heatBreath(b, from: breathStart, seconds: 30 * 60, firstCycle: 1).filter { $0.at >= now }
        default:
            guard playing else { return }
            let pos = playPosition(at: now)
            var at = now.addingTimeInterval(-(HeatMove.all[pos.index].seconds - pos.left))
            for m in HeatMove.all[pos.index...] {
                cues.append(VoiceCue(at: max(at, now), text: VoiceGuide.intro(m)))
                at = at.addingTimeInterval(m.seconds)
            }
            cues.append(VoiceCue(at: at, text: String(localized: "That's all the moves.")))
        }
        voice.play(cues)
    }

    // Timer + I'm out, always visible.
    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Label(kind.title.uppercased(), systemImage: kind.symbol)
                    .font(SP.rounded(12, .semibold)).tracking(1.4).foregroundStyle(kind.tint)
                if let s = heat.active {
                    TimelineView(.periodic(from: s.start, by: 1)) { ctx in
                        Text(spFormatClock(ctx.date.timeIntervalSince(s.start)))
                            .font(SP.numbers(34)).foregroundStyle(.white).monospacedDigit()
                    }
                } else {
                    Text("Not timing").font(SP.rounded(15)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            if heat.active != nil {
                Button {
                    withAnimation { heat.finish() }
                    dismiss()
                } label: {
                    Label("I'm out", systemImage: "checkmark")
                        .font(SP.rounded(15, .semibold)).foregroundStyle(kind.tint2)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(SoftPress())
            }
            VoiceToggleButton(size: 38).foregroundStyle(.white.opacity(0.85))
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 38, height: 38).background(Circle().fill(.white.opacity(0.12)))
            }
            .accessibilityLabel("Close guide")
        }
    }

    // MARK: Guided round

    private var guided: some View {
        let steps = HeatStep.round
        return VStack(spacing: 16) {
            if roundDone {
                VStack(spacing: 10) {
                    Image(systemName: "drop.fill").font(.system(size: 34)).foregroundStyle(kind.tint)
                    Text("Round done").font(SP.serif(28)).foregroundStyle(.white)
                    Text("Step out, cool down slowly, drink some water. Go again after a break if you feel good.")
                        .font(SP.rounded(15)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    Button("Another round") { roundStart = Date(); roundDone = false; refreshVoice() }
                        .font(SP.rounded(15, .semibold)).foregroundStyle(kind.tint).padding(.top, 6)
                    RootboundLinkCard(title: "Cool down outside",
                                      subtitle: "Fresh air and a tree hug between rounds. Rootbound logs it.")
                        .padding(.top, 8)
                }
                .padding(.vertical, 30)
            } else {
                TimelineView(.periodic(from: roundStart, by: 1)) { ctx in
                    let pos = roundPosition(at: ctx.date)
                    let stepIndex = pos.index
                    let step = steps[stepIndex]
                    let left = pos.left
                    VStack(spacing: 14) {
                        HStack {
                            Text("STEP \(stepIndex + 1) OF \(steps.count)").font(SP.rounded(11, .semibold)).tracking(1.4)
                            Spacer()
                            Text(spFormatClock(left)).font(SP.numbers(16)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        ProgressView(value: 1 - left / max(1, step.seconds)).tint(kind.tint)
                        stepView(step, start: pos.stepStart)
                            .id(stepIndex)
                        HStack {
                            if stepIndex + 1 < steps.count {
                                Text("Next: \(steps[stepIndex + 1].title)").font(SP.rounded(13)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button { skip(left: left) } label: {
                                Label("Skip", systemImage: "forward.fill").font(SP.rounded(13, .semibold))
                            }
                            .foregroundStyle(kind.tint)
                            .accessibilityLabel("Skip to the next step")
                        }
                    }
                    .onChange(of: pos.done) { _, done in if done { withAnimation(reduceMotion ? nil : .default) { roundDone = true } } }
                }
            }
        }
    }

    @ViewBuilder
    private func stepView(_ step: HeatStep, start: Date) -> some View {
        switch step {
        case .breathe(let id, _):
            BreathPacer(breath: HeatBreath.find(id), tint: kind.tint, glow: kind.tint2, startedAt: start)
        case .move(let id):
            MovePanel(move: HeatMove.find(id), tint: kind.tint, large: true)
        }
    }

    /// Jump to the next step: the round clock moves on by whatever was left of this one.
    private func skip(left: Double) {
        withAnimation(reduceMotion ? nil : .easeInOut) { roundStart = roundStart.addingTimeInterval(-left) }
        if roundPosition(at: Date()).done { roundDone = true }
        refreshVoice()
    }

    // MARK: Breathe / Move pickers

    private var breathe: some View {
        VStack(spacing: 14) {
            BreathPacer(breath: HeatBreath.find(breathPick), tint: kind.tint, glow: kind.tint2, startedAt: breathStart)
            ForEach(HeatBreath.all) { b in
                Button { withAnimation { breathPick = b.id } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).font(SP.serif(18)).foregroundStyle(.white)
                            Text(b.pattern).font(SP.rounded(12)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if b.id == breathPick { Image(systemName: "checkmark.circle.fill").foregroundStyle(kind.tint) }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(b.id == breathPick ? 0.14 : 0.06)))
                }
                .buttonStyle(SoftPress())
            }
        }
    }

    private var move: some View {
        VStack(spacing: 12) {
            if playing {
                movePlayer
            } else {
                Button {
                    playBase = HeatMove.all.firstIndex { $0.id == movePick } ?? 0
                    playStart = Date()
                    withAnimation(reduceMotion ? nil : .default) { playing = true }
                    refreshVoice()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Text("Play all \(HeatMove.all.count) moves")
                        Spacer()
                        Text("\(Int((HeatMove.all.reduce(0) { $0 + $1.seconds } / 60).rounded())) min").opacity(0.7)
                    }
                    .font(SP.rounded(16, .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(colors: [kind.tint, kind.tint2], startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(SoftPress())
                if let id = movePick {
                    MovePanel(move: HeatMove.find(id), tint: kind.tint, large: true)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(HeatMove.all) { m in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { movePick = m.id }
                        if playing, let i = HeatMove.all.firstIndex(of: m) { playBase = i; playStart = Date(); refreshVoice() }
                        else if voice.on { voice.hush(); voice.say(VoiceGuide.intro(m)) }
                    } label: {
                        VStack(spacing: 6) {
                            PoseFigureView(motion: PoseLibrary.motion(for: m.step), tint: kind.tint, glow: kind.tint2,
                                           lineWidth: 2, captions: false)
                                .frame(height: 70)
                            Text(m.title).font(SP.rounded(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(m.id == movePick ? 0.16 : 0.06)))
                    }
                    .buttonStyle(SoftPress())
                    .accessibilityLabel(m.title)
                    .accessibilityAddTraits(m.id == movePick ? .isSelected : [])
                }
            }
        }
    }

    /// Plays every move in order with a countdown, then stops. Tap a tile to start from that move.
    private var movePlayer: some View {
        TimelineView(.periodic(from: playStart, by: 1)) { ctx in
            let pos = playPosition(at: ctx.date)
            let playIndex = pos.index
            let m = HeatMove.all[playIndex]
            let left = pos.left
            VStack(spacing: 12) {
                HStack {
                    Text("MOVE \(playIndex + 1) OF \(HeatMove.all.count)").font(SP.rounded(11, .semibold)).tracking(1.4)
                    Spacer()
                    Text(spFormatClock(left)).font(SP.numbers(16)).monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.7))
                ProgressView(value: 1 - left / max(1, m.seconds)).tint(kind.tint)
                MovePanel(move: m, tint: kind.tint, large: true)
                    .id(m.id)
                    .transition(.opacity)
                HStack(spacing: 22) {
                    Button { stepMove(from: playIndex, by: -1) } label: { Image(systemName: "backward.fill") }
                        .disabled(playIndex == 0)
                        .accessibilityLabel("Previous move")
                    Button { withAnimation(reduceMotion ? nil : .default) { playing = false }; voice.hush() } label: { Image(systemName: "stop.fill") }
                        .accessibilityLabel("Stop")
                    Button { stepMove(from: playIndex, by: 1) } label: { Image(systemName: "forward.fill") }
                        .accessibilityLabel("Next move")
                }
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                if playIndex + 1 < HeatMove.all.count {
                    Text("Next: \(HeatMove.all[playIndex + 1].title)").font(SP.rounded(13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .onChange(of: pos.done) { _, done in if done { withAnimation(reduceMotion ? nil : .default) { playing = false } } }
        }
    }

    private func stepMove(from current: Int, by d: Int) {
        let n = current + d
        if n >= HeatMove.all.count {
            withAnimation(reduceMotion ? nil : .default) { playing = false }
            voice.hush()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut) { playBase = max(0, n); playStart = Date() }
        refreshVoice()
    }

    private var safety: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(kind.tint)
            Text("No breath-holds or fast breathing in the heat. Step out if you feel dizzy, sick or your heart pounds. Phones can overheat, so keep it on a towel out of the hottest air, or use Siri.")
                .font(SP.rounded(12)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }
}

// MARK: - Pieces

/// A big glowing orb that grows on the in-breath and shrinks on the out-breath, with the cue under it.
struct BreathPacer: View {
    let breath: HeatBreath
    let tint: Color
    let glow: Color
    /// When the pacing began (shared with the voice so both keep the same beat). Nil: when it appeared.
    var startedAt: Date? = nil
    @State private var appeared = Date()
    private var start: Date { startedAt ?? appeared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let st = state(at: ctx.date)
                ZStack {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.55), glow.opacity(0.25), .clear],
                                                 center: .center, startRadius: 4, endRadius: 140))
                        .scaleEffect(reduceMotion ? 0.8 : 0.55 + 0.45 * st.size)
                    Circle().stroke(tint.opacity(0.6), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(reduceMotion ? 0.8 : 0.55 + 0.45 * st.size)
                    VStack(spacing: 2) {
                        Text(st.label).font(SP.serif(20)).foregroundStyle(.white)
                        Text("\(st.count)").font(SP.numbers(28)).foregroundStyle(.white.opacity(0.85)).monospacedDigit()
                    }
                }
                .frame(height: 240)
                .background(PhaseTick(key: st.key))
            }
            VStack(spacing: 4) {
                Text("\(breath.title) · \(breath.pattern)").font(SP.rounded(14, .semibold)).foregroundStyle(tint)
                Text(breath.why).font(SP.rounded(13)).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(breath.id)
        .onAppear { appeared = Date() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(breath.title), \(breath.pattern). \(breath.why)")
    }

    private struct PaceState { var label: String; var count: Int; var size: Double; var key: Int }

    private func state(at date: Date) -> PaceState {
        let cyc = max(1, breath.cycle)
        let elapsed = date.timeIntervalSince(start)
        var t = elapsed.truncatingRemainder(dividingBy: cyc)
        let round = Int(elapsed / cyc)
        // Size before this phase, so a top-up keeps growing from where the in-breath ended.
        var size = 0.0
        for (i, p) in breath.phases.enumerated() {
            if t < p.seconds {
                let f = t / p.seconds
                let e = f * f * (3 - 2 * f)
                let target = p.grow ? min(1, size + (i == 0 ? 0.85 : 0.15)) : 0
                let s = size + (target - size) * e
                return PaceState(label: p.label, count: Int((p.seconds - t).rounded(.up)), size: s, key: round * 10 + i)
            }
            t -= p.seconds
            size = p.grow ? min(1, size + (i == 0 ? 0.85 : 0.15)) : 0
        }
        return PaceState(label: breath.phases.first?.label ?? "", count: 0, size: 0, key: 0)
    }
}

/// A light tap each time the breath phase changes, so you can follow with eyes closed.
private struct PhaseTick: View {
    let key: Int
    var body: some View { Color.clear.sensoryFeedback(.impact(weight: .light), trigger: key) }
}

/// One move: animated figure, name and how-to.
struct MovePanel: View {
    let move: HeatMove
    let tint: Color
    var large = false

    var body: some View {
        VStack(spacing: 10) {
            PoseFigureView(motion: PoseLibrary.motion(for: move.step), tint: tint, glow: tint,
                           lineWidth: large ? 3.2 : 2.2)
                .frame(height: large ? 200 : 110)
            Text(move.title).font(SP.serif(24)).foregroundStyle(.white)
            Text(move.how).font(SP.rounded(14)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.07)))
    }
}
