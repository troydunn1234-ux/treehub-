import SwiftUI
import UIKit

enum Theme {
    #if TRACK_APP
    // Night-road palette for TrackHub
    static let forestDeep = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let forest = Color(red: 0.07, green: 0.11, blue: 0.20)
    static let moss = Color(red: 0.13, green: 0.19, blue: 0.32)
    static let leaf = Color(red: 1.0, green: 0.42, blue: 0.20)
    static let glow = Color(red: 1.0, green: 0.74, blue: 0.32)
    #else
    static let forestDeep = Color(red: 0.04, green: 0.13, blue: 0.09)
    static let forest = Color(red: 0.08, green: 0.24, blue: 0.16)
    static let moss = Color(red: 0.16, green: 0.38, blue: 0.24)
    static let leaf = Color(red: 0.36, green: 0.72, blue: 0.42)
    static let glow = Color(red: 0.74, green: 0.96, blue: 0.55)
    #endif
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.90)
    static let bark = Color(red: 0.42, green: 0.29, blue: 0.18)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.32)
    static let sky = Color(red: 0.45, green: 0.78, blue: 1.0)
    static let card = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.12)
    static let textDim = Color.white.opacity(0.65)

    #if TRACK_APP
    static let background = LinearGradient(
        colors: [Color(red: 0.09, green: 0.13, blue: 0.24), forestDeep, Color(red: 0.01, green: 0.02, blue: 0.05)],
        startPoint: .top, endPoint: .bottom)
    #else
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.20, blue: 0.14), forestDeep, Color(red: 0.02, green: 0.07, blue: 0.06)],
        startPoint: .top, endPoint: .bottom)
    #endif

    static let goldGradient = LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), gold, Color(red: 0.9, green: 0.55, blue: 0.15)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let leafGradient = LinearGradient(colors: [glow, leaf], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

// MARK: - Background with drifting leaves

struct ForestBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.leaf.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Theme.gold.opacity(0.08), .clear], center: .bottomLeading, startRadius: 10, endRadius: 380)
            #if !TRACK_APP
            if !reduceMotion { FallingLeaves() }
            #endif
        }
        .ignoresSafeArea()
    }
}

struct FallingLeaves: View {
    private struct Flake { let x: Double; let speed: Double; let size: Double; let phase: Double; let hue: Int }
    private let flakes: [Flake] = {
        var rng = SeededRNG(seed: "leaves")
        return (0..<9).map { _ in
            Flake(x: rng.next(), speed: 0.018 + rng.next() * 0.02, size: 10 + rng.next() * 12, phase: rng.next(), hue: Int(rng.next() * 3))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for f in flakes {
                    let p = (t * f.speed + f.phase).truncatingRemainder(dividingBy: 1)
                    let y = p * (size.height + 60) - 30
                    let x = f.x * size.width + sin(t * 0.8 + f.phase * 6) * 24
                    var g = gc
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(sin(t * 1.1 + f.phase * 9) * 1.2))
                    let r = CGRect(x: -f.size / 2, y: -f.size / 2, width: f.size, height: f.size)
                    let colors: [Color] = [Theme.leaf, Theme.gold, Color(red: 0.9, green: 0.45, blue: 0.2)]
                    g.opacity = 0.18
                    g.fill(LeafPath(shape: .oval).path(in: r), with: .color(colors[f.hue]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cards & chips

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Theme.glow) }
            Text(title).font(Theme.rounded(17, .bold)).foregroundStyle(.white)
            Spacer()
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = Theme.glow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
            }
            Text(value).font(Theme.rounded(22, .bold)).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
            Text(label.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Chip: View {
    let label: String
    var symbol: String? = nil
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
            Text(label).font(Theme.rounded(14, .semibold))
            if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? Theme.forestDeep : .white)
        .background(selected ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
        .overlay(Capsule().stroke(selected ? Color.clear : Theme.cardStroke, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.leafGradient
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(17, .bold))
            .foregroundStyle(Theme.forestDeep)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.glow.opacity(0.35), radius: configuration.isPressed ? 4 : 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Photo helpers

struct PhotoView: View {
    let data: Data?
    var placeholder: String = "tree.fill"

    var body: some View {
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Theme.moss, Theme.forest], startPoint: .top, endPoint: .bottom)
                Image(systemName: placeholder).font(.system(size: 30)).foregroundStyle(Theme.glow.opacity(0.6))
            }
        }
    }
}

enum ImageTools {
    /// Shrinks big camera photos so the library and iCloud sync stay light.
    static func compressed(_ data: Data, maxSide: CGFloat = 1800, quality: CGFloat = 0.82) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let size = img.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return out.jpegData(compressionQuality: quality) ?? data
    }
}

extension View {
    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: style).impactOccurred() })
    }
}

extension View {
    /// Forest background behind a whole screen, with a see-through navigation bar.
    func forestScreen() -> some View {
        self
            .background { ForestBackground() }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
