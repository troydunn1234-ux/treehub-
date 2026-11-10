import SwiftUI
import Charts

struct ActivityScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 7

    var body: some View {
        LabScroll(kicker: "Output", title: "Moves") {
            todayTiles
            RangePicker(days: $days)
            energy
            steps
            workouts
        }
    }

    private var todayTiles: some View {
        let w = store.today(.watch), h = store.today(.whoop)
        let (dist, du) = Units.distance(w?.distanceKm)
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTag("Today")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                    tile("STEPS", w?.steps, "", 0, Lab.watch)
                    tile("ACTIVE", w?.activeKcal, "kcal", 0, Lab.watch)
                    tile("EXERCISE", w?.exerciseMin, "min", 0, Lab.watch)
                    tile("DISTANCE", dist, du, 1, Lab.watch)
                    tile("FLIGHTS", w?.flights, "", 0, Lab.watch)
                    tile("STRAIN", h?.strain, "/ 21", 1, Lab.whoop)
                    tile("DAYLIGHT", w?.daylightMin, "min", 0, Lab.watch)
                    tile("STAND", w?.standMin.map { $0 / 60 }, "h", 1, Lab.watch)
                    tile("MINDFUL", w?.mindfulMin, "min", 0, Lab.watch)
                }
            }
        }
    }

    private func tile(_ l: String, _ v: Double?, _ u: String, _ d: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(Lab.label(9)).foregroundStyle(Lab.dim)
            CountUp(value: v, decimals: d, size: 20, color: c)
            Text(u.isEmpty ? " " : u).font(Lab.label(8)).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var energy: some View {
        let w = store.days(.watch).recent(days), h = store.days(.whoop).recent(days)
        return LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTag("Total calories burned")
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.watch)
                }
                if w.allSatisfy({ $0.totalKcal == nil }) && h.allSatisfy({ $0.totalKcal == nil }) {
                    EmptyNote(text: "No calorie data in this range.")
                } else {
                Chart {
                    ForEach(w.filter { $0.totalKcal != nil }) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.totalKcal ?? 0), width: .ratio(0.38))
                            .position(by: .value("Source", "Watch"))
                            .foregroundStyle(Lab.watch.gradient)
                            .cornerRadius(3)
                    }
                    ForEach(h.filter { $0.totalKcal != nil }) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.totalKcal ?? 0), width: .ratio(0.38))
                            .position(by: .value("Source", "WHOOP"))
                            .foregroundStyle(Lab.whoop.gradient)
                            .cornerRadius(3)
                    }
                }
                .chartXAxis { LabAxis.xDays }
                .chartYAxis { LabAxis.y }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily calories over \(days) days. Apple Watch averages \(avgText(w)), WHOOP averages \(avgText(h)).")
                }
                Text("Apple counts active + resting energy; WHOOP reports one total per cycle (converted from kJ).")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.detail = .calories }
        .accessibilityAddTraits(.isButton)
    }

    private func avgText(_ d: [DayStat]) -> String {
        Stats.mean(d.compactMap(\.totalKcal)).map { "\(Int($0.rounded())) kcal" } ?? "no data"
    }

    private var steps: some View {
        let w = store.days(.watch).recent(days).filter { $0.steps != nil }
        let avg = Stats.mean(w.compactMap(\.steps))
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionTag("Steps"); Spacer(); SourceChip(source: .watch) }
                if w.isEmpty {
                    EmptyNote(text: "No steps in this range. WHOOP doesn't count steps, so this is Watch/iPhone only.")
                } else {
                Chart {
                    ForEach(w) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Steps", d.steps ?? 0))
                            .foregroundStyle(LinearGradient(colors: [Lab.watch, Lab.violet], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(3)
                    }
                    if let avg {
                        RuleMark(y: .value("Avg", avg)).foregroundStyle(Lab.text.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("AVG \(Int(avg).formatted())").font(Lab.label(8)).foregroundStyle(Lab.dim)
                            }
                    }
                }
                .chartXAxis { LabAxis.xDays }
                .chartYAxis { LabAxis.y }
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Steps over \(days) days, average \(avg.map { Int($0).formatted() } ?? "unknown") a day.")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.detail = .steps }
        .accessibilityAddTraits(.isButton)
    }

    private var workouts: some View {
        let cut = Date().dayStart.adding(days: -(days - 1))
        let m = Compare.matchWorkouts(store.workouts.filter { $0.start >= cut })
        return LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTag("Workouts · \(m.pairs.count) matched")
                if m.pairs.isEmpty && m.watchOnly.isEmpty && m.whoopOnly.isEmpty {
                    EmptyNote(text: "No workouts in this range.")
                }
                ForEach(m.pairs) { p in pairRow(p) }
                ForEach(m.watchOnly) { w in singleRow(w) }
                ForEach(m.whoopOnly) { w in singleRow(w) }
            }
        }
    }

    private func pairRow(_ p: Compare.WorkoutPair) -> some View {
        VStack(alignment: .leading, spacing: Lab.S.s) {
            HStack {
                Image(systemName: p.watch.symbol).foregroundStyle(Lab.text)
                Text(p.watch.name).font(Lab.title(16)).foregroundStyle(Lab.text)
                Spacer()
                Text(p.watch.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Lab.mono(10)).foregroundStyle(Lab.faint)
            }
            HStack(alignment: .top, spacing: Lab.S.s) {
                pairColumn(p.watch, .watch)
                VStack(spacing: Lab.S.xs) {
                    deltaChip("KCAL", p.watch.kcal, p.whoop.kcal, decimals: 0)
                    deltaChip("AVG", p.watch.avgHR, p.whoop.avgHR, decimals: 0)
                    deltaChip("MAX", p.watch.maxHR, p.whoop.maxHR, decimals: 0)
                }
                .frame(width: 66)
                pairColumn(p.whoop, .whoop)
            }
        }
        .padding(Lab.S.m - 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.5), Lab.whoop.opacity(0.5)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func pairColumn(_ w: WorkoutRec, _ s: Source) -> some View {
        VStack(alignment: s == .watch ? .leading : .trailing, spacing: 3) {
            SourceChip(source: s)
            stat("KCAL", w.kcal, s)
            stat("AVG HR", w.avgHR, s)
            stat("MAX HR", w.maxHR, s)
            if s == .whoop, let st = w.strain { stat("STRAIN", st, s, decimals: 1) }
            else { stat("MIN", w.minutes, s) }
        }
        .frame(maxWidth: .infinity, alignment: s == .watch ? .leading : .trailing)
    }

    private func stat(_ l: String, _ v: Double?, _ s: Source, decimals: Int = 0) -> some View {
        HStack(spacing: 5) {
            if s == .whoop { Text(l).font(Lab.label(8)).foregroundStyle(Lab.faint) }
            Text(v.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—").font(Lab.mono(14, .heavy)).foregroundStyle(v == nil ? Lab.faint : Lab.color(s))
            if s == .watch { Text(l).font(Lab.label(8)).foregroundStyle(Lab.faint) }
        }
    }

    /// Watch − WHOOP, tinted toward whoever read higher.
    private func deltaChip(_ l: String, _ a: Double?, _ b: Double?, decimals: Int) -> some View {
        VStack(spacing: 0) {
            if let a, let b {
                let d = a - b
                Text((d >= 0 ? "+" : "−") + abs(d).formatted(.number.precision(.fractionLength(decimals))))
                    .font(Lab.mono(11, .heavy)).foregroundStyle(abs(d) < 0.5 ? Lab.dim : d > 0 ? Lab.watch : Lab.whoop)
            } else {
                Text("—").font(Lab.mono(11, .heavy)).foregroundStyle(Lab.faint)
            }
            Text(l).font(Lab.label(7)).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func singleRow(_ w: WorkoutRec) -> some View {
        HStack(spacing: 10) {
            Image(systemName: w.symbol).foregroundStyle(Lab.color(w.source)).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(w.name).font(Lab.display(15, .bold)).foregroundStyle(Lab.text)
                Text("\(Int(w.minutes)) min · \(w.kcal.map { "\(Int($0)) kcal" } ?? "–")").font(Lab.mono(10)).foregroundStyle(Lab.faint)
            }
            Spacer()
            SourceChip(source: w.source)
        }
        .padding(.vertical, 4)
    }
}
