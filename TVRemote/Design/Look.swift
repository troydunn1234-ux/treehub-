import SwiftUI

/// Clankerr's look — "neon console": deep space, layered glass, electric magenta → violet → cyan.
enum Look {
    // Base palette
    static let bg = Color(red: 0.027, green: 0.024, blue: 0.065)
    static let bgDeep = Color(red: 0.012, green: 0.010, blue: 0.035)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.10)
    static let magenta = Color(red: 1.0, green: 0.24, blue: 0.62)
    static let violet = Color(red: 0.55, green: 0.33, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.38)
    static let live = Color(red: 0.25, green: 0.95, blue: 0.55)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let accent = LinearGradient(colors: [magenta, violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentH = LinearGradient(colors: [magenta, violet, cyan], startPoint: .leading, endPoint: .trailing)

    /// Spacing scale: 4 / 8 / 12 / 16 / 24 / 32.
    enum S {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    /// Big confident display type.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

// MARK: - Text styles

/// Small caps label with wide tracking.
struct CapsLabel: View {
    let text: String
    var color: Color = Look.dim
    var size: CGFloat = 11
    init(_ text: String, color: Color = Look.dim, size: CGFloat = 11) { self.text = text; self.color = color; self.size = size }
    var body: some View {
        Text(text.uppercased()).font(Look.font(size, .heavy)).tracking(size * 0.22).foregroundStyle(color)
    }
}

/// "YOUR APPS ———— Edit" style section header.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: Look.S.m) {
            CapsLabel(title, color: .white.opacity(0.7))
            Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.title = title; self.trailing = { EmptyView() } }
}

// MARK: - Glass

/// Layered glass: soft gradient fill, top highlight, gradient rim and a tinted shadow.
/// Cheap by default (no blur) so screens stay instant; pass `material: true` for real blur.
struct Glass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color = .white
    var glow: Color? = nil
    var material = false
    var strength: Double = 1

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if material { shape.fill(.ultraThinMaterial) }
                    shape.fill(LinearGradient(colors: [tint.opacity(0.13 * strength), tint.opacity(0.035 * strength)],
                                              startPoint: .top, endPoint: .bottom))
                    // Inner highlight along the top edge.
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center), lineWidth: 2)
                        .blur(radius: 1.5)
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06), (glow ?? .white).opacity(glow == nil ? 0.10 : 0.55)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: (glow ?? .black).opacity(glow == nil ? 0.35 : 0.40), radius: glow == nil ? 14 : 18, y: 8)
    }
}

extension View {
    func glass(_ radius: CGFloat = 24, tint: Color = .white, glow: Color? = nil, material: Bool = false, strength: Double = 1) -> some View {
        modifier(Glass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, glow: glow, material: material, strength: strength))
    }
    func glassCapsule(tint: Color = .white, glow: Color? = nil, material: Bool = false, strength: Double = 1) -> some View {
        modifier(Glass(shape: Capsule(), tint: tint, glow: glow, material: material, strength: strength))
    }
    func glassCircle(tint: Color = .white, glow: Color? = nil, material: Bool = false, strength: Double = 1) -> some View {
        modifier(Glass(shape: Circle(), tint: tint, glow: glow, material: material, strength: strength))
    }
}

// MARK: - Background

/// Deep space: slow aurora blobs, a faint starfield that twinkles, and a vignette.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stars: [(x: Double, y: Double, r: Double, ph: Double)] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<70).map { _ in (rnd(), rnd(), 0.4 + rnd() * 1.1, rnd() * 6.28) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let full = Path(CGRect(origin: .zero, size: size))
                ctx.fill(full, with: .linearGradient(Gradient(colors: [Look.bg, Look.bgDeep]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                // Aurora
                let blobs: [(Color, Double, Double, Double, Double)] = [
                    (Look.magenta, 0.15, 0.10, 0.0, 0.26), (Look.violet, 0.85, 0.32, 2.0, 0.24),
                    (Look.cyan, 0.30, 0.88, 4.0, 0.18), (Look.violet, 0.70, 0.70, 5.2, 0.12)]
                for (c, x, y, ph, a) in blobs {
                    let cx = size.width * (x + 0.09 * sin(t * 0.11 + ph))
                    let cy = size.height * (y + 0.06 * cos(t * 0.09 + ph))
                    let r = size.width * 0.85
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r / 2, y: cy - r / 2, width: r, height: r)),
                             with: .radialGradient(Gradient(colors: [c.opacity(a), .clear]), center: CGPoint(x: cx, y: cy),
                                                   startRadius: 0, endRadius: r / 2))
                }
                // Stars
                for s in Self.stars {
                    let tw = reduceMotion ? 0.6 : 0.35 + 0.35 * (1 + sin(t * 1.3 + s.ph)) / 2
                    let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s.r, y: p.y - s.r, width: s.r * 2, height: s.r * 2)),
                             with: .color(.white.opacity(tw * 0.55)))
                }
                // Vignette
                ctx.fill(full, with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]),
                                                     center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                                                     startRadius: size.width * 0.35, endRadius: size.height * 0.75))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Bits

/// A small glowing status dot that softly pulses.
struct LiveDot: View {
    var color: Color = Look.live
    var size: CGFloat = 8
    var pulsing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: size, height: size)
                .scaleEffect(on ? 2.4 : 1).opacity(on ? 0 : 0.9)
            Circle().fill(color).frame(width: size, height: size).shadow(color: color, radius: 4)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

