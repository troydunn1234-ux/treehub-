import SwiftUI
import SwiftData
import Charts

@MainActor
struct StatsView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @State private var period: Period = .month

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
        let value: String
        let activity: Activity
        var id: String { label }
    }

    // MARK: Data

    private var periodActivities: [Activity] {
        guard let days = period.days else { return activities }
        let cutoff: Date = Date().addingTimeInterval(-Double(days) * 86_400)
        return activities.filter { $0.start >= cutoff }
    }

    private var kindTotals: [KindTotal] {
        let list = periodActivities
        return ActivityKind.allCases.compactMap { (k: ActivityKind) -> KindTotal? in
            let items = list.filter { $0.kind == k }
            guard !items.isEmpty else { return nil }
            return KindTotal(kind: k, count: items.count, distance: items.reduce(0.0) { $0 + $1.distanceM })
        }
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
        func add(_ label: String, _ symbol: String, _ a: Activity?, _ value: (Activity) -> String) {
            if let a { out.append(Record(label: label, symbol: symbol, value: value(a), activity: a)) }
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

        add("Longest run", "figure.run", longest(.run)) { Format.distance($0.distanceM) }
        add("Fastest run pace", "stopwatch.fill", fastest) {
            Format.paceOrSpeed(distance: $0.distanceM, seconds: runSeconds($0), kind: .run)
        }
        add("Longest hike", "figure.hiking", longest(.hike)) { Format.distance($0.distanceM) }
        add("Biggest climb", "mountain.2.fill", climb) { Format.elevation($0.elevGainM) }
        add("Longest ride", "bicycle", longest(.bike)) { Format.distance($0.distanceM) }
        add("Longest drive", "car.fill", longest(.drive)) { Format.distance($0.distanceM) }
        add("Top speed", "gauge.with.dots.needle.67percent", top) { Format.speed($0.maxSpeed) }
        return out
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Stats").font(Theme.title(36)).foregroundStyle(.white).padding(.top, 8)

                    if activities.isEmpty {
                        emptyState
                    } else {
                        Picker("Period", selection: $period) {
                            ForEach(Period.allCases) { (p: Period) in Text(p.rawValue).tag(p) }
                        }
                        .pickerStyle(.segmented)

                        totalsCard
                        byTypeSection
                        chartCard
                        recordsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
        }
    }

    // MARK: Sections

    private var totalsCard: some View {
        let list = periodActivities
        let distance: Double = list.reduce(0.0) { $0 + $1.distanceM }
        let time: Double = list.reduce(0.0) { $0 + $1.elapsedSec }
        let climb: Double = list.filter { $0.kind.isOnFoot }.reduce(0.0) { $0 + $1.elevGainM }
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return GlassCard {
            LazyVGrid(columns: columns, spacing: 10) {
                StatTile(value: Format.distance(distance), label: "Distance", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", tint: Theme.glow)
                StatTile(value: Format.duration(time), label: "Time", symbol: "clock.fill", tint: Theme.sky)
                StatTile(value: "\(list.count)", label: list.count == 1 ? "Trip" : "Trips", symbol: "flag.checkered", tint: Theme.leaf)
                StatTile(value: Format.elevation(climb), label: "Climb (on foot)", symbol: "mountain.2.fill", tint: Theme.gold)
            }
        }
    }

    private var byTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By type", symbol: "square.stack.3d.up.fill")
            if kindTotals.isEmpty {
                Text("No trips in this period.").font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
            } else {
                GlassCard(padding: 12) {
                    VStack(spacing: 10) {
                        ForEach(kindTotals) { (t: KindTotal) in
                            HStack(spacing: 12) {
                                Image(systemName: t.kind.symbol)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Self.color(for: t.kind))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.08), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.kind.title).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                                    Text("\(t.count) \(t.count == 1 ? "trip" : "trips")")
                                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                                Text(Format.distance(t.distance)).font(Theme.rounded(15, .bold)).foregroundStyle(Theme.glow)
                            }
                        }
                    }
                }
            }
        }
    }

    private var chartCard: some View {
        let bars = weekBars
        let kinds: [ActivityKind] = ActivityKind.allCases.filter { k in bars.contains { $0.kind == k } }
        let domain: [String] = kinds.map { $0.title }
        let range: [Color] = kinds.map { Self.color(for: $0) }
        let start = firstWeek
        let end: Date = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: start) ?? Date()
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Last 8 weeks", symbol: "chart.bar.fill")
                if bars.isEmpty {
                    Text("No distance logged in the last 8 weeks.")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                } else {
                    Chart(bars) { (b: WeekBar) in
                        BarMark(x: .value("Week", b.week, unit: .weekOfYear),
                                y: .value("Distance", b.value))
                            .foregroundStyle(by: .value("Type", b.kind.title))
                            .cornerRadius(4)
                    }
                    .chartForegroundStyleScale(domain: domain, range: range)
                    .chartXScale(domain: start...end)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.textDim)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel().foregroundStyle(Theme.textDim)
                        }
                    }
                    .chartYAxisLabel(Format.distanceUnit)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .environment(\.colorScheme, .dark)
                    .frame(height: 200)
                }
            }
        }
    }

    private var recordsCard: some View {
        let list = records
        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Personal records", symbol: "trophy.fill").padding(.horizontal, 4)
                if list.isEmpty {
                    Text("Records appear once you log some trips.").font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                }
                ForEach(list) { (r: Record) in
                    NavigationLink(value: r.activity.id) {
                        HStack(spacing: 12) {
                            Image(systemName: r.symbol)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.gold)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                                Text(Format.day(r.activity.start)).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Text(r.value).font(Theme.rounded(15, .bold)).foregroundStyle(Theme.glow)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                Text("No stats yet").font(Theme.rounded(18, .bold)).foregroundStyle(.white)
                Text("Record a trip from the Track tab to see totals, trends and records.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }
}
