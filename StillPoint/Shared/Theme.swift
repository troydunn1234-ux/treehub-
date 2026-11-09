import SwiftUI

/// Still Point look: deep night, teal breath, soft gold.
enum SP {
    // Dusk palette: indigo → plum → warm amber, with a mist teal for the breath.
    static let nightTop = Color(spHex: "#1C1844")
    static let night = Color(spHex: "#2A1838")
    static let nightBottom = Color(spHex: "#0B0912")
    static let plum = Color(spHex: "#5A2F55")
    static let amber = Color(spHex: "#E9B97A")
    static let indigo = Color(spHex: "#6A5ACD")
    static let violet = Color(spHex: "#A99BE8")
    static let teal = Color(spHex: "#8FD3CC")
    static let gold = Color(spHex: "#EBC88E")
    static let rose = Color(spHex: "#E8A6A6")
    static let ink = Color(spHex: "#F4EFE6")
    static let dim = Color(spHex: "#F4EFE6").opacity(0.62)
    static let faint = Color(spHex: "#F4EFE6").opacity(0.38)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)

    static var background: LinearGradient {
        LinearGradient(colors: [nightTop, night, nightBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Dawn: for summary / "Well done" screens.
    static var dawn: LinearGradient {
        LinearGradient(colors: [Color(spHex: "#2A2150"), plum, Color(spHex: "#B5745A"), Color(spHex: "#E9B97A").opacity(0.9)],
                       startPoint: .top, endPoint: .bottom)
    }

    static let breath = LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGlow = LinearGradient(colors: [gold, Color(spHex: "#F6DDA8")], startPoint: .leading, endPoint: .trailing)

    /// New York serif for titles.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// SF Rounded for everything else.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func numbers(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded).monospacedDigit()
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
    var glow: Color = SP.amber
    var body: some View {
        ZStack {
            SP.background
            RadialGradient(colors: [glow.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [SP.teal.opacity(0.10), .clear], center: UnitPoint(x: 0.15, y: 0.1), startRadius: 10, endRadius: 380)
            Grain()
        }
        .ignoresSafeArea()
    }
}
