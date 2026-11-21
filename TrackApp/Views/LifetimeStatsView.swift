import SwiftUI
import SwiftData

/// Every drive you've ever recorded: totals, records, best month, streaks, this year against last year,
/// and fun distance milestones. Opened from Stats. (Walks / rides from before Roamr went drive-only are
/// left out of these totals and noted at the bottom; their data isn't touched.)
@MainActor
struct LifetimeStatsView: View {
    @Query(sort: \Activity.start, order: .reverse) private var allTrips: [Activity]
    private var activities: [Activity] { allTrips.filter { $0.kind == .drive } }
    private var olderTrips: [Activity] { allTrips.filter { $0.kind != .drive } }
    /// Re-renders when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false

    // MARK: Data

    private struct Milestone: Identifiable {
        let name: String
        let symbol: String
        let meters: Double
        var id: String { name }
    }

    /// Distance milestones (meters).
    private static let distanceMilestones: [Milestone] = [
        Milestone(name: "Across the Golden Gate Bridge", symbol: "road.lanes", meters: 2_737),
        Milestone(name: "San Francisco to San Jose", symbol: "car.fill", meters: 77_000),
        Milestone(name: "Around Lake Tahoe", symbol: "water.waves", meters: 116_000),
        Milestone(name: "San Francisco to Los Angeles", symbol: "car.fill", meters: 615_000),
        Milestone(name: "The length of California", symbol: "map.fill", meters: 1_240_000),
        Milestone(name: "All of Route 66", symbol: "signpost.right.fill", meters: 3_940_000),
        Milestone(name: "Coast to coast across the US", symbol: "flag.fill", meters: 4_500_000),
        Milestone(name: "Around the Earth", symbol: "globe.americas.fill", meters: 40_075_000),
        Milestone(name: "To the Moon", symbol: "moon.stars.fill", meters: 384_400_000),
    ]

    private static func seconds(_ a: Activity) -> Double { a.movingSec > 0 ? a.movingSec : a.elapsedSec }

    private var totalDistance: Double { activities.reduce(0) { $0 + $1.distanceM } }
    private var totalSeconds: Double { activities.reduce(0) { $0 + Self.seconds($1) } }
    private var avgSpeed: Double { totalSeconds > 0 ? totalDistance / totalSeconds : 0 }

    private var fastest: Activity? { activities.filter { $0.maxSpeed > 0 && $0.maxSpeed < 95 }.max { $0.maxSpeed < $1.maxSpeed } }
    private var longest: Activity? { activities.max { $0.distanceM < $1.distanceM } }
    private var longestTime: Activity? { activities.max { Self.seconds($0) < Self.seconds($1) } }

    /// Month with the most distance: (month start, distance, trips).
    private var bestMonth: (month: Date, distance: Double, trips: Int)? {
        let cal = Calendar.current
        let groups = Dictionary(grouping: activities) { cal.dateInterval(of: .month, for: $0.start)?.start ?? $0.start }
        return groups.map { (month: $0.key, distance: $0.value.reduce(0) { $0 + $1.distanceM }, trips: $0.value.count) }
            .max { $0.distance == $1.distance ? $0.trips < $1.trips : $0.distance < $1.distance }
    }

