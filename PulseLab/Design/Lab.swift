import Charts
import SwiftUI

/// Pulse Lab's look: a calm, dark data dashboard. Flat graphite cards, one red accent for controls,
/// and two fixed data colours used everywhere (Apple Watch = cyan, WHOOP = amber). Numbers are SF Rounded
/// with monospaced digits; text is plain SF.
enum Lab {
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.051)
    /// Card surface (close to iOS's dark secondary grouped background).
    static let panel = Color(red: 0.106, green: 0.106, blue: 0.118)
    /// Inner surface: rows / tiles inside a card.
    static let inset = Color.white.opacity(0.05)
    /// Hairlines, gridlines and card strokes.
    static let line = Color.white.opacity(0.08)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.97)
    /// Secondary text (AA on panel).
    static let dim = Color.white.opacity(0.66)
    /// Tertiary text: captions, axis labels (still ≥ 4.5:1 on panel).
    static let faint = Color.white.opacity(0.50)
    /// Fixed data colours: always Watch = cyan, WHOOP = amber, in every chart, chip and number.
    static let watch = Color(red: 0.25, green: 0.80, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.64, blue: 0.20)
    /// Pulse Lab's accent (buttons, selection, links).
    static let accent = Color(red: 1.00, green: 0.25, blue: 0.36)
    /// Data colour for REM sleep / the sleep category (not used for controls).
    static let violet = Color(red: 0.58, green: 0.45, blue: 1.00)
    static let good = Color(red: 0.22, green: 0.84, blue: 0.46)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.36, blue: 0.32)

    /// Card corner radius (continuous) and inner radius.
    static let radius: CGFloat = 20
    static let innerRadius: CGFloat = 12

    /// Dynamic Type: every Lab font follows the text size setting. Big display numbers grow less than
    /// small text (they're already large and sit in fixed layouts); small labels grow the most.
    static func scaled(_ size: CGFloat) -> CGFloat {
        let s = UIFontMetrics.default.scaledValue(for: size)
        let cap: CGFloat = size >= 28 ? 1.2 : size >= 18 ? 1.4 : 1.8
        return max(size * 0.85, min(s, size * cap))
    }
    /// Heavy weights are toned down one step: the dashboard reads sharper with bold, not black.
    private static func calm(_ w: Font.Weight) -> Font.Weight { (w == .black || w == .heavy) ? .bold : w }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: scaled(size), weight: calm(weight)) }
    /// Inline numbers and short numeric chips: rounded, monospaced digits.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: scaled(size), weight: weight == .black || weight == .heavy ? .bold : weight, design: .rounded).monospacedDigit()
    }
    /// Small uppercase captions (units, column heads). Never below 10 pt.
    static func label(_ size: CGFloat = 10) -> Font { .system(size: scaled(max(size + 1, 10)), weight: .semibold) }
    /// Big scoreboard numbers: rounded, monospaced digits.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: scaled(size), weight: calm(weight), design: .rounded).monospacedDigit()
    }
    /// Watch → WHOOP gradient (used sparingly: brand marks only).
    static let duel = LinearGradient(colors: [watch, whoop], startPoint: .leading, endPoint: .trailing)

    static func color(_ s: Source) -> Color { s == .watch ? watch : whoop }

    /// Recovery / readiness colour bands (WHOOP style: red < 34 ≤ yellow < 67 ≤ green).
    static func band(_ score: Double) -> Color { score >= 67 ? good : score >= 34 ? warn : bad }

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Spacing scale 4 / 8 / 12 / 16 / 24 / 32.
    enum S {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let sm: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
    /// Type scale: large title 34 · title 22 · headline 17 · body 15 · caption 11.
    static func title(_ size: CGFloat = 22, _ weight: Font.Weight = .bold) -> Font { .system(size: scaled(size), weight: calm(weight)) }
    static func body(_ size: CGFloat = 15, _ weight: Font.Weight = .regular) -> Font { .system(size: scaled(size), weight: calm(weight)) }

    /// One number format everywhere: grouping, fixed decimals, real minus sign.
    static func fmt(_ v: Double, _ decimals: Int = 0, signed: Bool = false) -> String {
        let s = abs(v).formatted(.number.precision(.fractionLength(decimals)))
        if v < 0 && s.contains(where: { $0 != "0" && $0 != "." && $0 != "," }) { return "−" + s }
        return (signed && v > 0 ? "+" : "") + s
    }

    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// The one primary button: filled accent, 50 pt tall, 14 pt corners.
struct LabPrimaryButton: ButtonStyle {
    var tint: Color = Lab.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lab.body(16, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary button: tinted fill, tinted text.
struct LabSecondaryButton: ButtonStyle {
    var tint: Color = Lab.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Lab.body(15, .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.15)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Cards and rows press down slightly under the finger.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Background

/// Flat near-black with a barely-there lift at the top. Static (nothing moves behind data).
struct LabBackground: View {
    var body: some View {
        ZStack {
            Lab.bg
            LinearGradient(colors: [Color.white.opacity(0.035), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panels

/// The one card style: flat panel, 20 pt continuous corners, 1 pt hairline. `tint` is kept for call sites
/// but only colours a 2 pt leading accent when `accentEdge` is set.
struct LabPanel<Content: View>: View {
    var tint: Color = Lab.accent
    var accentEdge = false
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Lab.S.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
            .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.line, lineWidth: 1))
            .overlay(alignment: .leading) {
                if accentEdge {
                    Capsule().fill(tint).frame(width: 3).padding(.vertical, 18).padding(.leading, 1)
                }
            }
    }
}

/// Card section header: `.headline`, sentence case.
struct SectionTag: View {
    let text: String
    var color: Color = Lab.dim
    init(_ text: String, color: Color = Lab.dim) { self.text = text; self.color = color }
    var body: some View {
        Text(L(text))
            .font(.headline)
            .foregroundStyle(color == Lab.dim ? Lab.text : color)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small status dot that softly pulses (still under Reduce Motion).
struct LiveDot: View {
    var color: Color = Lab.watch
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 1 : 0.5)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { on = true }
            }
            .accessibilityHidden(true)
    }
}

/// Screen header: small secondary kicker over a large bold title.
struct ScreenTitle: View {
    let kicker: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(kicker)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.dim)
                .lineLimit(2)
            Text(L(title)).font(Lab.display(34, .bold)).foregroundStyle(Lab.text)
                .lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small coloured source chip: "● Watch" / "● WHOOP" (sentence case, like every caption).
struct SourceChip: View {
    let source: Source
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(source)).frame(width: 6, height: 6)
            Text(source.label).font(Lab.label(10)).foregroundStyle(Lab.color(source))
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Lab.color(source).opacity(0.14)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.name)
    }
}

/// Sentence-case caption used above a number (column heads, units).
struct LabCaption: View {
    let text: String
    var color: Color = Lab.faint
    init(_ text: String, color: Color = Lab.faint) { self.text = text; self.color = color }
    var body: some View {
        Text(L(text)).font(.caption.weight(.semibold)).foregroundStyle(color)
    }
}

// MARK: - Numbers

/// A number that counts up when it first appears (rounded, monospaced digits). Nil shows an em dash.
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
                    .foregroundStyle(color)
            } else {
                Text("—").foregroundStyle(Lab.faint)
            }
        }
        .font(Lab.number(size, .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func animate(to v: Double) {
        if Lab.reduceMotion { shown = v; return }
        withAnimation(.easeOut(duration: 0.7)) { shown = v }
    }
}

// MARK: - Gauge

/// Ring gauge 0–100, flat stroke.
struct GaugeRing: View {
    let value: Double?
    let label: String
    let color: Color
    var size: CGFloat = 120
    @State private var drawn: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: drawn / 100)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                CountUp(value: value, size: size * 0.28, color: Lab.text)
                Text(L(label)).font(Lab.label(10)).foregroundStyle(Lab.dim)
            }
        }
        .frame(width: size, height: size)
        .onAppear { draw() }
        .onChange(of: value) { _, _ in draw() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(label)) \(value.map { Int($0.rounded()).description } ?? "not available")")
    }

    private func draw() {
        let v = min(100, max(0, value ?? 0))
        if Lab.reduceMotion { drawn = v; return }
        drawn = 0
        DispatchQueue.main.async { withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { drawn = v } }
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
                Text(L(title)).font(Lab.body(13, .semibold)).foregroundStyle(Lab.dim)
                Spacer()
                if let note { Text(note).font(Lab.label(9)).foregroundStyle(Lab.faint) }
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountUp(value: watch, decimals: decimals, size: 24, color: Lab.watch)
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint)
                }
                Spacer()
                delta
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    CountUp(value: whoop, decimals: decimals, size: 24, color: Lab.whoop)
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(title)): Apple Watch \(fmt(watch)) \(unit), WHOOP \(fmt(whoop)) \(unit)")
    }

    private var delta: some View {
        Group {
            if let a = watch, let b = whoop {
                DeltaPill(value: a - b, decimals: decimals)
            } else {
                Text("vs").font(Lab.body(13, .semibold)).foregroundStyle(Lab.faint)
            }
        }
    }

    private func fmt(_ v: Double?) -> String { v.map { Lab.fmt($0, decimals) } ?? "no data" }
}

