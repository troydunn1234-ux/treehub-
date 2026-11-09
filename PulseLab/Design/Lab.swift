import Charts
import SwiftUI

/// Pulse Lab's look: a dark lab bench with a faint grid, two signature colours
/// (Apple Watch = electric cyan, WHOOP = hot amber), mono numerics and heavy rounded headings.
enum Lab {
    static let bg = Color(red: 0.020, green: 0.016, blue: 0.040)
    static let panel = Color(red: 0.060, green: 0.052, blue: 0.105)
    static let line = Color.white.opacity(0.07)
    static let text = Color(red: 0.93, green: 0.94, blue: 1.0)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let watch = Color(red: 0.20, green: 0.92, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.66, blue: 0.16)
    static let violet = Color(red: 0.58, green: 0.38, blue: 1.00)
    static let good = Color(red: 0.25, green: 0.95, blue: 0.55)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.30, blue: 0.40)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

    static func color(_ s: Source) -> Color { s == .watch ? watch : whoop }

    /// Recovery / readiness colour bands (WHOOP style: red < 34 ≤ yellow < 67 ≤ green).
    static func band(_ score: Double) -> Color { score >= 67 ? good : score >= 34 ? warn : bad }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
}

// MARK: - Background

/// Near-black with a faint lab grid, a violet haze and a slow scanline.
struct LabBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Lab.bg
            RadialGradient(colors: [Lab.violet.opacity(0.22), .clear], center: .top, startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Lab.watch.opacity(0.08), .clear], center: .bottomLeading, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Lab.whoop.opacity(0.07), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 420)
            Canvas { ctx, size in
                let step: CGFloat = 26
                var p = Path()
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(Color.white.opacity(0.035)), lineWidth: 0.5)
            }
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    GeometryReader { geo in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let y = CGFloat((t.truncatingRemainder(dividingBy: 7)) / 7) * (geo.size.height + 120) - 60
                        LinearGradient(colors: [.clear, Lab.watch.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .offset(y: y)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panels

struct LabPanel<Content: View>: View {
    var tint: Color = Lab.violet
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Lab.panel.opacity(0.95), Lab.panel.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [tint.opacity(0.45), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.12), radius: 18, y: 6)
    }
}

struct SectionTag: View {
    let text: String
    var color: Color = Lab.dim
    init(_ text: String, color: Color = Lab.dim) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Lab.label(11)).tracking(2.2).foregroundStyle(color)
    }
}

struct ScreenTitle: View {
    let kicker: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Lab.watch).frame(width: 6, height: 6)
                Circle().fill(Lab.whoop).frame(width: 6, height: 6)
                Text(kicker.uppercased()).font(Lab.label(11)).tracking(2.6).foregroundStyle(Lab.dim)
            }
            Text(title).font(Lab.display(34)).foregroundStyle(Lab.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small coloured source chip: "● WATCH" / "● WHOOP".
struct SourceChip: View {
    let source: Source
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(source)).frame(width: 6, height: 6).shadow(color: Lab.color(source), radius: 4)
            Text(source.short).font(Lab.label(10)).tracking(1.5).foregroundStyle(Lab.color(source))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Lab.color(source).opacity(0.12)))
    }
}

// MARK: - Numbers

/// A number that counts up when it first appears (mono, glowing).
struct CountUp: View {
    let value: Double?
    var decimals: Int = 0
    var size: CGFloat = 30
    var color: Color = Lab.text
    @State private var shown: Double = 0

    var body: some View {
        Group {
            if let value {
                Text(shown, format: .number.precision(.fractionLength(decimals)))
                    .contentTransition(.numericText(value: shown))
                    .onAppear { animate(to: value) }
                    .onChange(of: value) { _, v in animate(to: v) }
            } else {
                Text("––")
            }
        }
        .font(Lab.mono(size, .heavy))
        .foregroundStyle(color)
        .shadow(color: color.opacity(0.45), radius: 8)
        .monospacedDigit()
    }

    private func animate(to v: Double) {
        if Lab.reduceMotion { shown = v; return }
        withAnimation(.easeOut(duration: 0.9)) { shown = v }
    }
}

// MARK: - Gauge

/// Ring gauge 0–100 with a glowing gradient stroke.
struct GaugeRing: View {
    let value: Double?
    let label: String
    let color: Color
    var size: CGFloat = 120
    @State private var drawn: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 12)
            Circle()
                .trim(from: 0, to: drawn / 100)
                .stroke(AngularGradient(colors: [color.opacity(0.4), color, color], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.7), radius: 10)
            VStack(spacing: 0) {
                CountUp(value: value, size: size * 0.28, color: Lab.text)
                Text(label.uppercased()).font(Lab.label(9)).tracking(1.5).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .onAppear { draw() }
        .onChange(of: value) { _, _ in draw() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value.map { Int($0).description } ?? "not available")")
    }

    private func draw() {
        let v = min(100, max(0, value ?? 0))
        if Lab.reduceMotion { drawn = v; return }
        drawn = 0   // always sweep up from empty, on every appearance
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 1.1)) { drawn = v } }
        guard value != nil else { return }
        // Small tap when the ring lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        }
    }
}

// MARK: - VS split row

/// One metric, Watch on the left, WHOOP on the right, with a delta in the middle.
struct VSRow: View {
    let title: String
    let unit: String
    let watch: Double?
    let whoop: Double?
    var decimals: Int = 0
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(Lab.label(10)).tracking(1.8).foregroundStyle(Lab.dim)
                Spacer()
                if let note { Text(note).font(Lab.label(9)).foregroundStyle(Lab.faint) }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    CountUp(value: watch, decimals: decimals, size: 26, color: Lab.watch)
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.watch.opacity(0.7))
                }
                Spacer()
                delta
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    CountUp(value: whoop, decimals: decimals, size: 26, color: Lab.whoop)
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.whoop.opacity(0.7))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): Apple Watch \(fmt(watch)) \(unit), WHOOP \(fmt(whoop)) \(unit)")
    }

    private var delta: some View {
        Group {
            if let a = watch, let b = whoop {
                let d = a - b
                Text((d >= 0 ? "+" : "−") + abs(d).formatted(.number.precision(.fractionLength(decimals))))
                    .font(Lab.mono(12, .bold))
                    .foregroundStyle(d >= 0 ? Lab.watch : Lab.whoop)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().strokeBorder(Color.white.opacity(0.12)))
            } else {
                Text("VS").font(Lab.display(14)).foregroundStyle(Lab.faint)
            }
        }
    }

    private func fmt(_ v: Double?) -> String { v.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data" }
}

struct RangePicker: View {
    @Binding var days: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach([7, 30, 90], id: \.self) { d in
                Button { withAnimation(.snappy) { days = d } } label: {
                    Text("\(d)D").font(Lab.mono(12, .heavy))
                        .foregroundStyle(days == d ? Lab.bg : Lab.dim)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(days == d ? AnyShapeStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.06))))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(days == d ? .isSelected : [])
            }
        }
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Lab.faint)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 18)
    }
}


/// Shared chart axes: faint grid, mono labels.
enum LabAxis {
    static var y: some AxisContent {
        AxisMarks(position: .leading) { _ in
            AxisGridLine().foregroundStyle(Lab.line)
            AxisValueLabel().foregroundStyle(Lab.faint).font(Lab.mono(9, .medium))
        }
    }
    static var xDays: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine().foregroundStyle(Lab.line)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Lab.faint).font(Lab.mono(9, .medium))
        }
    }
}
