import SwiftUI
import SwiftData
import Charts

/// Month-by-month driving stats: miles, hours, drives, average speed and the longest drive per
/// month, miles per week for the last 12 weeks, and lifetime totals. Opened from the History list.
@MainActor
struct MonthlyStatsView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    /// Re-renders when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false

    private struct MonthStat: Identifiable {
        let month: Date
        let distance: Double
        let seconds: Double
        let drives: Int
        let avgSpeed: Double
        let longest: Activity?
        var id: Date { month }
    }

    private struct WeekBar: Identifiable {
        let week: Date
        let value: Double
        var id: Date { week }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    // MARK: Data

    private var drives: [Activity] { activities.filter { $0.kind == .drive } }

    private var months: [MonthStat] {
        let cal = Calendar.current
        let dict: [Date: [Activity]] = Dictionary(grouping: drives) { (a: Activity) -> Date in
            cal.dateInterval(of: .month, for: a.start)?.start ?? cal.startOfDay(for: a.start)
        }
        let keys: [Date] = dict.keys.sorted(by: >)
        return keys.map { (key: Date) -> MonthStat in
            let items: [Activity] = dict[key] ?? []
            let distance: Double = items.reduce(0.0) { $0 + $1.distanceM }
            let seconds: Double = items.reduce(0.0) { $0 + $1.elapsedSec }
            let moving: Double = items.reduce(0.0) { $0 + ($1.movingSec > 0 ? $1.movingSec : $1.elapsedSec) }
            let avg: Double = moving > 0 ? distance / moving : 0
            let longest: Activity? = items.max { $0.distanceM < $1.distanceM }
            return MonthStat(month: key, distance: distance, seconds: seconds, drives: items.count, avgSpeed: avg, longest: longest)
        }
    }

    private var firstWeek: Date {
        let cal = Calendar.current
        let current = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return cal.date(byAdding: .weekOfYear, value: -11, to: current) ?? current
    }

    private var weekBars: [WeekBar] {
        let cal = Calendar.current
        let start = firstWeek
        var sums: [Date: Double] = [:]
        // Every week gets a bar, even an empty one, so the axis stays even.
        for i in 0..<12 {
            if let w = cal.date(byAdding: .weekOfYear, value: i, to: start) { sums[w] = 0 }
        }
        for a in drives where a.start >= start && a.distanceM > 0 {
            let week = cal.dateInterval(of: .weekOfYear, for: a.start)?.start ?? start
            sums[week, default: 0] += Self.userUnits(a.distanceM)
        }
        return sums.keys.sorted().map { WeekBar(week: $0, value: sums[$0] ?? 0) }
    }

    private var lifetimeDistance: Double { drives.reduce(0.0) { $0 + $1.distanceM } }
    private var lifetimeSeconds: Double { drives.reduce(0.0) { $0 + $1.elapsedSec } }
    private var lifetimeLongest: Activity? { drives.max { $0.distanceM < $1.distanceM } }

    private static func userUnits(_ meters: Double) -> Double {
        Units.metric ? meters / 1000 : meters / 1609.344
    }

    private static func hours(_ seconds: Double) -> String {
        let h = seconds / 3600
        return h < 10 ? String(format: "%.1f h", h) : "\(Int(h.rounded())) h"
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                header
                if drives.isEmpty {
                    emptyState
                } else {
                    lifetimeCard.cardAppear()
                    chartCard.cardAppear()
                    SectionHeader(title: "By month", symbol: "calendar")
                        .padding(.top, 6)
                    ForEach(months) { (m: MonthStat) in
                        monthCard(m).cardAppear()
                    }
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationTitle("Monthly")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Driving by month")
                .font(Theme.title(30))
                .foregroundStyle(.white)
            Text(drives.isEmpty ? "Your drives, month by month" : "\(drives.count) \(drives.count == 1 ? "drive" : "drives") · \(Format.distance(lifetimeDistance))")
                .font(Theme.rounded(14, .semibold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lifetime

    private var lifetimeCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Lifetime", symbol: "infinity")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.distanceValue(lifetimeDistance))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Format.distanceUnit)
                        .font(Theme.rounded(18, .bold))
                        .foregroundStyle(Theme.glow)
                }
                HStack(spacing: 0) {
                    miniStat(value: Self.hours(lifetimeSeconds), label: "Hours", symbol: "clock.fill", tint: Theme.sky)
                    divider
                    miniStat(value: "\(drives.count)", label: "Drives", symbol: "car.fill", tint: Theme.leaf)
                    divider
                    miniStat(value: lifetimeLongest.map { Format.distance($0.distanceM) } ?? "--", label: "Longest", symbol: "trophy.fill", tint: Theme.gold)
                }
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        let bars = weekBars
        let start = firstWeek
        let end: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: start) ?? Date()
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Last 12 weeks", symbol: "chart.bar.fill")
                    Text(Format.distanceUnit)
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.textDim)
                }
                Chart(bars) { (b: WeekBar) in
                    BarMark(x: .value("Week", b.week, unit: .weekOfYear),
                            y: .value("Distance", b.value))
                        .foregroundStyle(Theme.leafGradient)
                        .cornerRadius(6)
                }
                .chartXScale(domain: start...end)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
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
                .environment(\.colorScheme, .dark)
                .frame(height: 180)
            }
        }
    }

    // MARK: Month cards

    private func monthCard(_ m: MonthStat) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.monthFormatter.string(from: m.month))
                        .font(Theme.rounded(17, .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(Format.distance(m.distance))
                        .font(Theme.rounded(17, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.glow)
                }
                HStack(spacing: 0) {
                    miniStat(value: Self.hours(m.seconds), label: "Hours", symbol: "clock.fill", tint: Theme.sky)
                    divider
                    miniStat(value: "\(m.drives)", label: m.drives == 1 ? "Drive" : "Drives", symbol: "car.fill", tint: Theme.leaf)
                    divider
                    miniStat(value: Format.speed(m.avgSpeed), label: "Avg", symbol: "speedometer", tint: Theme.gold)
                }
                if let longest = m.longest {
                    NavigationLink(value: longest.id) {
                        HStack(spacing: 10) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.gold)
                            Text("Longest: \(Format.distance(longest.distanceM)) · \(Format.day(longest.start))")
                                .font(Theme.rounded(13, .semibold))
                                .foregroundStyle(Theme.textDim)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textDim)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Pieces

    private var divider: some View {
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
                .font(Theme.rounded(17, .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 76, height: 76)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                Text("No drives yet")
                    .font(Theme.rounded(18, .bold))
                    .foregroundStyle(.white)
                Text("Record a drive from the Track tab to see monthly totals here.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }
}
