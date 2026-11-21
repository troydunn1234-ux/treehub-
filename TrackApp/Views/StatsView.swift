import SwiftUI
import SwiftData
import Charts

@MainActor
struct StatsView: View {
    @Query(sort: \Activity.start, order: .reverse) private var allTrips: [Activity]
    /// Roamr is a drive logbook: stats are about drives (older walks / rides stay in History, untouched).
    private var activities: [Activity] { allTrips.filter { $0.kind == .drive } }
    /// Re-renders the screen when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false
    @State private var period: Period = .month
    @State private var path = NavigationPath()
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

    private struct WeekBar: Identifiable {
        let week: Date
        let value: Double
        var id: Double { week.timeIntervalSince1970 }
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
        /// Moving seconds (time actually rolling), for average speed.
        let moving: Double
        let top: Double
        var avgSpeed: Double { moving > 0 ? distance / moving : 0 }
        var avgDrive: Double { count > 0 ? distance / Double(count) : 0 }
    }

    private static func movingSeconds(_ a: Activity) -> Double { a.movingSec > 0 ? a.movingSec : a.elapsedSec }

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
        let moving: Double = list.reduce(0.0) { $0 + Self.movingSeconds($1) }
        let top: Double = list.map(\.maxSpeed).filter { $0 > 0 && $0.isFinite }.max() ?? 0
        return Totals(distance: distance, time: time, count: list.count, moving: moving, top: top)
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

    private static func userUnits(_ meters: Double) -> Double {
        Units.metric ? meters / 1000 : meters / 1609.344
    }

    private var firstWeek: Date {
        let cal = Calendar.current
        let current = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return cal.date(byAdding: .weekOfYear, value: -7, to: current) ?? current
    }

    private var weekBars: [WeekBar] {
        let cal = Calendar.current
        let start = firstWeek
        var sums: [Date: Double] = [:]
        for a in activities where a.start >= start && a.distanceM > 0 {
            let week = cal.dateInterval(of: .weekOfYear, for: a.start)?.start ?? start
            sums[week, default: 0] += Self.userUnits(a.distanceM)
        }
        return sums.map { WeekBar(week: $0.key, value: $0.value) }.sorted { $0.week < $1.week }
    }

    private var records: [Record] {
        var out: [Record] = []
        func add(_ label: String, _ symbol: String, _ tint: Color, _ a: Activity?, _ value: (Activity) -> String) {
            if let a { out.append(Record(label: label, symbol: symbol, tint: tint, value: value(a), activity: a)) }
        }
        let longest: Activity? = activities.filter { $0.distanceM > 0 }.max { $0.distanceM < $1.distanceM }
        let longestTime: Activity? = activities.filter { Self.movingSeconds($0) > 0 }.max { Self.movingSeconds($0) < Self.movingSeconds($1) }
        let top: Activity? = activities.filter { $0.maxSpeed > 0 && $0.maxSpeed.isFinite }.max { $0.maxSpeed < $1.maxSpeed }
        // Best average speed over a real drive (at least 5 mi / 8 km), so a quick hop on the freeway doesn't win.
        let quickest: Activity? = activities
            .filter { $0.distanceM >= 8_000 && Self.movingSeconds($0) > 0 }
            .max { $0.distanceM / Self.movingSeconds($0) < $1.distanceM / Self.movingSeconds($1) }

        add("Longest drive", "car.fill", Theme.gold, longest) { Format.distance($0.distanceM) }
        add("Longest drive time", "clock.fill", Theme.sky, longestTime) { Format.duration(Self.movingSeconds($0)) }
        add("Top speed", "gauge.with.dots.needle.67percent", Theme.leaf, top) { Format.speed($0.maxSpeed) }
        add("Best average speed", "speedometer", Theme.glow, quickest) { Format.speed($0.distanceM / Self.movingSeconds($0)) }
        return out
    }

    private var subtitle: String {
        let n = activities.count
        guard n > 0 else { return "Miles driven, drive time, speed and fuel" }
        let total: Double = activities.reduce(0.0) { $0 + $1.distanceM }
        return "\(n) \(n == 1 ? "drive" : "drives") all time · \(Format.distance(total)) driven"
    }

    // MARK: Body

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    header

