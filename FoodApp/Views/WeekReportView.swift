import SwiftUI
import SwiftData

/// The last 7 days at a glance: calories and macros per day against your targets, averages,
/// best and worst day, your logging streak and how well you kept up with your supplements.
struct WeekReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [FoodEntry]
    @Query private var supps: [Supplement]
    @Query private var doses: [SuppDose]
    @Query private var logs: [DayLog]
    @AppStorage("goal") private var goal: Double = 2200
    @AppStorage("proteinGoal") private var proteinGoal: Double = 150

    private struct DayStat: Identifiable {
        let day: String
        let cal: Double, protein: Double, carbs: Double, fat: Double
        let logged: Bool
        var id: String { day }
        var short: String { Day.date(day).formatted(.dateTime.weekday(.abbreviated)) }
    }

    /// Oldest first, ending today.
    private var week: [DayStat] {
        let today = Day.key(Date())
        return (0..<7).reversed().map { back in
            let k = Day.shift(today, by: -back)
            let es = all.filter { $0.day == k }
            func t(_ kp: KeyPath<FoodEntry, Double>) -> Double { es.reduce(0) { $0 + $1[keyPath: kp] * $1.servings } }
            return DayStat(day: k, cal: t(\.cal), protein: t(\.protein), carbs: t(\.carbs), fat: t(\.fat), logged: !es.isEmpty)
        }
    }

    private var loggedDays: [DayStat] { week.filter(\.logged) }
    private func avg(_ kp: KeyPath<DayStat, Double>) -> Double {
        loggedDays.isEmpty ? 0 : loggedDays.reduce(0) { $0 + $1[keyPath: kp] } / Double(loggedDays.count)
    }
    /// Closest to the calorie goal is "best"; furthest is "worst".
    private var best: DayStat? { loggedDays.min { abs($0.cal - goal) < abs($1.cal - goal) } }
    private var worst: DayStat? { loggedDays.count > 1 ? loggedDays.max { abs($0.cal - goal) < abs($1.cal - goal) } : nil }

    private var streak: Int {
        let days = Set(all.map(\.day))
        var k = Day.key(Date())
        if !days.contains(k) { k = Day.shift(k, by: -1) }
        var n = 0
        while days.contains(k) { n += 1; k = Day.shift(k, by: -1) }
        return n
    }

    /// Doses taken ÷ doses expected (every supplement, every day of the week it existed).
    private var adherence: Int? {
        guard !supps.isEmpty else { return nil }
        let today = Day.key(Date())
        var expected = 0, taken = 0
        let ids = Set(supps.map(\.id))
        for back in 0..<7 {
            let k = Day.shift(today, by: -back)
            let d = Day.date(k)
            let active = supps.filter { Calendar.current.startOfDay(for: $0.createdAt) <= d }
            expected += active.count
            taken += doses.filter { $0.day == k && ids.contains($0.suppID) }.count
        }
        guard expected > 0 else { return nil }
        return Int((Double(min(taken, expected)) / Double(expected) * 100).rounded())
    }

    private var carbsTarget: Double { goal * 0.45 / 4 }
    private var fatTarget: Double { goal * 0.30 / 9 }
    private var waterWeek: Int { let from = Day.shift(Day.key(Date()), by: -6); return logs.filter { $0.day >= from }.reduce(0) { $0 + $1.water } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        stat("\(loggedDays.count)/7", "days logged", Ember.gold)
                        stat("\(streak)", "day streak", Ember.orange)
                        if let a = adherence { stat("\(a)%", "supps taken", Ember.protein) } else { stat("\(waterWeek)", "glasses water", Ember.protein) }
                    }

                    BarsCard(title: "Calories", unit: "cal", target: goal, color: Ember.orange,
                             values: week.map { ($0.short, $0.cal, $0.logged) }, average: avg(\.cal))
                    BarsCard(title: "Protein", unit: "g", target: proteinGoal, color: Ember.protein,
                             values: week.map { ($0.short, $0.protein, $0.logged) }, average: avg(\.protein))
                    BarsCard(title: "Carbs", unit: "g", target: carbsTarget, color: Ember.carbs,
                             values: week.map { ($0.short, $0.carbs, $0.logged) }, average: avg(\.carbs), targetNote: "≈45% of calories")
                    BarsCard(title: "Fat", unit: "g", target: fatTarget, color: Ember.fat,
                             values: week.map { ($0.short, $0.fat, $0.logged) }, average: avg(\.fat), targetNote: "≈30% of calories")

                    if let best {
                        VStack(alignment: .leading, spacing: 10) {
                            dayLine("Best day", best, Ember.gold, symbol: "star.fill")
                            if let worst, worst.day != best.day { dayLine("Furthest from goal", worst, Ember.pink, symbol: "exclamationmark.triangle.fill") }
                        }
                        .padding(16)
                        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
                    }

                    if adherence != nil {
                        HStack {
                            Label("Water this week", systemImage: "drop.fill").font(Ember.font(15, .bold)).foregroundStyle(Ember.cream)
                            Spacer()
                            Text("\(waterWeek) glasses · \(Double(waterWeek) * DayLog.glassML / 1000, specifier: "%.1f") L")
                                .font(Ember.font(14, .bold)).foregroundStyle(Ember.dim)
                        }
                        .padding(16)
                        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
                    }

                    if loggedDays.isEmpty {
                        Text("Log a few days and your week shows up here.")
                            .font(Ember.font(14, .medium)).foregroundStyle(Ember.dim).frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(EmberBackground())
            .navigationTitle("This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Ember.font(16, .bold)).foregroundStyle(Ember.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(Ember.font(22, .heavy)).foregroundStyle(Ember.cream)
            Text(label.uppercased()).font(Ember.font(9, .heavy)).tracking(1).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }

    private func dayLine(_ title: String, _ d: DayStat, _ color: Color, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Ember.font(12, .heavy)).tracking(0.5).foregroundStyle(Ember.dim)
                Text(Day.title(d.day)).font(Ember.font(16, .heavy)).foregroundStyle(Ember.cream)
            }
            Spacer()
            Text("\(Int(d.cal)) cal · \(Int(d.protein))g P").font(Ember.font(14, .bold)).foregroundStyle(Ember.cream)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven bars against a target line, with the week's average underneath.