/// Watch − WHOOP gap, neutral pill. Coloured text by which side reads higher.
struct DeltaPill: View {
    let value: Double
    var decimals: Int = 0
    var body: some View {
        let even = abs(value) < pow(10, -Double(decimals)) / 2
        Text(even ? "=" : Lab.fmt(value, decimals, signed: true))
            .font(Lab.mono(12, .semibold))
            .foregroundStyle(even ? Lab.faint : (value > 0 ? Lab.watch : Lab.whoop))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Lab.inset))
            .accessibilityLabel(even ? "Equal" : "Difference \(Lab.fmt(value, decimals, signed: true))")
    }
}

/// Segmented 7D / 30D / 90D / 1Y control (90D and 1Y are Pro).
struct RangePicker: View {
    @Binding var days: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach([7, 30, 90, 365], id: \.self) { d in
                Button {
                    if d >= 90 && !Unlock.shared.gate(d == 365 ? "Full-year history" : "90-day history") { return }
                    withAnimation(.snappy) { days = d }
                } label: {
                    HStack(spacing: 3) {
                        Text(d == 365 ? "1Y" : "\(d)D")
                        if d >= 90 && !Unlock.shared.isPro { Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold)) }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .font(Lab.mono(13, .semibold))
                    .foregroundStyle(days == d ? Color.white : Lab.dim)
                    .frame(minWidth: 44, minHeight: 32)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(days == d ? Lab.accent : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d == 365 ? "1 year" : "\(d) days")
                .accessibilityAddTraits(days == d ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Lab.inset))
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// The designed "nothing here yet" state inside a card: symbol, optional title, one-line hint and an
/// optional action. `EmptyNote(text:)` alone stays a quiet one-liner.
struct EmptyNote: View {
    let text: String
    var symbol: String = "chart.line.uptrend.xyaxis"
    var title: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Lab.S.s) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Lab.faint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Lab.inset))
                .accessibilityHidden(true)
            if let title {
                Text(L(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L(text)).font(.footnote).foregroundStyle(Lab.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button {
                    Lab.tick()
                    action()
                } label: {
                    Text(L(actionTitle))
                }
                .buttonStyle(LabSecondaryButton())
                .frame(maxWidth: 280)
                .padding(.top, Lab.S.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Lab.S.m)
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

// MARK: - Charts

/// The one chart style: hairline grid, rounded mono-digit axis labels, unit in the corner.
enum LabAxis {
    static let labelFont = Font.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()

    static var y: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Lab.line)
            AxisValueLabel().foregroundStyle(Lab.faint).font(labelFont)
        }
    }
    static var xDays: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Lab.line)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                .foregroundStyle(Lab.faint).font(labelFont)
        }
    }
    /// Category axis (bar charts with string x values).
    static var xLabels: some AxisContent {
        AxisMarks { _ in
            AxisValueLabel().foregroundStyle(Lab.faint).font(labelFont)
        }
    }

    /// Unit caption pinned to the top-left of the plot.
    static func unitLabel(_ unit: String) -> some View {
        Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(Lab.faint)
    }
}

