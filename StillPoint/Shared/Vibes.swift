import SwiftUI

// Calm touches shared by the iPhone and Watch apps: the time-of-day sky behind Today, a glow that breathes
// with a session, a soft ripple when something is finished, a slow swell for glows and halos, the warm light
// of the sauna and steam room, and plain words for the "Right now" pick.
// All of it is decoration only: nothing here is saved, and every movement stops with Reduce Motion.

// MARK: - Time-of-day sky

/// Four quiet skies for Today: dawn, day, dusk and night. Each stays deep and dark lower down, so cards and
/// text keep their contrast; only the top of the screen takes on the light of the hour.
enum SkyPart: Int, CaseIterable, Identifiable {
    case dawn, day, dusk, night

    var id: Int { rawValue }

    static func at(_ date: Date, calendar: Calendar = .current) -> SkyPart {
        switch calendar.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    static var now: SkyPart { at(Date()) }

    /// Top to bottom.
    var colors: [Color] {
        switch self {
        case .dawn: return [Color(spHex: "#262555"), Color(spHex: "#1A1E4B"), Color(spHex: "#0E1433"), SP.nightBottom]
        case .day: return [Color(spHex: "#1A285E"), Color(spHex: "#141F50"), Color(spHex: "#0D1432"), SP.nightBottom]
        case .dusk: return [Color(spHex: "#2D2357"), Color(spHex: "#1C1B49"), Color(spHex: "#0E1332"), SP.nightBottom]
        case .night: return [SP.nightTop, SP.night, SP.nightBottom]
        }
    }

    /// The light of the hour, high on the screen: the low sun, the open sky, the sunset, the moon.
    var glow: Color {
        switch self {
        case .dawn: return Color(spHex: "#F4B183").opacity(0.16)
        case .day: return SP.teal.opacity(0.12)
        case .dusk: return Color(spHex: "#EBA27C").opacity(0.15)
        case .night: return Color(spHex: "#CFC6FF").opacity(0.10)
        }
    }

    var glowCenter: UnitPoint {
        switch self {
        case .dawn: return UnitPoint(x: 0.85, y: -0.02)
        case .day: return UnitPoint(x: 0.15, y: -0.02)
        case .dusk: return UnitPoint(x: 0.75, y: -0.04)
        case .night: return UnitPoint(x: 0.85, y: 0.0)
        }
    }

    /// A second, fainter light on the other side.
    var haze: Color {
        switch self {
        case .dawn: return Color(spHex: "#E79AB4").opacity(0.10)
        case .day: return SP.gold.opacity(0.07)
        case .dusk: return Color(spHex: "#C77DB0").opacity(0.11)
        case .night: return SP.teal.opacity(0.08)
        }
    }

    var hazeCenter: UnitPoint {
        switch self {
        case .dawn: return UnitPoint(x: 0.1, y: 0.05)
        case .day: return UnitPoint(x: 0.9, y: 0.0)
        case .dusk: return UnitPoint(x: 0.15, y: 0.02)
        case .night: return UnitPoint(x: 0.15, y: 0.1)
        }
    }

    /// The drifting specks on Today: peach at dawn, pale sunlight by day, gold at dusk, starlight at night.
    var mote: Color {
        switch self {
        case .dawn: return Color(spHex: "#F4C9A0")
        case .day: return Color(spHex: "#BFE6E8")
        case .dusk: return SP.gold
        case .night: return Color(spHex: "#DCE2FF")
        }
    }

    /// Symbol beside the greeting.
    var symbol: String {
        switch self {
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Tint for that symbol.
    var accent: Color {
        switch self {
        case .dawn: return Color(spHex: "#F4B183")
        case .day: return SP.gold
        case .dusk: return Color(spHex: "#EBA27C")
        case .night: return SP.violet
        }
    }
}

/// The time-of-day sky. Give it a part, or leave it out to follow the clock (checked once a minute).
/// Changing from one part to the next is a slow cross-fade.
struct SkyBackground: View {
    var part: SkyPart? = nil

    var body: some View {
        if let part {
            SkyLayers(part: part)
        } else {
            TimelineView(.everyMinute) { tl in
                SkyLayers(part: SkyPart.at(tl.date))
            }
        }
    }
}

private struct SkyLayers: View {
    let part: SkyPart

    var body: some View {
        ZStack {
            ForEach(SkyPart.allCases) { p in
                SkyFill(part: p).opacity(p == part ? 1 : 0)
            }
            Grain()
        }
        .animation(.easeInOut(duration: 2.5), value: part)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SkyFill: View {
    let part: SkyPart

    var body: some View {
        ZStack {
            LinearGradient(colors: part.colors, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [part.glow, .clear], center: part.glowCenter, startRadius: 10, endRadius: 460)
            RadialGradient(colors: [part.haze, .clear], center: part.hazeCenter, startRadius: 10, endRadius: 360)
            // The low indigo glow every other screen has.
            RadialGradient(colors: [SP.indigo.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 10, endRadius: 520)
        }
    }
}

// MARK: - Slow swell

/// A very slow swell and settle (about 5½ s each way, the pace of resonance breathing) for glows and halos.
/// Still, at an in-between brightness, with Reduce Motion.
struct SlowBreathe: ViewModifier {
    var period: Double = 5.5
    /// Opacity at the bottom of the breath (1 at the top).
    var low: Double = 0.55
    /// How much it grows from the bottom to the top of the breath (0 = brightness only).
    var grow: CGFloat = 0.06
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity((1 + low) / 2)
        } else {
            let low = self.low, grow = self.grow, period = self.period
            content.phaseAnimator([false, true]) { view, full in
                view
                    .opacity(full ? 1 : low)
                    .scaleEffect(full ? 1 + grow / 2 : 1 - grow / 2)
            } animation: { _ in
                .easeInOut(duration: period)
            }
        }
    }
}

extension View {
    /// Swells and settles slowly (see SlowBreathe). Still with Reduce Motion.
    func slowBreathe(period: Double = 5.5, low: Double = 0.55, grow: CGFloat = 0.06) -> some View {
        modifier(SlowBreathe(period: period, low: low, grow: grow))
    }
}

// MARK: - Breathing glow

/// A soft glow behind the breathing orb that swells on the in-breath and settles on the out-breath, at the
/// session's own pace (it follows the orb). With Reduce Motion it keeps one size and only brightens and dims.
struct BreathAura: View {
    /// The orb's size: 0.55 (empty) … 1.0 (full).
    var level: Double
    var tint: Color
    /// The screen has dimmed itself: just a trace of it.
    var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let amount: Double = min(1, max(0, (level - 0.55) / 0.45))
        let scale: Double = reduceMotion ? 0.92 : 0.68 + 0.32 * amount
        let glow: Double = (quiet ? 0.3 : 1) * (0.5 + 0.5 * amount)
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.34), tint.opacity(0.12), .clear],
                                     center: .center, startRadius: 0, endRadius: r))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .scaleEffect(scale)
        .opacity(glow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Completion ripple

/// A soft ripple, once: a few rings spread out from the middle and fade, like a stone dropped into still water.
/// Nothing at all with Reduce Motion.
struct CalmRipple: View {
    var tint: Color = SP.accent
    var rings = 3
    var duration: Double = 2.8
    var lineWidth: CGFloat = 1.5
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RippleRings(progress: progress, rings: max(1, rings), tint: tint, lineWidth: lineWidth)
            .opacity(reduceMotion ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: duration)) { progress = 1 }
            }
    }
}

