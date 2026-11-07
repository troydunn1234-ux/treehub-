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

    #if TRACK_APP
    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    #else
    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .serif) }
    #endif

    /// Spacing scale (8-pt grid) so every screen lines up.
    static let pad: CGFloat = 20
    static let gap: CGFloat = 14
    static let radius: CGFloat = 26
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

// MARK: - Background with drifting leaves

struct ForestBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background
            if #available(iOS 18.0, *), !reduceMotion {
                AuroraMesh()
            } else {
                RadialGradient(colors: [Theme.leaf.opacity(0.25), .clear], center: .topTrailing, startRadius: 10, endRadius: 460)
                RadialGradient(colors: [Theme.gold.opacity(0.08), .clear], center: .bottomLeading, startRadius: 10, endRadius: 380)
            }
            // Soft vignette keeps edges calm and text readable.
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 220, endRadius: 700)
            #if !TRACK_APP
            if !reduceMotion { FallingLeaves() }
            #endif
        }
        .ignoresSafeArea()
    }
}

/// Slowly breathing aurora of the app's colors (iOS 18+).
@available(iOS 18.0, *)
struct AuroraMesh: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let w1 = Float(sin(t * 0.21) * 0.12), w2 = Float(cos(t * 0.17) * 0.12), w3 = Float(sin(t * 0.13 + 1) * 0.1)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + w1, 0], [1, 0],
                    [0, 0.45 + w2], [0.55 + w3, 0.5 + w1], [1, 0.4 + w3],
                    [0, 1], [0.45 + w2, 1], [1, 1],
                ],
                colors: [
                    Theme.forest, Theme.leaf.opacity(0.55), Theme.forest,
                    Theme.forestDeep, Theme.moss.opacity(0.9), Theme.glow.opacity(0.22),
                    Theme.forestDeep, Theme.forestDeep, Theme.forest,
                ],
                smoothsColors: true
            )
            .opacity(0.85)
        }
    }
}

struct FallingLeaves: View {
    private struct Flake { let x: Double; let speed: Double; let size: Double; let phase: Double; let hue: Int }
    private let flakes: [Flake] = {
        var rng = SeededRNG(seed: "leaves")
        return (0..<6).map { _ in
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
                    g.opacity = 0.13
                    g.fill(LeafPath(shape: .oval).path(in: r), with: .color(colors[f.hue]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cards & chips

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                // Light catches the top edge, fades toward the bottom.
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.glow)
            }
            Text(title).font(Theme.rounded(18, .bold)).foregroundStyle(.white)
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
        VStack(alignment: .leading, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
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
        .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.cardStroke, lineWidth: 1))
        .shadow(color: selected ? Theme.glow.opacity(0.35) : .clear, radius: 8, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
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

// MARK: - Motion

extension View {
    /// Cards ease in as they scroll into view and settle back as they leave.
    func cardAppear() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }

    /// Springy press feedback for tappable cards.
    func pressable() -> some View { buttonStyle(PressableStyle()) }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Floating tab bar

struct TabBarItem: Identifiable {
    let id: String
    let symbol: String
    let label: String
    var alert: Bool = false
}

/// Glass tab bar with a sliding highlight pill and an optional center action button.
struct FloatingTabBar: View {
    let items: [TabBarItem]
    @Binding var selection: String
    var centerSymbol: String? = nil
    var centerLabel: String = ""
    var centerAction: (() -> Void)? = nil
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            let half = centerAction == nil ? items.count : items.count / 2
            ForEach(items.prefix(half)) { tabButton($0) }
            if let centerAction, let centerSymbol {
                Button(action: centerAction) {
                    ZStack {
                        Circle().fill(Theme.leafGradient)
                            .frame(width: 58, height: 58)
                            .shadow(color: Theme.glow.opacity(0.55), radius: 14, y: 4)
                        Image(systemName: centerSymbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.forestDeep)
                    }
                }
                .pressable()
                .offset(y: -14)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(centerLabel)
                .sensoryFeedback(.impact(weight: .medium), trigger: selection)
            }
            ForEach(items.dropFirst(half)) { tabButton($0) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
            Capsule(style: .continuous).fill(Theme.forestDeep.opacity(0.35))
        }
        .overlay(Capsule(style: .continuous).strokeBorder(
            LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ item: TabBarItem) -> some View {
        let active = selection == item.id
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = item.id }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: active ? .bold : .semibold))
                    .symbolEffect(.pulse, isActive: item.alert)
                    .symbolEffect(.bounce, value: active)
                Text(item.label).font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(active ? Theme.forestDeep : (item.alert ? Color.red : Color.white.opacity(0.6)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if active {
                    Capsule(style: .continuous)
                        .fill(Theme.leafGradient)
                        .matchedGeometryEffect(id: "pill", in: pill)
                        .shadow(color: Theme.glow.opacity(0.4), radius: 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(item.label)")
        .sensoryFeedback(.selection, trigger: active)
    }
}