    /// Current and longest run of days in a row with at least one trip, plus total active days.
    private var streaks: (current: Int, longest: Int, days: Int) {
        let cal = Calendar.current
        let days = Set(activities.map { cal.startOfDay(for: $0.start) }).sorted()
        guard !days.isEmpty else { return (0, 0, 0) }
        var longest = 1, run = 1
        for i in 1..<max(1, days.count) {
            let gap = cal.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longest = max(longest, run)
        }
        // Current: counts back from today (or yesterday, so the streak doesn't look broken before you go out).
        let today = cal.startOfDay(for: Date())
        let set = Set(days)
        var current = 0
        var day = set.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while set.contains(day) {
            current += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return (current, longest, days.count)
    }

    private struct YearTotals { var distance = 0.0; var trips = 0; var seconds = 0.0 }

    /// This year so far, last year up to the same date, and all of last year.
    private var years: (this: YearTotals, lastToDate: YearTotals, lastFull: YearTotals, thisYear: Int) {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let sameDayLastYear = cal.date(byAdding: .year, value: -1, to: now) ?? now
        var t = YearTotals(), ltd = YearTotals(), lf = YearTotals()
        for a in activities {
            let ay = cal.component(.year, from: a.start)
            if ay == y {
                t.distance += a.distanceM; t.trips += 1; t.seconds += Self.seconds(a)
            } else if ay == y - 1 {
                lf.distance += a.distanceM; lf.trips += 1; lf.seconds += Self.seconds(a)
                if a.start <= sameDayLastYear { ltd.distance += a.distanceM; ltd.trips += 1; ltd.seconds += Self.seconds(a) }
            }
        }
        return (t, ltd, lf, y)
    }

    // MARK: Formatting

    /// Whole numbers once distances get big ("1,284 mi"), two decimals below 10.
    private static func bigDistance(_ m: Double) -> String {
        let v = Units.metric ? m / 1000 : m / 1609.344
        let unit = Format.distanceUnit
        if v >= 100 { return "\(v.formatted(.number.precision(.fractionLength(0)))) \(unit)" }
        if v >= 10 { return String(format: "%.1f %@", v, unit) }
        return Format.distance(m)
    }

    private static func hours(_ s: Double) -> String {
        let h = s / 3600
        if h >= 100 { return "\(Int(h.rounded()).formatted()) h" }
        if h >= 1 { return String(format: "%.1f h", h) }
        return "\(Int((s / 60).rounded())) min"
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                header
                if activities.isEmpty {
                    emptyState
                } else {
                    heroCard.cardAppear()
                    recordsCard.cardAppear()
                    streakCard.cardAppear()
                    yearCard.cardAppear()
                    milestonesCard(title: "Distance milestones", symbol: "map.fill",
                                   list: Self.distanceMilestones, total: totalDistance, format: Self.bigDistance)
                        .cardAppear()
                }
                if !olderTrips.isEmpty {
                    Label("Not counted: \(olderTrips.count) older \(olderTrips.count == 1 ? "walk or ride" : "walks & rides") from before Roamr went drive-only. They're still in History.",
                          systemImage: "archivebox")
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationTitle("Lifetime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All time")
                .font(Theme.title(30))
                .foregroundStyle(.white)
            Text(activities.isEmpty ? "Every drive you've ever logged"
                 : "Since \(Format.day(activities.last?.start ?? Date())) · \(activities.count) \(activities.count == 1 ? "drive" : "drives")")
                .font(Theme.rounded(14, .semibold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero

    private var heroCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Lifetime", symbol: "infinity")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.metric ? (totalDistance / 1000).formatted(.number.precision(.fractionLength(1)))
                                      : (totalDistance / 1609.344).formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(Format.distanceUnit)
                        .font(Theme.rounded(18, .bold))
                        .foregroundStyle(Theme.glow)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Self.bigDistance(totalDistance)) driven in total")
                HStack(spacing: 0) {
                    miniStat(Self.hours(totalSeconds), "Drive time", "clock.fill", Theme.sky)
                    miniStat("\(activities.count)", "Drives", "car.fill", Theme.leaf)
                    miniStat(avgSpeed > 0 ? Format.speed(avgSpeed) : "—", "Avg speed", "speedometer", Theme.gold)
                }
            }
        }
    }

    // MARK: Records

    private var recordsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Records", symbol: "trophy.fill")
                    .padding(.bottom, 4)
                if let a = fastest {
                    recordRow("Top speed", Format.speed(a.maxSpeed), "gauge.with.dots.needle.67percent", Theme.leaf, a)
                }
                if let a = longest {
                    recordRow("Longest drive", Self.bigDistance(a.distanceM), "point.topleft.down.to.point.bottomright.curvepath", Theme.gold, a)
                }
                if let a = longestTime {
                    recordRow("Longest drive time", Format.duration(Self.seconds(a)), "clock.fill", Theme.sky, a)
                }
                if let m = bestMonth {
                    HStack(spacing: 12) {
                        recordIcon("calendar", Theme.glow)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Most driven month").font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
                            Text(Self.monthFormatter.string(from: m.month)).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Self.bigDistance(m.distance)).font(Theme.rounded(16, .heavy)).foregroundStyle(.white)
                            Text("\(m.trips) \(m.trips == 1 ? "drive" : "drives")").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                        }
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func recordIcon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.16), in: Circle())
    }

    private func recordRow(_ label: String, _ value: String, _ symbol: String, _ tint: Color, _ a: Activity) -> some View {
        NavigationLink(value: a.id) {
            HStack(spacing: 12) {
                recordIcon(symbol, tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
                    Text(value).font(Theme.rounded(16, .heavy)).foregroundStyle(.white).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(a.displayTitle).font(Theme.rounded(13, .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(Format.day(a.start)).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens that trip")
    }

    // MARK: Streaks

    private var streakCard: some View {
        let s = streaks
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Streaks", symbol: "flame.fill")
                HStack(spacing: 0) {
                    miniStat("\(s.current) \(s.current == 1 ? "day" : "days")", "Current", "flame.fill", s.current > 0 ? Theme.leaf : Theme.textDim)
                    miniStat("\(s.longest) \(s.longest == 1 ? "day" : "days")", "Best", "crown.fill", Theme.gold)
                    miniStat("\(s.days)", "Driving days", "calendar", Theme.sky)
                }
                Text(s.current > 0 ? "Days in a row with at least one drive." : "Log a drive today to start a new streak.")
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: This year vs last

    private var yearCard: some View {
        let y = years
        let maxD = max(y.this.distance, y.lastToDate.distance, 1)
        let change: Double? = y.lastToDate.distance > 0 ? (y.this.distance - y.lastToDate.distance) / y.lastToDate.distance * 100 : nil
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "\(String(y.thisYear)) vs \(String(y.thisYear - 1))", symbol: "arrow.left.arrow.right")
                    if let change {
                        let up = change >= 0
                        Label("\(Int(abs(change).rounded()))%", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                            .font(Theme.rounded(12, .heavy))
                            .foregroundStyle(up ? Theme.leaf : Theme.sky)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((up ? Theme.leaf : Theme.sky).opacity(0.15), in: Capsule())
                            .accessibilityLabel("\(Int(abs(change).rounded())) percent \(up ? "more" : "less") than last year so far")
                    }
                }
                yearBar("This year", y.this, fraction: y.this.distance / maxD, tint: Theme.leafGradient)
                yearBar("Last year, same date", y.lastToDate, fraction: y.lastToDate.distance / maxD,
                        tint: LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                if y.lastFull.trips > 0 {
                    Text("All of \(String(y.thisYear - 1)): \(Self.bigDistance(y.lastFull.distance)) · \(y.lastFull.trips) \(y.lastFull.trips == 1 ? "drive" : "drives") · \(Self.hours(y.lastFull.seconds))")
                        .font(Theme.rounded(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                } else {
                    Text("Nothing from last year yet. Next year you'll see how you compare.")
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func yearBar(_ label: String, _ t: YearTotals, fraction: Double, tint: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.rounded(13, .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(Self.bigDistance(t.distance)) · \(t.trips) \(t.trips == 1 ? "drive" : "drives")")
                    .font(Theme.rounded(13, .heavy)).foregroundStyle(.white).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(tint).frame(width: max(8, g.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Self.bigDistance(t.distance)), \(t.trips) \(t.trips == 1 ? "drive" : "drives"), \(Self.hours(t.seconds))")
    }

    // MARK: Milestones

    private func milestonesCard(title: String, symbol: String, list: [Milestone], total: Double,
                                format: @escaping (Double) -> String) -> some View {
        let reached = list.filter { total >= $0.meters }
        let next = list.first { total < $0.meters }
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: title, symbol: symbol)
                    Text("\(reached.count)/\(list.count)")
                        .font(Theme.rounded(12, .heavy)).foregroundStyle(Theme.glow)
                }
                if let next {
                    let fraction = total / next.meters
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: next.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.forestDeep)
                                .frame(width: 34, height: 34)
                                .background(Theme.goldGradient, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Next up").font(Theme.rounded(11, .bold)).foregroundStyle(Theme.textDim)
                                Text(next.name).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                            }
                            Spacer()
                            Text(fraction >= 0.01 ? "\(Int((fraction * 100).rounded(.down)))%" : "<1%")
                                .font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.gold).monospacedDigit()
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.07))
                                Capsule().fill(Theme.goldGradient).frame(width: max(8, g.size.width * CGFloat(min(1, fraction))))
                            }
                        }
                        .frame(height: 8)
                        Text("\(format(next.meters - total)) to go")
                            .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Next milestone: \(next.name). \(Int((fraction * 100).rounded(.down))) percent there, \(format(next.meters - total)) to go")
                } else {
                    Label("Every milestone reached. Legend.", systemImage: "sparkles")
                        .font(Theme.rounded(15, .bold)).foregroundStyle(Theme.gold)
                }
                ForEach(reached.reversed()) { m in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.leaf)
                        Text(m.name).font(Theme.rounded(14, .semibold)).foregroundStyle(.white)
                        Spacer()
                        let times = total / m.meters
                        if times >= 2 {
                            Text("\(Int(times.rounded(.down)))×").font(Theme.rounded(13, .heavy)).foregroundStyle(Theme.glow)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Pieces

    private func miniStat(_ value: String, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.textDim).lineLimit(1)
            }
            Text(value)
                .font(Theme.rounded(18, .bold)).monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "infinity")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 76, height: 76)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                Text("Your all-time driving starts here")
                    .font(Theme.rounded(18, .bold)).foregroundStyle(.white)
                Text("Start a drive from the Track tab, or let drive detect catch it. Totals, records, streaks and milestones build up as you go.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
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
