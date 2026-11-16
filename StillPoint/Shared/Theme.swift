import SwiftUI

/// Still Point look: calm night blue and indigo, a soft periwinkle accent, mist teal for the breath,
/// and a little warm gold kept for achievements (streaks, milestones).
enum SP {
    // Night palette: indigo navy → deep midnight, with an indigo-violet in between.
    static let nightTop = Color(spHex: "#18214A")
    static let night = Color(spHex: "#111836")
    static let nightBottom = Color(spHex: "#070A18")
    static let plum = Color(spHex: "#33317A")
    /// Warm sand: small warm highlights only (lowest heart rate, hold phase).
    static let amber = Color(spHex: "#E6C39A")
    static let indigo = Color(spHex: "#6C74E0")
    static let violet = Color(spHex: "#A9A6F0")
    static let teal = Color(spHex: "#8FD3D6")
    static let gold = Color(spHex: "#EBCB92")
    static let rose = Color(spHex: "#EBA9B4")
    static let ink = Color(spHex: "#F2F3FA")
    static let dim = Color(spHex: "#F2F3FA").opacity(0.66)
    static let faint = Color(spHex: "#F2F3FA").opacity(0.44)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)

    /// The app accent: calm periwinkle blue (text, icons, tints on the dark background).
    static let accent = Color(spHex: "#A3B4FF")
    /// Fill for primary buttons: deep enough for white text (AA).
    static let accentFill = LinearGradient(colors: [Color(spHex: "#5B69DE"), Color(spHex: "#4651C4")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)

    // Spacing scale (4/8/12/16/24/32) and the one card radius.
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24, s8: CGFloat = 32
    static let radius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    static let screenPadding: CGFloat = 20

    static var background: LinearGradient {
        LinearGradient(colors: [nightTop, night, nightBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Dawn: for summary / "Well done" screens. A soft lift from midnight into indigo and pale blue.
    static var dawn: LinearGradient {
        LinearGradient(colors: [Color(spHex: "#0E1430"), Color(spHex: "#232A66"), Color(spHex: "#4B4F9E"), Color(spHex: "#8C8FCB")],
                       startPoint: .top, endPoint: .bottom)
    }

    static let breath = LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGlow = LinearGradient(colors: [gold, Color(spHex: "#F6DDA8")], startPoint: .leading, endPoint: .trailing)

    /// New York serif for titles.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: .serif)
    }

    /// SF Rounded for everything else.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: .rounded)
    }

    static func numbers(_ size: CGFloat) -> Font {
        .system(size: scaled(size), weight: .light, design: .rounded).monospacedDigit()
    }

    /// Follows the person's text size (Dynamic Type, accessibility sizes included) on iPhone.
    /// Body-sized text can grow a lot; big display numbers grow less so they still fit their rings.
    static func scaled(_ size: CGFloat) -> CGFloat {
        #if os(iOS)
        let raw = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        let cap: CGFloat = size <= 20 ? 2.6 : (size <= 30 ? 1.6 : 1.25)
        return min(raw, size * cap)
        #else
        return size
        #endif
    }
}

extension Color {
    /// "#RRGGBB" or "RRGGBB"; falls back to violet.
    init(spHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self = Color(red: 0.49, green: 0.42, blue: 0.94)
            return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Tradition {
    var tint: Color { Color(spHex: color) }
}

/// Small rounded capsule label.
struct SPChip: View {
    let text: String
    var color: Color = SP.gold
    var filled = false
    var body: some View {
        Text(text.uppercased())
            .font(SP.rounded(10, .bold))
            .tracking(1.2)
            .lineLimit(1)
            .foregroundStyle(filled ? Color.black.opacity(0.85) : color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(filled ? color : color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.35), lineWidth: 0.8))
    }
}

func spFormatClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// A quiet, fixed film grain so gradients feel soft and painted.
struct Grain: View {
    var opacity: Double = 0.05
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            let n = Int(size.width * size.height / 90)
            for _ in 0..<min(n, 6000) {
                let r = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 1, height: 1)
                ctx.fill(Path(r), with: .color(.white.opacity(rnd() * opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The app background: dusk gradient, a slow warm glow low on the screen, and grain.
struct DuskBackground: View {
    var glow: Color = SP.indigo
    var body: some View {
        ZStack {
            SP.background
            RadialGradient(colors: [glow.opacity(0.20), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [SP.teal.opacity(0.10), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 10, endRadius: 380)
            Grain()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared building blocks (one card, one primary button, one section header)

/// The one card surface: soft translucent fill, 20pt continuous corners, a hairline stroke.
struct SPCardModifier: ViewModifier {
    var padding: CGFloat = SP.s4
    var tint: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SP.radius, style: .continuous)
                    .fill(tint.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.16), SP.card], startPoint: .topLeading, endPoint: .bottomTrailing)) }
                          ?? AnyShapeStyle(SP.card))
            )
            .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
    }
}

extension View {
    /// Wraps content in the standard Still Pointz card.
    func spCard(padding: CGFloat = SP.s4, tint: Color? = nil) -> some View {
        modifier(SPCardModifier(padding: padding, tint: tint))
    }
}

/// Primary action: filled accent capsule, 50pt tall, white label.
struct SPPrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.rounded(17, .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .background(Capsule().fill(SP.accentFill))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action: tinted capsule, 44pt+ tall.
struct SPSecondaryButtonStyle: ButtonStyle {
    var tint: Color = SP.accent
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SP.rounded(15, .medium))
            .foregroundStyle(tint)
            .lineLimit(2)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.22 : 0.14)))
            .contentShape(Capsule())
    }
}

/// A round icon control (pause / end / voice) with a 56pt hit area and a caption under it.
struct SPRoundControl: View {
    let icon: String
    let title: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: prominent ? 22 : 18, weight: .regular))
                    .foregroundStyle(prominent ? Color.white : SP.ink)
                    .frame(width: prominent ? 68 : 56, height: prominent ? 68 : 56)
                    .background(Circle().fill(prominent ? AnyShapeStyle(SP.accentFill) : AnyShapeStyle(Color.white.opacity(0.10))))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                Text(title).font(SP.rounded(12, .medium)).foregroundStyle(SP.dim).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Section title in the family style: headline weight, optional trailing detail.
struct SPSectionTitle: View {
    let title: String
    var detail: String? = nil
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(SP.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.footnote).foregroundStyle(SP.faint).multilineTextAlignment(.trailing) }
        }
    }
}

/// Designed empty state: symbol, title, one-line hint, optional action.
struct SPEmptyState: View {
    let symbol: String
    let title: String
    let hint: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: SP.s3) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(SP.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(SP.accent.opacity(0.12)))
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(SP.ink).multilineTextAlignment(.center)
            Text(hint).font(.subheadline).foregroundStyle(SP.dim).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(SPPrimaryButtonStyle(fullWidth: false))
                    .padding(.top, SP.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SP.s6)
        .padding(.horizontal, SP.s4)
    }
}

/// A soft pulsing placeholder block for data that is still loading (still when Reduce Motion is on).
struct SPSkeleton: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var radius: CGFloat = 6
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(on ? 0.12 : 0.06))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
            }
            .accessibilityHidden(true)
    }
}