                    if activities.isEmpty {
                        emptyState
                    } else {
                        periodSelector
                        if periodActivities.isEmpty {
                            periodEmptyState
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            heroCard.cardAppear()
                            insightsCard.cardAppear()
                                .transition(.opacity)
                            drivingCard.cardAppear()
                        }
                        // Fuel and vehicles: per-vehicle MPG and this month's spend (the gas log, one tap away).
                        FuelSummaryCard().cardAppear()
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
            .navigationDestination(for: String.self) { route in
                if route == "lifetime" { LifetimeStatsView() }
            }
            .onAppear { if TrackDemo.open == "lifetime", path.isEmpty { path.append("lifetime") } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stats")
                    .font(Theme.title(34))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(Theme.rounded(14, .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 8)
            if !activities.isEmpty {
                NavigationLink(value: "lifetime") {
                    HStack(spacing: 6) {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .bold))
                        Text("All time")
                            .font(Theme.rounded(13, .bold))
                    }
                    .foregroundStyle(Theme.glow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.glow.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("Lifetime stats")
                .accessibilityHint("Totals, records, streaks and milestones")
            }
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
        .accessibilityLabel("Distance driven \(Format.distance(distance))")
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
            miniStat(value: Format.duration(t.time), label: "Drive time", symbol: "clock.fill", tint: Theme.sky)
            statDivider
            miniStat(value: "\(t.count)", label: t.count == 1 ? "Drive" : "Drives", symbol: "car.fill", tint: Theme.leaf)
            statDivider
            miniStat(value: t.avgSpeed > 0 ? Format.speed(t.avgSpeed) : "—", label: "Avg speed", symbol: "speedometer", tint: Theme.gold)
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

    // MARK: Insights

    private struct Insight: Identifiable {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
        var activityID: UUID? = nil
        var id: String { title }
    }

    /// A few plain-language takeaways for the selected period (only the ones the data supports).
    private var insights: [Insight] {
        let list = periodActivities
        guard !list.isEmpty else { return [] }
        let cal = Calendar.current
        var out: [Insight] = []

        // Your usual drive.
        if list.count >= 2 {
            let avgDistance: Double = list.reduce(0.0) { $0 + $1.distanceM } / Double(list.count)
            let avgTime: Double = list.reduce(0.0) { $0 + $1.elapsedSec } / Double(list.count)
            if avgDistance > 0 {
                out.append(Insight(symbol: "car.fill", tint: Theme.gold, title: "Your usual drive",
                                   detail: "\(Format.distance(avgDistance)) in \(Format.duration(avgTime)), over \(list.count) drives"))
            }
        }

        // How many days you drove.
        let days = Set(list.map { cal.startOfDay(for: $0.start) }).count
        if let span = period.days {
            out.append(Insight(symbol: "calendar", tint: Theme.sky,
                               title: "Drove on \(days) of \(span) days",
                               detail: "\(Format.distance(list.reduce(0.0) { $0 + $1.distanceM } / Double(max(days, 1)))) on a typical driving day"))
        } else {
            out.append(Insight(symbol: "calendar", tint: Theme.sky, title: "\(days) driving \(days == 1 ? "day" : "days")",
                               detail: "Days with at least one drive, all time"))
        }

        // Busiest weekday, once there's enough to tell.
        if list.count >= 4 {
            let counts = Dictionary(grouping: list, by: { cal.component(.weekday, from: $0.start) }).mapValues(\.count)
            if let best = counts.max(by: { $0.value < $1.value }), best.value >= 2 {
                let name = cal.weekdaySymbols[(best.key - 1 + 7) % 7]
                out.append(Insight(symbol: "sun.max.fill", tint: Theme.gold, title: "\(name)s are your big day",
                                   detail: "\(best.value) of \(list.count) drives started on a \(name)"))
            }
        }

        // The longest one in this period, one tap away.
        if let longest = list.filter({ $0.distanceM > 0 }).max(by: { $0.distanceM < $1.distanceM }) {
            out.append(Insight(symbol: "trophy.fill", tint: Theme.leaf, title: "Longest: \(Format.distance(longest.distanceM))",
                               detail: "\(longest.displayTitle) · \(Format.day(longest.start))", activityID: longest.id))
        }
        return Array(out.prefix(4))
    }

    private var insightsCard: some View {
        let list = insights
        return GlassCard(padding: 6) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Insights", symbol: "sparkles")
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                ForEach(list) { (i: Insight) in
                    if i.id != list.first?.id {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            .padding(.leading, 64).padding(.trailing, 12)
                    }
                    if let id = i.activityID {
                        NavigationLink(value: id) { insightRow(i, chevron: true) }
                            .pressable()
                            .accessibilityHint("Opens that trip")
                    } else {
                        insightRow(i, chevron: false)
                    }
                }
            }
        }
    }

    private func insightRow(_ i: Insight, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: i.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(i.tint)
                .frame(width: 38, height: 38)
                .background(i.tint.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title)
                    .font(Theme.rounded(15, .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(i.detail)
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Nothing in the chosen period (but there are older trips): say so, and offer a way forward.
    private var periodEmptyState: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 64, height: 64)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text("Nothing in the \(period.caption.lowercased())")
                    .font(Theme.rounded(17, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Your older drives are under All. Drive somewhere and this fills up.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NotificationCenter.default.post(name: RoamrTabs.openTrack, object: nil)
                } label: {
                    Label("Start a drive", systemImage: "car.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
                Button {
                    withAnimation(Self.spring) { period = .all }
                } label: {
                    Text("See all time")
                        .font(Theme.rounded(15, .bold))
                        .foregroundStyle(Theme.glow)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Driving

    /// Speed and length for the period: average speed, top speed, a typical drive and the longest one.
    private var drivingCard: some View {
        let t = totals
        let longest: Activity? = periodActivities.filter { $0.distanceM > 0 }.max { $0.distanceM < $1.distanceM }
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Driving", symbol: "car.fill")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                    drivingTile(t.avgSpeed > 0 ? Format.speed(t.avgSpeed) : "—", "Avg speed", "speedometer", Theme.gold)
                    drivingTile(t.top > 0 ? Format.speed(t.top) : "—", "Top speed", "gauge.with.dots.needle.67percent", Theme.leaf)
                    drivingTile(t.avgDrive > 0 ? Format.distance(t.avgDrive) : "—", "Avg drive", "point.topleft.down.to.point.bottomright.curvepath", Theme.sky)
                    drivingTile(longest.map { Format.distance($0.distanceM) } ?? "—", "Longest", "trophy.fill", Theme.glow)
                }
            }
        }
    }

    private func drivingTile(_ value: String, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(Theme.rounded(17, .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private var chartCard: some View {
        let bars = weekBars
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Driven, last 8 weeks", symbol: "chart.bar.fill")
                    Text(Format.distanceUnit)
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.textDim)
                }
                if bars.isEmpty {
                    Text("No drives in the last 8 weeks.")
                        .font(Theme.rounded(13, .medium))
                        .foregroundStyle(Theme.textDim)
                } else {
                    weekChart(bars)
                }
            }
        }
    }

    private func weekChart(_ bars: [WeekBar]) -> some View {
        let start = firstWeek
        let end: Date = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: start) ?? Date()
        return Chart(bars) { (b: WeekBar) in
            BarMark(x: .value("Week", b.week, unit: .weekOfYear),
                    y: .value("Distance", b.value))
                .foregroundStyle(Theme.leafGradient)
                .cornerRadius(6)
                .accessibilityLabel(Text("Week of \(b.week.formatted(.dateTime.month(.wide).day()))"))
                .accessibilityValue(Text("\(b.value.formatted(.number.precision(.fractionLength(1)))) \(Format.distanceUnit)"))
        }
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

    // MARK: Records

    private var recordsSection: some View {
        let list = records
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Personal records", symbol: "trophy.fill")
                .padding(.top, 6)
            GlassCard(padding: 6) {
                if list.isEmpty {
                    Text("Records appear once you log some drives.")
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
                    .accessibilityHidden(true)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 76, height: 76)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                Text("No drives yet")
                    .font(Theme.rounded(18, .bold))
                    .foregroundStyle(.white)
                Text("Start a drive from the Track tab, or turn on drive detect in Settings, to see miles driven, drive time, speed and fuel.")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NotificationCenter.default.post(name: RoamrTabs.openTrack, object: nil)
                } label: {
                    Label("Start a drive", systemImage: "car.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }
}