/// The rings at one moment of the ripple (0 … 1); SwiftUI animates `progress`.
private struct RippleRings: View, Animatable {
    var progress: Double
    var rings: Int
    var tint: Color
    var lineWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(0..<rings, id: \.self) { i in
                Circle()
                    .stroke(tint, lineWidth: lineWidth)
                    .scaleEffect(0.18 + 0.82 * eased(i))
                    .opacity(alpha(i))
            }
        }
    }

    /// How far ring `i` has spread (0 … 1): each starts a little after the one before.
    private func local(_ i: Int) -> Double {
        let stagger = 0.22
        let span = max(0.3, 1 - stagger * Double(rings - 1))
        return min(1, max(0, (progress - Double(i) * stagger) / span))
    }

    private func eased(_ i: Int) -> Double {
        let t = local(i)
        return 1 - (1 - t) * (1 - t)
    }

    private func alpha(_ i: Int) -> Double {
        let t = local(i)
        guard t > 0, t < 1 else { return 0 }
        return 0.75 * (1 - eased(i))
    }
}

// MARK: - Heat glow

/// Low warm light at the bottom of a sauna card (coals) or a misty blue one for steam, swelling slowly.
struct EmberGlow: View {
    let kind: HeatKind

    var body: some View {
        RadialGradient(colors: [kind.tint.opacity(0.22), kind.tint2.opacity(0.10), .clear],
                       center: UnitPoint(x: 0.5, y: 1.25), startRadius: 4, endRadius: 280)
            .slowBreathe(period: 3.5, low: 0.6, grow: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Plain words for the "Right now" pick

extension Suggestion {
    /// Rules that come from the body's numbers (or the heat and training logs), not only from the clock.
    private static let bodyRules: Set<String> = ["heat", "post-workout", "stress", "low-recovery", "short-night", "high-recovery", "focus"]
    /// Time-of-day rules: their "because" line says the same as the headline.
    private static let clockRules: Set<String> = ["night", "evening", "morning", "afternoon"]

    /// True when the body (or the heat / training log) picked this, not just the time of day.
    var fromBody: Bool { Self.bodyRules.contains(rule) }

    /// What to do, in a few plain words: "wind down", "slow down", "cool down"…
    var plainAction: String {
        switch rule {
        case "heat": return String(localized: "cool down")
        case "post-workout": return String(localized: "recover")
        case "stress": return String(localized: "slow down")
        case "low-recovery": return String(localized: "take it easy")
        case "short-night": return String(localized: "rest")
        case "high-recovery": return String(localized: "wake up and go")
        case "focus": return String(localized: "focus")
        case "night": return String(localized: "wind down")
        case "evening": return String(localized: "let the day settle")
        case "morning": return String(localized: "start steady")
        case "afternoon": return String(localized: "reset and refocus")
        default:
            switch goal {
            case "sleep": return String(localized: "wind down")
            case "calm": return String(localized: "slow down")
            case "recovery": return String(localized: "recover")
            case "energy": return String(localized: "wake up")
            case "focus": return String(localized: "focus")
            case "healing": return String(localized: "be gentle")
            default: return String(localized: "breathe")
            }
        }
    }

    /// "Your body says: slow down" when the numbers picked it, "Time to wind down" when the clock did.
    var plainHeadline: String {
        let action = plainAction
        return fromBody ? String(localized: "Your body says: \(action)") : String(localized: "Time to \(action)")
    }

    /// Whether the "because" line tells you more than the headline already does.
    var becauseAddsSomething: Bool { !because.isEmpty && !Self.clockRules.contains(rule) }
}
