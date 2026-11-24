import SwiftUI
import Combine

// Rootbound's light (looks only): the forest follows the time of day (dawn, day, golden hour, moonlight) and the
// season (the running seasonal event's color). Reads nothing but the clock; stores nothing.

enum ForestLight {
    enum Phase: Equatable { case dawn, day, golden, night }

    static func phase(at date: Date = Date(), calendar: Calendar = .current) -> Phase {
        switch calendar.component(.hour, from: date) {
        case 5..<9: return .dawn
        case 9..<17: return .day
        case 17..<21: return .golden
        default: return .night
        }
    }

    /// The light falling into the forest: peach at dawn, soft sun by day, amber at golden hour, cool moonlight.
    static func sun(_ p: Phase) -> Color {
        switch p {
        case .dawn: return Color(red: 1.0, green: 0.80, blue: 0.62)
        case .day: return Color(red: 1.0, green: 0.96, blue: 0.74)
        case .golden: return Color(red: 1.0, green: 0.68, blue: 0.36)
        case .night: return Color(red: 0.64, green: 0.78, blue: 1.0)
        }
    }

    /// How strong the light is (moonlight is only a faint glow).
    static func strength(_ p: Phase) -> Double {
        switch p {
        case .dawn: return 0.85
        case .day: return 1
        case .golden: return 0.95
        case .night: return 0.5
        }
    }

