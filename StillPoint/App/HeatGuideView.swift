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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var kind: HeatKind { heat.active?.kind ?? heat.history.first?.kind ?? .sauna }

    var body: some View {
        ZStack {
            // The app's night sky with a warm (sauna) or misty (steam) glow and a slow heat haze.
            DuskBackground(glow: kind.tint)
            HeatShimmer(color: kind.tint).ignoresSafeArea()
            VStack(spacing: SP.s4) {
                topBar
                Picker("Mode", selection: $mode) {
                    Text("Guided").tag(0); Text("Breathe").tag(1); Text("Move").tag(2)
                }
                .pickerStyle(.segmented)
                ScrollView {
                    VStack(spacing: SP.s4) {
                        switch mode {
                        case 0: guided
                        case 1: breathe
                        default: move
                        }
                        safety
                    }
                    .padding(.bottom, SP.s8)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, SP.screenPadding)
            .padding(.top, SP.s2)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(trigger: roundDone) { _, done in done ? SensoryFeedback.success : nil }
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

    // Timer + I'm out, always visible (I'm out drops under the clock when big text needs the room).
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: SP.s2) {
                clock
                Spacer(minLength: SP.s2)
                outButton
                voiceAndClose
            }
            VStack(alignment: .leading, spacing: SP.s2) {
                HStack(alignment: .center, spacing: SP.s2) {
                    clock
                    Spacer(minLength: SP.s2)
                    voiceAndClose
                }
                outButton
            }
        }
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label { Text(kind.localizedTitle) } icon: { Image(systemName: kind.symbol) }
                .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                .foregroundStyle(kind.tint)
            if let s = heat.active {
                TimelineView(.periodic(from: s.start, by: 1)) { ctx in
                    Text(spFormatClock(ctx.date.timeIntervalSince(s.start)))
                        .font(SP.numbers(34)).foregroundStyle(SP.ink)
                        .contentTransition(.numericText())
                }
            } else {
                Text("Not timing").font(.subheadline).foregroundStyle(SP.dim)
            }
        }
    }

    @ViewBuilder private var outButton: some View {
        if heat.active != nil {
            Button {
                withAnimation { heat.finish() }
                dismiss()
            } label: {
                Label("I'm out", systemImage: "checkmark")
            }
            .buttonStyle(SPPrimaryButtonStyle(fullWidth: false))
        }
    }

    private var voiceAndClose: some View {
        HStack(spacing: SP.s2) {
            VoiceToggleButton(size: 44).foregroundStyle(SP.ink)
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SP.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .overlay(Circle().stroke(SP.stroke, lineWidth: 1))
            }
            .accessibilityLabel("Close guide")
        }
    }

    // MARK: Guided round

    private var guided: some View {
        let steps = HeatStep.round
        return VStack(spacing: SP.s4) {
            if roundDone {
                VStack(spacing: SP.s3) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 28, weight: .light)).foregroundStyle(kind.tint)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(kind.tint.opacity(0.14)))
                        .accessibilityHidden(true)
                    Text("Round done").font(SP.serif(28, .light)).foregroundStyle(SP.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Step out, cool down slowly, drink some water. Go again after a break if you feel good.")
                        .font(.subheadline).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { roundStart = Date(); roundDone = false; refreshVoice() } label: {
                        Label("Another round", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SPPrimaryButtonStyle(fullWidth: false))
                    .padding(.top, SP.s1)
                    RootboundLinkCard(title: "Cool down outside",
                                      subtitle: "Fresh air and a tree hug between rounds. Rootbound logs it.")
                        .padding(.top, SP.s2)
                }
                .padding(.vertical, SP.s6)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.96).combined(with: .opacity))
            } else {
                TimelineView(.periodic(from: roundStart, by: 1)) { ctx in
                    let pos = roundPosition(at: ctx.date)
                    let stepIndex = pos.index
                    let step = steps[stepIndex]
                    let left = pos.left
                    VStack(spacing: SP.s3) {
                        HStack {
                            Text("STEP \(stepIndex + 1) OF \(steps.count)").font(.caption.weight(.semibold)).tracking(1.2)
                            Spacer()
                            Text(spFormatClock(left)).font(.subheadline).monospacedDigit()
                        }
                        .foregroundStyle(SP.dim)
                        ProgressView(value: 1 - left / max(1, step.seconds)).tint(kind.tint)
                        stepView(step, start: pos.stepStart)
                            .id(stepIndex)
                        HStack(spacing: SP.s3) {
                            if stepIndex + 1 < steps.count {
                                Text("Next: \(steps[stepIndex + 1].title)").font(.footnote).foregroundStyle(SP.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: SP.s2)
                            Button { skip(left: left) } label: {
                                Label("Skip", systemImage: "forward.fill")
                            }
                            .buttonStyle(SPSecondaryButtonStyle())
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
            MovePanel(move: HeatMove.find(id), tint: kind.tint, glow: kind.tint2, large: true)
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
        VStack(spacing: SP.s3) {
            BreathPacer(breath: HeatBreath.find(breathPick), tint: kind.tint, glow: kind.tint2, startedAt: breathStart)
            ForEach(HeatBreath.all) { b in
                Button { withAnimation(reduceMotion ? nil : .default) { breathPick = b.id } } label: {
                    HeatBreathRow(breath: b, selected: b.id == breathPick)
                }
                .buttonStyle(SoftPress())
                .accessibilityAddTraits(b.id == breathPick ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: breathPick)
    }

    /// Two columns of move tiles; one at the largest text sizes.
    private var moveColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: SP.s3, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private var move: some View {
        VStack(spacing: SP.s3) {
            if playing {
                movePlayer
            } else {
                Button {
                    playBase = HeatMove.all.firstIndex { $0.id == movePick } ?? 0
                    playStart = Date()
                    withAnimation(reduceMotion ? nil : .default) { playing = true }
                    refreshVoice()
                } label: {
                    HStack(spacing: SP.s2) {
                        Image(systemName: "play.fill")
                        Text("Play all \(HeatMove.all.count) moves")
                        Spacer(minLength: SP.s2)
                        Text("\(Int((HeatMove.all.reduce(0) { $0 + $1.seconds } / 60).rounded())) min")
                            .monospacedDigit().opacity(0.8)
                    }
                }
                .buttonStyle(SPPrimaryButtonStyle())
                if let id = movePick {
                    MovePanel(move: HeatMove.find(id), tint: kind.tint, glow: kind.tint2, large: true)
                }
            }
            LazyVGrid(columns: moveColumns, spacing: SP.s3) {
                ForEach(HeatMove.all) { m in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { movePick = m.id }
                        if playing, let i = HeatMove.all.firstIndex(of: m) { playBase = i; playStart = Date(); refreshVoice() }
                        else if voice.on { voice.hush(); voice.say(VoiceGuide.intro(m)) }
                    } label: {
                        HeatMoveTile(move: m, kind: kind, selected: m.id == movePick)
                    }
                    .buttonStyle(SoftPress())
                    .accessibilityLabel(m.title)
                    .accessibilityAddTraits(m.id == movePick ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: movePick)
    }

    /// Plays every move in order with a countdown, then stops. Tap a tile to start from that move.
    private var movePlayer: some View {
        TimelineView(.periodic(from: playStart, by: 1)) { ctx in
            let pos = playPosition(at: ctx.date)
            let playIndex = pos.index
            let m = HeatMove.all[playIndex]
            let left = pos.left
            VStack(spacing: SP.s3) {
                HStack {
                    Text("MOVE \(playIndex + 1) OF \(HeatMove.all.count)").font(.caption.weight(.semibold)).tracking(1.2)
                    Spacer()
                    Text(spFormatClock(left)).font(.subheadline).monospacedDigit()
                }
                .foregroundStyle(SP.dim)
                ProgressView(value: 1 - left / max(1, m.seconds)).tint(kind.tint)
                MovePanel(move: m, tint: kind.tint, glow: kind.tint2, large: true)
                    .id(m.id)
                    .transition(.opacity)
                HStack(spacing: SP.s6) {
                    playerControl("backward.fill", label: "Previous move") { stepMove(from: playIndex, by: -1) }
                        .disabled(playIndex == 0)
                        .opacity(playIndex == 0 ? 0.4 : 1)
                    playerControl("stop.fill", label: "Stop", prominent: true) {
                        withAnimation(reduceMotion ? nil : .default) { playing = false }
                        voice.hush()
                    }
                    playerControl("forward.fill", label: "Next move") { stepMove(from: playIndex, by: 1) }
                }
                if playIndex + 1 < HeatMove.all.count {
                    Text("Next: \(HeatMove.all[playIndex + 1].title)").font(.footnote).foregroundStyle(SP.dim)
                }
            }
            .onChange(of: pos.done) { _, done in if done { withAnimation(reduceMotion ? nil : .default) { playing = false } } }
        }
    }

    /// Round player control with a 52 pt (64 pt for Stop) hit area.
    private func playerControl(_ icon: String, label: LocalizedStringKey, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 20 : 17, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : SP.ink)
                .frame(width: prominent ? 64 : 52, height: prominent ? 64 : 52)
                .background(Circle().fill(prominent ? AnyShapeStyle(SP.accentFill) : AnyShapeStyle(Color.white.opacity(0.10))))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
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
        HStack(alignment: .top, spacing: SP.s3) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SP.amber).accessibilityHidden(true)
            Text("No breath-holds or fast breathing in the heat. Step out if you feel dizzy, sick or your heart pounds. Phones can overheat, so keep it on a towel out of the hottest air, or use Siri.")
                .font(.footnote).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .spCard(padding: SP.s3 + 2, tint: SP.amber)
    }
}

// MARK: - Pieces

/// Card surface for something you pick in the guide: an accent wash and outline when it's the one chosen.
private struct HeatPickCard: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SP.radius, style: .continuous)
        return content
            .background(shape.fill(selected ? SP.accent.opacity(0.14) : SP.card))
            .overlay(shape.stroke(selected ? SP.accent.opacity(0.45) : SP.stroke, lineWidth: 1))
            .contentShape(shape)
    }
}

/// One heat-safe breathing pattern to choose.
private struct HeatBreathRow: View {
    let breath: HeatBreath
    let selected: Bool
    var body: some View {
        HStack(spacing: SP.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(breath.title).font(.body.weight(.semibold)).foregroundStyle(SP.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(breath.pattern).font(.footnote).monospacedDigit().foregroundStyle(SP.dim)
            }
            Spacer(minLength: SP.s2)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(selected ? SP.accent : SP.faint)
                .accessibilityHidden(true)
        }
        .padding(SP.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HeatPickCard(selected: selected))
    }
}

/// One bench move to choose: its looping figure and name.
private struct HeatMoveTile: View {
    let move: HeatMove
    let kind: HeatKind
    let selected: Bool
    var body: some View {
        VStack(spacing: SP.s2) {
            PoseFigureView(motion: PoseLibrary.motion(for: move.step), tint: kind.tint, glow: kind.tint2,
                           lineWidth: 2, captions: false)
                .frame(height: 70)
                .accessibilityHidden(true)
            Text(move.title).font(.footnote.weight(.semibold)).foregroundStyle(SP.ink)
                .multilineTextAlignment(.center).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SP.s3 - 2)
        .frame(maxWidth: .infinity)
        .modifier(HeatPickCard(selected: selected))
    }
}

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
        VStack(spacing: SP.s3) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let st = state(at: ctx.date)
                ZStack {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.50), glow.opacity(0.24), SP.indigo.opacity(0.10), .clear],
                                                 center: .center, startRadius: 4, endRadius: 140))
                        .scaleEffect(reduceMotion ? 0.8 : 0.55 + 0.45 * st.size)
                    Circle().stroke(tint.opacity(0.55), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(reduceMotion ? 0.8 : 0.55 + 0.45 * st.size)
                    VStack(spacing: 2) {
                        Text(st.label).font(SP.serif(20)).foregroundStyle(SP.ink)
                        Text("\(st.count)").font(SP.numbers(28)).foregroundStyle(SP.ink.opacity(0.85))
                    }
                }
                .frame(height: 240)
                .background(PhaseTick(key: st.key))
            }
            VStack(spacing: SP.s1) {
                Text("\(breath.title) · \(breath.pattern)").font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                    .multilineTextAlignment(.center)
                Text(breath.why).font(.footnote).foregroundStyle(SP.dim)
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

/// One move: animated figure, name and how-to, on the standard card.
struct MovePanel: View {
    let move: HeatMove
    let tint: Color
    /// Soft halo behind the figure (defaults to the tint).
    var glow: Color? = nil
    var large = false

    var body: some View {
        VStack(spacing: SP.s3) {
            PoseFigureView(motion: PoseLibrary.motion(for: move.step), tint: tint, glow: glow ?? tint,
                           lineWidth: large ? 3.2 : 2.2)
                .frame(height: large ? 200 : 110)
                .accessibilityHidden(true)
            Text(move.title).font(SP.serif(24, .light)).foregroundStyle(SP.ink)
                .multilineTextAlignment(.center)
            Text(move.how).font(.subheadline).foregroundStyle(SP.dim)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(SP.s4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
