import SwiftUI
import SwiftData
import Charts

@MainActor
struct StatsView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    /// Re-renders the screen when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false
    @State private var period: Period = .month
    @Namespace private var periodPill

    private static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
        var caption: String {
            switch self {
            case .week: return "Last 7 days"
            case .month: return "Last 30 days"
            case .year: return "Last 12 months"
            case .all: return "All time"
            }
        }
    }

    private struct KindTotal: Identifiable {
        let kind: ActivityKind
        let count: Int
        let distance: Double
        var id: String { kind.rawValue }
    }

    private struct WeekBar: Identifiable {
        let week: Date
        let kind: ActivityKind
        let value: Double
        var id: String { "\(week.timeIntervalSince1970)-\(kind.rawValue)" }
    }

    private struct Record: Identifiable {
        let label: String
        let symbol: String
        let tint: Color
        let value: String
        let activity: Activity
        var id: String { label }
    }

    private struct Totals {
        let distance: Double
        let time: Double
        let count: Int
        let climb: Double
    }

    // MARK: Data

    private var periodActivities: [Activity] {
        guard let days = period.days else { return activities }
        let cutoff: Date = Date().addingTimeInterval(-Double(days) * 86_400)
        return activities.filter { $0.start >= cutoff }
    }

    private var totals: Totals {
        let list = periodActivities
        let distance: Double = list.reduce(0.0) { $0 + $1.distanceM }
        let time: Double = list.reduce(0.0) { $0 + $1.elapsedSec }
        let climb: Double = list.filter { $0.kind.isOnFoot }.reduce(0.0) { $0 + $1.elevGainM }
        return Totals(distance: distance, time: time, count: list.count, climb: climb)
    }

    /// Distance in the equally long period just before this one (nil for "All").
    private var previousDistance: Double? {
        guard let days = period.days else { return nil }
        let span: Double = Double(days) * 86_400
        let end: Date = Date().addingTimeInterval(-span)
        let start: Date = end.addingTimeInterval(-span)
        let items: [Activity] = activities.filter { $0.start >= start && $0.start < end }
        return items.reduce(0.0) { $0 + $1.distanceM }
    }

    private var kindTotals: [KindTotal] {
        let list = periodActivities
        let all: [KindTotal] = ActivityKind.allCases.compactMap { (k: ActivityKind) -> KindTotal? in
            let items = list.filter { $0.kind == k }
            guard !items.isEmpty else { return nil }
            return KindTotal(kind: k, count: items.count, distance: items.reduce(0.0) { $0 + $1.distanceM })
        }
        return all.sorted { $0.distance > $1.distance }
    }

    private static func userUnits(_ meters: Double) -> Double {
        Units.metric ? meters / 1000 : meters / 1609.344
    }

    private static func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .walk: return Theme.glow
        case .run: return Theme.leaf
        case .hike: return Theme.gold
        case .bike: return Theme.sky
        case .drive: return Color(white: 0.78)
        }
    }

    private var firstWeek: Date {
        let cal = Calendar.current
        let current = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return cal.date(byAdding: .weekOfYear, value: -7, to: current) ?? current
    }

    private var weekBars: [WeekBar] {
        let cal = Calendar.current
        let start = firstWeek
        var sums: [String: WeekBar] = [:]
        for a in activities where a.start >= start && a.distanceM > 0 {
            let week = cal.dateInterval(of: .weekOfYear, for: a.start)?.start ?? start
            let key = "\(week.timeIntervalSince1970)-\(a.kind.rawValue)"
            let prev: Double = sums[key]?.value ?? 0
            sums[key] = WeekBar(week: week, kind: a.kind, value: prev + Self.userUnits(a.distanceM))
        }
        return sums.values.sorted { ($0.week, $0.kind.rawValue) < ($1.week, $1.kind.rawValue) }
    }

    private var records: [Record] {
        var out: [Record] = []
        func add(_ label: String, _ symbol: String, _ tint: Color, _ a: Activity?, _ value: (Activity) -> String) {
            if let a { out.append(Record(label: label, symbol: symbol, tint: tint, value: value(a), activity: a)) }
        }
        func longest(_ kind: ActivityKind) -> Activity? {
            activities.filter { $0.kind == kind && $0.distanceM > 0 }.max { $0.distanceM < $1.distanceM }
        }
        func runSeconds(_ a: Activity) -> Double { a.movingSec > 0 ? a.movingSec : a.elapsedSec }
        let minRun: Double = Units.metric ? 1600 : 1609.344
        let fastest: Activity? = activities
            .filter { $0.kind == .run && $0.distanceM >= minRun && runSeconds($0) > 0 }
            .min { runSeconds($0) / $0.distanceM < runSeconds($1) / $1.distanceM }
        let climb: Activity? = activities.filter { $0.kind.isOnFoot && $0.elevGainM > 0 }.max { $0.elevGainM < $1.elevGainM }
        let top: Activity? = activities.filter { $0.maxSpeed > 0 && $0.maxSpeed.isFinite }.max { $0.maxSpeed < $1.maxSpeed }

        add("Longest run", "figure.run", Theme.leaf, longest(.run)) { Format.distance($0.distanceM) }
        add("Fastest run pace", "stopwatch.fill", Theme.glow, fastest) {
            Format.paceOrSpeed(distance: $0.distanceM, seconds: runSeconds($0), kind: .run)
        }
        add("Longest hike", "figure.hiking", Theme.gold, longest(.hike)) { Format.distance($0.distanceM) }
        add("Biggest climb", "mountain.2.fill", Theme.gold, climb) { Format.elevation($0.elevGainM) }
        add("Longest ride", "bicycle", Theme.sky, longest(.bike)) { Format.distance($0.distanceM) }
        add("Longest drive", "car.fill", Color(white: 0.78), longest(.drive)) { Format.distance($0.distanceM) }
        add("Top speed", "gauge.with.dots.needle.67percent", Theme.leaf, top) { Format.speed($0.maxSpeed) }
        return out
    }

    private var subtitle: String {
        let n = activities.count
        guard n > 0 else { return "Your totals, trends and records" }
        let total: Double = activities.reduce(0.0) { $0 + $1.distanceM }
        return "\(n) \(n == 1 ? "trip" : "trips") all time · \(Format.distance(total))"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    header

                    if activities.isEmpty {
                        emptyState
                    } else {
                        periodSelector
                        heroCard.cardAppear()
                        byTypeSection
                        chartCard.cardAppear()
                        recordsSection
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 130)
                .animation(Self.spring, value: period)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stats")
                .font(Theme.title(34))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(Theme.rounded(14, .semibold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Period selector

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases) { (p: Period) in
                periodButton(p)
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous).fill(.ultraThinMaterial).opacity(0.6)
            Capsule(style: .continuous).fill(Color.white.opacity(0.05))
        }
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: period)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
    }

    private func periodButton(_ p: Period) -> some View {
        let selected: Bool = period == p
        let traits: AccessibilityTraits = selected ? .isSelected : []
        return Button {
            withAnimation(Self.spring) { period = p }
        } label: {
            Text(p.rawValue)
                .font(Theme.rounded(14, .bold))
                .foregroundStyle(selected ? Theme.forestDeep : Color.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(Theme.leafGradient)
                            .matchedGeometryEffect(id: "periodPill", in: periodPill)
                            .shadow(color: Theme.glow.opacity(0.35), radius: 8, y: 2)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.caption)
        .accessibilityAddTraits(traits)
    }

    // MARK: Hero

    private var heroCard: some View {
        let t = totals
        return GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                heroTopRow
                heroNumber(t.distance)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                heroStats(t)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(RadialGradient(colors: [Theme.leaf.opacity(0.35), .clear],
                                     center: .topTrailing, startRadius: 0, endRadius: 280))
        }
    }

    private var heroTopRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.glow)
            Text(period.caption.uppercased())
                .font(Theme.rounded(12, .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textDim)
                .contentTransition(.interpolate)
            Spacer(minLength: 8)
            deltaChip
        }
    }

    private func heroNumber(_ distance: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Format.distanceValue(distance))
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Format.distanceUnit)
                .font(Theme.rounded(20, .bold))
                .foregroundStyle(Theme.glow)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total distance \(Format.distance(distance))")
    }

    @ViewBuilder
    private var deltaChip: some View {
        if let prev = previousDistance, prev > 0 {
            let current: Double = totals.distance
            let pct: Double = (current - prev) / prev * 100
            let up: Bool = pct >= 0
            let tint: Color = up ? Theme.glow : Color.white.opacity(0.7)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .heavy))
                Text("\(Int(abs(pct).rounded()))%")
                    .font(Theme.rounded(12, .bold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(up ? "Up" : "Down") \(Int(abs(pct).rounded())) percent from the previous period")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func heroStats(_ t: Totals) -> some View {
        HStack(spacing: 0) {
            miniStat(value: Format.duration(t.time), label: "Time", symbol: "clock.fill", tint: Theme.sky)
            statDivider
            miniStat(value: "\(t.count)", label: t.count == 1 ? "Trip" : "Trips", symbol: "flag.checkered", tint: Theme.leaf)
            statDivider
            miniStat(value: Format.elevation(t.climb), label: "Climb", symbol: "mountain.2.fill", tint: Theme.gold)
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 6)
    }

    private func miniStat(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Text(value)
                .font(Theme.rounded(18, .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: By type

    private var byTypeSection: some View {
        let list = kindTotals
        let maxDistance: Double = list.map { $0.distance }.max() ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By type", symbol: "square.stack.3d.up.fill")
                .padding(.top, 6)
            if list.isEmpty {
                GlassCard {
                    Text("No trips in this period.")
                        .font(Theme.rounded(13, .medium))
                        .foregroundStyle(Theme.textDim)
                }
                .transition(.opacity)
            } else {
                ForEach(list) { (t: KindTotal) in
                    kindRow(t, fraction: maxDistance > 0 ? t.distance / maxDistance : 0)
                        .cardAppear()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    private func kindRow(_ t: KindTotal, fraction: Double) -> some View {
        let tint: Color = Self.color(for: t.kind)
        return HStack(spacing: 14) {
            Image(systemName: t.kind.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.kind.title)
                        .font(Theme.rounded(16, .bold))
                        .foregroundStyle(.white)
                    Text("\(t.count) \(t.count == 1 ? "trip" : "trips")")
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Text(Format.distance(t.distance))
                        .font(Theme.rounded(15, .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                shareBar(fraction: fraction, tint: tint)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial).opacity(0.5)
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    private func shareBar(fraction: Double, tint: Color) -> some View {
        let clamped: CGFloat = CGFloat(min(max(fraction, 0), 1))
        return Capsule()
            .fill(Color.white.opacity(0.07))
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(5, geo.size.width * clamped))
                }
            }
            .clipShape(Capsule())
    }

    // MARK: Chart

    private var chartCard: some View {
        let bars = weekBars
        let kinds: [ActivityKind] = ActivityKind.allCases.filter { k in bars.contains { $0.kind == k } }
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Last 8 weeks", symbol: "chart.bar.fill")
                    Text(Format.distanceUnit)
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.textDim)
                }
                if bars.isEmpty {
                    Text("No distance logged in the last 8 weeks.")
                        .font(Theme.rounded(13, .medium))
                        .foregroundStyle(Theme.textDim)
                } else {
                    weekChart(bars, kinds: kinds)
                    chartLegend(kinds)
                }
            }
        }
    }

    private func weekChart(_ bars: [WeekBar], kinds: [ActivityKind]) -> some View {
        let domain: [String] = kinds.map { $0.title }
        let range: [Color] = kinds.map { Self.color(for: $0) }
        let start = firstWeek
        let end: Date = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: start) ?? Date()
        return Chart(bars) { (b: WeekBar) in
            BarMark(x: .value("Week", b.week, unit: .weekOfYear),
                    y: .value("Distance", b.value))
                .foregroundStyle(by: .value("Type", b.kind.title))
                .cornerRadius(6)
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.rounded(10, .semibold))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Color.white.opacity(0.07))
                AxisValueLabel()
                    .font(Theme.rounded(10, .semibold))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .chartLegend(.hidden)
        .environment(\.colorScheme, .dark)
        .frame(height: 190)
    }

    private func chartLegend(_ kinds: [ActivityKind]) -> some View {
        FlowLayout(spacing: 12) {
            ForEach(kinds) { (k: ActivityKind) in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.color(for: k))
                        .frame(width: 8, height: 8)
                    Text(k.title)
                        .font(Theme.rounded(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: Records

    private var recordsSection: some View {
        let list = records
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Personal records", symbol: "trophy.fill")
                .padding(.top, 6)
            GlassCard(padding: 6) {
                if list.isEmpty {
                    Text("Records appear once you log some trips.")
                        .font(Theme.rounded(13, .medium))
                        .foregroundStyle(Theme.textDim)
                        .padding(12)
                } else {
                    VStack(spacing: 0) {
                        let firstID: String? = list.first?.id
                        ForEach(list) { (r: Record) in
                            if r.id != firstID {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 1)
                                    .padding(.leading, 64)
                                    .padding(.trailing, 12)
                            }
                            recordRow(r)
                        }
                    }
                }
            }
            .cardAppear()
        }
    }

    private func recordRow(_ r: Record) -> some View {
        NavigationLink(value: r.activity.id) {
            HStack(spacing: 14) {
                Image(systemName: r.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(r.tint)
                    .frame(width: 38, height: 38)
                    .background(r.tint.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label)
                        .font(Theme.rounded(15, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(Format.day(r.activity.start))
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 8)
                Text(r.value)
                    .font(Theme.rounded(15, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.glow)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .pressable()
    }

    // MARK: Empty

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 76, height: 76)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                Text("No stats yet")
                    .font(Theme.rounded(18, .bold))
                    .foregroundStyle(.white)
                Text("Record a trip from the Track tab to see totals, trends and records.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }
}