struct BarsCard: View {
    let title: String
    let unit: String
    let target: Double
    let color: Color
    /// (weekday, value, logged)
    let values: [(String, Double, Bool)]
    let average: Double
    var targetNote: String? = nil

    private var top: Double { max(target * 1.25, values.map(\.1).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Ember.font(16, .heavy)).foregroundStyle(Ember.cream)
                Spacer()
                Text("avg \(Int(average.rounded()))\(unit) · goal \(Int(target.rounded()))\(unit)")
                    .font(Ember.font(12, .bold)).foregroundStyle(Ember.dim)
            }
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .bottom) {
                    // Target line.
                    Rectangle().fill(color.opacity(0.5)).frame(height: 1)
                        .offset(y: -(16 + (h - 16) * CGFloat(min(1, target / top))))
                        .accessibilityHidden(true)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                            let frac = CGFloat(min(1, v.1 / top))
                            let over = v.1 > target && title == "Calories"
                            VStack(spacing: 4) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(v.2 ? (over ? Ember.pink : color) : Color.white.opacity(0.08))
                                    .frame(height: max(4, (h - 16) * frac))
                                Text(v.0.prefix(2)).font(Ember.font(10, .heavy)).foregroundStyle(Ember.dim)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(v.0): \(v.2 ? "\(Int(v.1))\(unit)" : "not logged")")
                        }
                    }
                }
            }
            .frame(height: 120)
            if let targetNote {
                Text("Target \(targetNote)").font(Ember.font(11, .medium)).foregroundStyle(Ember.dim)
            }
        }
        .padding(16)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
    }
}