/// Scrub tooltip used by every chart: date on top, one line per value.
struct LabChartTooltip: View {
    struct Line: Identifiable {
        let label: String
        let value: String
        let color: Color
        var id: String { label }
    }
    let title: String
    let lines: [Line]
    /// Optional footnote under the values ("Still counting").
    var note: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lab.dim)
            ForEach(lines) { l in
                HStack(spacing: 5) {
                    Circle().fill(l.color).frame(width: 6, height: 6)
                    Text(l.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Lab.dim)
                    Spacer(minLength: 6)
                    Text(l.value).font(Lab.mono(13, .semibold)).foregroundStyle(Lab.text)
                }
            }
            if let note {
                Text(note).font(.system(size: 10, weight: .medium)).foregroundStyle(Lab.faint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minWidth: 120)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    static func dayTitle(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

/// Snaps a raw chart-selection date to a day that has data, with a selection haptic. Marks plotted with
/// `unit: .day` sit in the middle of their day (bars span it), so the finger's day wins; between days with
/// data, the nearest day's middle does.
struct DaySelection: ViewModifier {
    let days: [Date]
    @Binding var selected: Date?
    @State private var raw: Date?
    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $raw)
            .onChange(of: raw) { _, r in
                let snapped = r.flatMap { DaySelection.snap($0, to: days) }
                if snapped != selected { selected = snapped }
            }
            .sensoryFeedback(.selection, trigger: selected)
    }

    static func snap(_ r: Date, to days: [Date]) -> Date? {
        if let same = days.first(where: { Calendar.current.isDate($0, inSameDayAs: r) }) { return same }
        func gap(_ d: Date) -> TimeInterval { abs(d.dayStart.addingTimeInterval(43_200).timeIntervalSince(r)) }
        return days.min { gap($0) < gap($1) }
    }
}