    static func symbol(_ p: Phase) -> String {
        switch p {
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .golden: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// The season's color: the running seasonal event's (blossom pink, summer gold, autumn orange, winter ice).
    static func season(at date: Date = Date()) -> Color {
        SeasonalEvent.active(on: date)?.colors.first ?? Theme.glow
    }
}

// MARK: - Home hero

/// Over the Home hero photo: soft sun rays from the top corner and drifting specks of dappled light by day,
/// a faint moon glow and a few fireflies at night, with the season's color in the far corner.
/// One still frame with Reduce Motion.
struct ForestShimmer: View {
    var phase: ForestLight.Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Speck { let x: CGFloat; let y: CGFloat; let r: CGFloat; let seed: Double }
    private struct Ray { let angle: Double; let spread: Double; let alpha: Double; let speed: Double }

    private static let specks: [Speck] = {
        var rng = SeededRNG(seed: "dappled-light")
        return (0..<12).map { _ in
            Speck(x: CGFloat(rng.next()), y: CGFloat(0.05 + rng.next() * 0.6), r: CGFloat(rng.next()), seed: rng.next())
        }
    }()

    /// Beams pointing down and to the left from the top-right corner (angles in radians, y pointing down).
    private static let rays: [Ray] = [
        Ray(angle: 1.98, spread: 0.035, alpha: 0.16, speed: 0.21),
        Ray(angle: 2.12, spread: 0.050, alpha: 0.12, speed: 0.17),
        Ray(angle: 2.26, spread: 0.030, alpha: 0.18, speed: 0.26),
        Ray(angle: 2.40, spread: 0.055, alpha: 0.10, speed: 0.15),
        Ray(angle: 2.55, spread: 0.030, alpha: 0.12, speed: 0.19),
    ]

    @Environment(\.scenePhase) private var scenePhase
    /// Low Power Mode: the light holds still until it's off again.
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        Group {
            if reduceMotion {
                scene(at: 0)
            } else {
                // Redrawn 20 times a second only while Rootbound is in front and Low Power Mode is off; otherwise
                // the last frame stays (no drawing in the background, easy on the battery).
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: scenePhase != .active || lowPower)) { ctx in
                    scene(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func scene(at t: Double) -> some View {
        let sun = ForestLight.sun(phase)
        let k = ForestLight.strength(phase)
        let season = ForestLight.season()
        let night = phase == .night
        return Canvas { gc, size in
            let w = size.width
            let h = size.height
            let all = Path(CGRect(origin: .zero, size: size))
            // The season's color, softly from the top-left.
            gc.fill(all, with: .radialGradient(Gradient(colors: [season.opacity(0.16), season.opacity(0)]),
                                               center: CGPoint(x: w * 0.12, y: h * 0.12), startRadius: 0, endRadius: w * 0.7))
            // Light from the top-right corner.
            let origin = CGPoint(x: w * 0.88, y: -h * 0.12)
            gc.fill(all, with: .radialGradient(Gradient(colors: [sun.opacity(0.28 * k), sun.opacity(0)]),
                                               center: origin, startRadius: 0, endRadius: w * 0.75))
            let len = max(w, h) * 1.4
            for r in Self.rays {
                let a = r.angle + sin(t * r.speed + r.angle * 3) * 0.03
                let breathe = 0.7 + 0.3 * sin(t * r.speed * 1.6 + r.angle * 7)
                let alpha = r.alpha * k * breathe * (night ? 0.45 : 1)
                let left = CGPoint(x: origin.x + CGFloat(cos(a - r.spread)) * len, y: origin.y + CGFloat(sin(a - r.spread)) * len)
                let right = CGPoint(x: origin.x + CGFloat(cos(a + r.spread)) * len, y: origin.y + CGFloat(sin(a + r.spread)) * len)
                let end = CGPoint(x: origin.x + CGFloat(cos(a)) * len * 0.62, y: origin.y + CGFloat(sin(a)) * len * 0.62)
                var beam = Path()
                beam.move(to: origin)
                beam.addLine(to: left)
                beam.addLine(to: right)
                beam.closeSubpath()
                gc.fill(beam, with: .linearGradient(Gradient(colors: [sun.opacity(alpha), sun.opacity(0)]),
                                                    startPoint: origin, endPoint: end))
            }
            // Dappled light by day, fireflies at night.
            for s in Self.specks {
                let x = s.x * w + CGFloat(sin(t * 0.18 + s.seed * 9)) * 14
                let y = s.y * h + CGFloat(cos(t * 0.13 + s.seed * 7)) * 9
                let twinkle = 0.5 + 0.5 * sin(t * (0.5 + s.seed) + s.seed * 12)
                let center = CGPoint(x: x, y: y)
                if night {
                    let r = 1.4 + s.r * 1.8
                    gc.fill(Path(ellipseIn: CGRect(x: x - r * 4, y: y - r * 4, width: r * 8, height: r * 8)),
                            with: .radialGradient(Gradient(colors: [Theme.glow.opacity(0.35 * twinkle), Theme.glow.opacity(0)]),
                                                  center: center, startRadius: 0, endRadius: r * 4))
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Theme.glow.opacity(0.85 * twinkle)))
                } else {
                    let r = 5 + s.r * 14
                    gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .radialGradient(Gradient(colors: [sun.opacity(0.22 * k * twinkle), sun.opacity(0)]),
                                                  center: center, startRadius: 0, endRadius: r))
                }
            }
        }
    }
}

// MARK: - Every screen

/// A faint wash of the hour's light from the top of every Rootbound screen, and the season's color from the
/// bottom corner (ForestBackground). Checks the clock once a minute.
struct ForestSkyWash: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let p = ForestLight.phase(at: ctx.date)
            ZStack {
                LinearGradient(colors: [ForestLight.sun(p).opacity(0.12 * ForestLight.strength(p)), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                RadialGradient(colors: [ForestLight.season(at: ctx.date).opacity(0.09), .clear],
                               center: .bottomLeading, startRadius: 10, endRadius: 420)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Hug saved

/// "Hug logged": a sprout grows out of the soil, two leaves unfurl and a heart blooms on top.
/// Shows the grown sprout straight away with Reduce Motion.
struct GrowingSprout: View {
    var size: CGFloat = 96
    /// Bounces the heart again when it changes (the XP tally landing).
    var bounce: Int = 0
    @State private var stem = false
    @State private var leaves = false
    @State private var bloom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heart = Color(red: 1, green: 0.45, blue: 0.55)

    var body: some View {
        let s = size
        ZStack {
            Circle().fill(Theme.glow.opacity(0.10))
            Circle().strokeBorder(Theme.glow.opacity(0.22), lineWidth: 1)
            Capsule().fill(Theme.bark)
                .frame(width: s * 0.42, height: s * 0.05)
                .position(x: s * 0.5, y: s * 0.76)
            SproutStem()
                .trim(from: 0, to: stem ? 1 : 0)
                .stroke(Theme.leaf, style: StrokeStyle(lineWidth: max(2.5, s * 0.04), lineCap: .round))
            leaf(angle: -58, at: CGPoint(x: s * 0.52, y: s * 0.6))
            leaf(angle: 52, at: CGPoint(x: s * 0.53, y: s * 0.5))
            Image(systemName: "heart.fill")
                .font(.system(size: s * 0.22, weight: .bold))
                .foregroundStyle(heart)
                .shadow(color: heart.opacity(0.5), radius: bloom ? 8 : 0)
                .symbolEffect(.bounce, value: bounce)
                .scaleEffect(bloom ? 1 : 0.01)
                .opacity(bloom ? 1 : 0)
                .position(x: s * 0.5, y: s * 0.27)
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
        .task { await grow() }
    }

    /// A leaf whose stalk sits on the stem at `at`, turned out to one side.
    private func leaf(angle: Double, at p: CGPoint) -> some View {
        let lw = size * 0.17, lh = size * 0.27
        return LeafPath(shape: .oval)
            .fill(Theme.leafGradient)
            .frame(width: lw, height: lh)
            .scaleEffect(leaves ? 1 : 0.01, anchor: .bottom)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .position(x: p.x, y: p.y - lh / 2)
    }

    private func grow() async {
        guard !reduceMotion else { stem = true; leaves = true; bloom = true; return }
        withAnimation(.easeOut(duration: 0.7)) { stem = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { leaves = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { bloom = true }
    }
}

/// The sprout's stem: from the soil up to just under the heart, with a slight lean.
private struct SproutStem: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.75))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.38),
                       control: CGPoint(x: r.midX + r.width * 0.09, y: r.minY + r.height * 0.56))
        return p
    }
}

// MARK: - Milestones

/// Warm moments on the hug-saved screen: round-number hugs and coming back to the same tree.
enum HugMilestone {
    struct Moment: Equatable {
        let title: String
        let detail: String
        let symbol: String
    }

