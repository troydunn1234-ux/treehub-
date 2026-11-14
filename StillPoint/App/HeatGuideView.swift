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
    @State private var stepIndex = 0
    @State private var stepStart = Date()
    @State private var roundDone = false
    @State private var breathPick = "cool"
    @State private var movePick: String? = nil

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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; stepStart = Date() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
                    Button("Another round") { stepIndex = 0; stepStart = Date(); roundDone = false }
                        .font(SP.rounded(15, .semibold)).foregroundStyle(kind.tint).padding(.top, 6)
                }
                .padding(.vertical, 30)
            } else {
                TimelineView(.periodic(from: stepStart, by: 1)) { ctx in
                    let step = steps[min(stepIndex, steps.count - 1)]
                    let left = max(0, step.seconds - ctx.date.timeIntervalSince(stepStart))
                    VStack(spacing: 14) {
                        HStack {
                            Text("STEP \(stepIndex + 1) OF \(steps.count)").font(SP.rounded(11, .semibold)).tracking(1.4)
                            Spacer()
                            Text(spFormatClock(left)).font(SP.numbers(16)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        ProgressView(value: 1 - left / max(1, step.seconds)).tint(kind.tint)
                        stepView(step)
                        HStack {
                            if stepIndex + 1 < steps.count {
                                Text("Next: \(steps[stepIndex + 1].title)").font(SP.rounded(13)).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Button { advance() } label: {
                                Label("Skip", systemImage: "forward.fill").font(SP.rounded(13, .semibold))
                            }
                            .foregroundStyle(kind.tint)
                        }
                    }
                    .onChange(of: left <= 0) { _, done in if done { advance() } }
                }
            }
        }
    }

    @ViewBuilder
    private func stepView(_ step: HeatStep) -> some View {
        switch step {
        case .breathe(let id, _):
            BreathPacer(breath: HeatBreath.find(id), tint: kind.tint, glow: kind.tint2)
        case .move(let id):
            MovePanel(move: HeatMove.find(id), tint: kind.tint, large: true)
        }
    }

    private func advance() {
        if stepIndex + 1 >= HeatStep.round.count {
            withAnimation { roundDone = true }
        } else {
            withAnimation(.easeInOut) { stepIndex += 1 }
            stepStart = Date()
        }
    }

    // MARK: Breathe / Move pickers

    private var breathe: some View {
        VStack(spacing: 14) {
            BreathPacer(breath: HeatBreath.find(breathPick), tint: kind.tint, glow: kind.tint2)
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
            if let id = movePick {
                MovePanel(move: HeatMove.find(id), tint: kind.tint, large: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(HeatMove.all) { m in
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { movePick = m.id } } label: {
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
                }
            }
        }
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
    @State private var start = Date()
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
        .onAppear { start = Date() }
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