extension View {
    /// Press-and-drag scrubbing that snaps to `days`.
    func scrubDays(_ days: [Date], selection: Binding<Date?>) -> some View {
        modifier(DaySelection(days: days, selected: selection))
    }

    /// One VoiceOver element for a chart: its spoken summary (the scrub gesture stays for touch).
    func chartSummary(_ text: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

// MARK: - Rows & cards

/// Card header used by every card: optional tinted symbol, a `.headline` title (sentence case), an optional
/// one-line subtitle and trailing content (a link, chips or a count).
struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Lab.accent,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Lab.S.s) {
            if let symbol { SymbolTile(symbol: symbol, tint: tint, size: 30) }
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(.headline).foregroundStyle(Lab.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(L(subtitle)).font(.footnote).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Lab.S.s)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Lab.accent) {
        self.init(title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// Tinted rounded-square SF Symbol for rows and card headers. Grows a little with Dynamic Type.
struct SymbolTile: View {
    let symbol: String
    var tint: Color
    var size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(symbol: String, tint: Color = Lab.accent, size: CGFloat = 32) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        let s = size * min(max(scale, 1), 1.5)
        Image(systemName: symbol)
            .font(.system(size: s * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: s, height: s)
            .background(RoundedRectangle(cornerRadius: s * 0.3, style: .continuous).fill(tint.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

/// Small sentence-case tag: "Yesterday", "Baseline: last 14 days", "Still counting".
struct TagChip: View {
    let text: String
    var tint: Color = Lab.dim
    var symbol: String? = nil

    init(_ text: String, tint: Color = Lab.dim, symbol: String? = nil) {
        self.text = text
        self.tint = tint
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)).accessibilityHidden(true) }
            Text(L(text)).font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A number with its unit on one baseline: rounded, monospaced digits; unit small and dim.
struct NumberUnit: View {
    let value: String
    var unit: String = ""
    var color: Color = Lab.text
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(Lab.number(size)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint).lineLimit(1)
            }
        }
    }
}

/// One stat in a grid: sentence-case caption on top, the number (and unit) under it. A missing value says so
/// in words instead of showing a bare dash.
struct StatCell: View {
    let caption: String
    let value: String?
    var unit: String = ""
    var color: Color = Lab.text
    var size: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(caption)).font(.footnote.weight(.medium)).foregroundStyle(Lab.dim)
                .lineLimit(2).minimumScaleFactor(0.85)
            if let value {
                NumberUnit(value: value, unit: unit, color: color, size: size)
            } else {
                Text("No data").font(.subheadline).foregroundStyle(Lab.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Accent text link for card headers ("Details", "Trend"), 44 pt tall.
struct CardLink: View {
    let title: String
    var symbol = "chevron.right"
    let action: () -> Void

    init(_ title: String, symbol: String = "chevron.right", action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 4) {
                Text(L(title)).font(.subheadline.weight(.semibold))
                Image(systemName: symbol).font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            .foregroundStyle(Lab.accent)
            .frame(minHeight: 44)
            .padding(.leading, Lab.S.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }
}

/// A bulleted line of body text.
struct LabBullet: View {
    let text: String
    var tint: Color = Lab.faint
    var font: Font = .subheadline
    var color: Color = Lab.dim

    init(_ text: String, tint: Color = Lab.faint, font: Font = .subheadline, color: Color = Lab.dim) {
        self.text = text
        self.tint = tint
        self.font = font
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
            Circle().fill(tint).frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            Text(L(text)).font(font).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Inset box with an info symbol: why two trackers differ, method notes.
struct InfoBox: View {
    let text: String
    var tint: Color = Lab.accent

    var body: some View {
        HStack(alignment: .top, spacing: Lab.S.s) {
            Image(systemName: "info.circle.fill").font(.footnote).foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(L(text)).font(.footnote).foregroundStyle(Lab.dim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Lab.S.sm)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(tint.opacity(0.08)))
    }
}

/// Looks up a runtime string (titles passed around as `String`) in the String Catalog.
/// Strings with no entry come back unchanged.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

extension Source {
    /// Display name in sentence case for legends and tooltips ("Watch" / "WHOOP").
    var label: String { self == .watch ? "Watch" : "WHOOP" }
}