/// Animated "live" bars.
struct EqualizerBars: View {
    let color: Color
    var bars = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 1 : tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: g.size.width * 0.12) {
                    ForEach(0..<bars, id: \.self) { i in
                        Capsule().fill(color)
                            .frame(height: g.size.height * (0.25 + 0.75 * abs(sin(t * (2.2 + Double(i) * 0.7) + Double(i)))))
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Radar used by TV and PC pairing: rings, a sweeping beam, blips and a glowing core.
struct RadarView: View {
    var scanning: Bool
    var icon: String
    var blips: Int = 0
    var diameter: CGFloat = 250
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Glow floor
            Circle().fill(RadialGradient(colors: [Look.violet.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: diameter * 0.6))
                .frame(width: diameter * 1.25, height: diameter * 1.25)
            ForEach(1..<5, id: \.self) { i in
                Circle().strokeBorder(Color.white.opacity(i == 4 ? 0.16 : 0.07), lineWidth: 1)
                    .frame(width: diameter * CGFloat(i) / 4, height: diameter * CGFloat(i) / 4)
            }
            // Crosshair
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1, height: diameter)
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: diameter, height: 1)

            if scanning {
                TimelineView(.animation(minimumInterval: 1 / 40, paused: reduceMotion)) { tl in
                    let angle = reduceMotion ? 300 : (tl.date.timeIntervalSinceReferenceDate * 140).truncatingRemainder(dividingBy: 360)
                    ZStack {
                        Circle()
                            .fill(AngularGradient(gradient: Gradient(stops: [
                                .init(color: Look.cyan.opacity(0), location: 0.0),
                                .init(color: Look.cyan.opacity(0), location: 0.70),
                                .init(color: Look.violet.opacity(0.22), location: 0.9),
                                .init(color: Look.cyan.opacity(0.55), location: 1.0)]), center: .center))
                        // The beam's leading edge.
                        Rectangle()
                            .fill(LinearGradient(colors: [Look.cyan.opacity(0.9), Look.cyan.opacity(0)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: diameter / 2, height: 2)
                            .offset(x: diameter / 4)
                            .shadow(color: Look.cyan, radius: 6)
                    }
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(angle))
                }
                .transition(.opacity)
            }

            // Blips for found devices
            ForEach(0..<min(blips, 6), id: \.self) { i in
                let a = Double(i) * 2.4 + 0.7
                let r = Double(diameter) * (0.22 + 0.06 * Double(i % 3))
                LiveDot(color: Look.cyan, size: 7)
                    .offset(x: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r))
                    .transition(.scale.combined(with: .opacity))
            }

            // Pulse rings
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(Look.accent, lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 2.3 : 0.9)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(Double(i) * 1.3), value: pulse)
            }

            // Core
            Circle().fill(Look.accent).frame(width: 96, height: 96)
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)).padding(3))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .shadow(color: Look.magenta.opacity(0.7), radius: 26)
                .shadow(color: Look.cyan.opacity(0.35), radius: 40)
            Image(systemName: icon)
                .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .frame(width: diameter, height: diameter)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: blips)
        .animation(.easeInOut(duration: 0.4), value: scanning)
        .onAppear { if !reduceMotion { pulse = true } }
        .accessibilityHidden(true)
    }
}

/// Code entry boxes (TV PIN and PC code) with a glowing focused box.
struct CodeBoxes: View {
    let code: String
    let count: Int
    var boxWidth: CGFloat = 58
    var boxHeight: CGFloat = 72
    var focused: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false

    var body: some View {
        HStack(spacing: count > 4 ? Look.S.s : Look.S.m) {
            ForEach(0..<count, id: \.self) { i in
                let chars = Array(code)
                let ch = i < chars.count ? String(chars[i]) : ""
                let active = focused && i == chars.count
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(active ? 0.14 : 0.08), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(active ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(ch.isEmpty ? 0.12 : 0.28)),
                                      lineWidth: active ? 2 : 1)
                    if ch.isEmpty {
                        if active {
                            Capsule().fill(Look.accent).frame(width: 3, height: boxHeight * 0.4)
                                .opacity(blink ? 0.15 : 1)
                        }
                    } else {
                        Text(ch).font(.system(size: boxHeight * 0.48, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .frame(width: boxWidth, height: boxHeight)
                .shadow(color: active ? Look.magenta.opacity(0.55) : .clear, radius: 14)
                .scaleEffect(active ? 1.05 : 1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: code)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { blink = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Code, \(code.count) of \(count) digits entered")
    }
}

/// A list row card for a found TV / PC.
struct DeviceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var busy = false
    var body: some View {
        HStack(spacing: Look.S.m) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Look.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Look.violet.opacity(0.5), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Look.font(17, .heavy)).foregroundStyle(.white)
                Text(subtitle).font(Look.font(12, .semibold)).foregroundStyle(Look.dim)
            }
            Spacer()
            if busy { ProgressView().tint(.white) }
            else {
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Color.white.opacity(0.1), in: Circle())
            }
        }
        .padding(Look.S.m)
        .padding(.trailing, Look.S.xs)
        .glass(22, glow: Look.violet)
    }
}

// MARK: - Button styles

/// Springy press feel for any button.
struct SquishStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Primary call-to-action capsule.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Look.font(16, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, Look.S.xl)
            .frame(minHeight: 52)
            .background(Look.accentH, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Look.magenta.opacity(0.5), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