    static let hugCounts: Set<Int> = [1, 5, 10, 25, 50, 75, 100, 150, 200, 250, 300, 365, 400, 500, 750, 1000]
    static let treeVisits: Set<Int> = [2, 5, 10, 20, 50, 100]

    /// `hugNumber`: how many hugs there are now, this one included. `visits`: hugs with this tree, this one included.
    static func moment(hugNumber: Int, visits: Int, treeName: String) -> Moment? {
        if hugCounts.contains(hugNumber) {
            switch hugNumber {
            case 1: return Moment(title: "Your first hug", detail: "Every grove starts with one tree.", symbol: "leaf.fill")
            case 5: return Moment(title: "5 hugs", detail: "A habit is taking root.", symbol: "leaf.fill")
            case 10: return Moment(title: "10 hugs", detail: "Your grove is really growing.", symbol: "tree.fill")
            case 25: return Moment(title: "25 hugs", detail: "That's a ritual now.", symbol: "sparkles")
            case 50: return Moment(title: "50 hugs", detail: "Fifty times you stopped to hold a tree.", symbol: "sparkles")
            default: return Moment(title: "\(hugNumber) hugs", detail: "Deep roots. Thank you for showing up.", symbol: "crown.fill")
            }
        }
        if treeVisits.contains(visits) {
            let name = treeName.isEmpty ? "this tree" : treeName
            if visits == 2 {
                return Moment(title: "You came back", detail: "Your second hug with \(name).", symbol: "arrow.uturn.backward.circle.fill")
            }
            return Moment(title: "\(visits) hugs with \(name)", detail: "Old friends now.", symbol: "heart.circle.fill")
        }
        return nil
    }
}

/// The milestone card: a warm golden glow behind a short line.
struct MilestoneCard: View {
    let moment: HugMilestone.Moment
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: RB.m) {
            Image(systemName: moment.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.forestDeep)
                .frame(width: 52, height: 52)
                .background(Theme.goldGradient, in: Circle())
                .shadow(color: Theme.gold.opacity(lit ? 0.6 : 0.2), radius: lit ? 14 : 4)
                .symbolEffect(.bounce, value: lit)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.title)
                    .font(RB.text(.headline, .heavy)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(moment.detail)
                    .font(RB.text(.subheadline)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RB.l)
        .background {
            RoundedRectangle(cornerRadius: RB.radius, style: .continuous).fill(RB.cardFill)
            RoundedRectangle(cornerRadius: RB.radius, style: .continuous)
                .fill(RadialGradient(colors: [Theme.gold.opacity(lit ? 0.30 : 0.16), .clear],
                                     center: .leading, startRadius: 4, endRadius: 260))
        }
        .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion { lit = true; return }
            withAnimation(.easeOut(duration: 0.9)) { lit = true }
        }
    }
}
