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
        // WHOOP's cycle usually hasn't closed this early; show the latest one and say so.
        let lastWhoop = store.days(.whoop).last { $0.strain != nil }
        let strain = h?.strain ?? lastWhoop?.strain
        let strainUnit = h?.strain != nil ? "/ 21" : (lastWhoop != nil ? "/ 21 · last cycle" : "/ 21")
        let has = w != nil
        let z: (Double?) -> Double? = { $0 ?? (has ? 0 : nil) }
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTag("Today")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                    tile("STEPS", w?.steps, stepsToday, 0, Lab.watch)
                    tile("ACTIVE", w?.activeKcal, "kcal", 0, Lab.watch)
                    tile("EXERCISE", w?.exerciseMin, "min", 0, Lab.watch)
                    tile("DISTANCE", dist, du, 1, Lab.watch)
                    tile("FLIGHTS", z(w?.flights), "", 0, Lab.watch)
                    tile("STRAIN", strain, strainUnit, 1, Lab.whoop)
                    tile("DAYLIGHT", z(w?.daylightMin), "min", 0, Lab.watch)
                    tile("STAND", z(w?.standMin.map { $0 / 60 }), "h", 1, Lab.watch)
                    tile("MINDFUL", z(w?.mindfulMin), "min", 0, Lab.watch)
                }
            }
        }
    }

    /// "Watch 412 · iPhone 204" under today's steps.
    private var stepsToday: String {
        let m = store.stepsByDevice[Date().dayStart] ?? [:]
        guard m.count > 1 else { return "" }
        return m.sorted { $0.value > $1.value }.map { "\($0.key.replacingOccurrences(of: "Apple ", with: "")) \(Int($0.value).formatted())" }.joined(separator: " · ")
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
                            .opacity(d.day.isToday ? 0.4 : 1)
                            .cornerRadius(3)
                    }
                    ForEach(h.filter { $0.totalKcal != nil }) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.totalKcal ?? 0), width: .ratio(0.38))
                            .position(by: .value("Source", "WHOOP"))
                            .foregroundStyle(Lab.whoop.gradient)
                            .opacity(d.day >= Date().dayStart.adding(days: -1) && d.day == (h.last?.day ?? .distantPast) ? 0.4 : 1)
                            .cornerRadius(3)
                    }
                }
                .chartXAxis { LabAxis.xDays }
                .chartYAxis { LabAxis.y }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily calories over \(days) days. Apple Watch averages \(avgText(w)), WHOOP averages \(avgText(h)).")
                }
                Text("Apple counts active + resting energy; WHOOP reports one total per cycle (converted from kJ). Faded bars are still counting — today on Apple, the open cycle on WHOOP — so don't compare those yet.")
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
        let avg = Stats.mean(w.filter { !$0.day.isToday }.compactMap(\.steps))
        let cut = Date().dayStart.adding(days: -(days - 1))
        let byDevice = store.stepsByDevice.filter { $0.key >= cut }
        let devices = Array(Set(byDevice.values.flatMap(\.keys))).sorted { a, b in
            if a == "iPhone" { return false }; if b == "iPhone" { return true }; return a < b
        }
        let palette: [Color] = [Lab.watch, Lab.violet, Lab.good, Lab.warn]
        let colorOf: (String) -> Color = { $0 == "iPhone" ? Lab.dim : palette[(devices.firstIndex(of: $0) ?? 0) % palette.count] }
        let rows: [(day: Date, device: String, v: Double)] = byDevice.flatMap { day, m in m.map { (day, $0.key, $0.value) } }.sorted { $0.day < $1.day }
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionTag("Steps · by device"); Spacer(); SourceChip(source: .watch) }
                if w.isEmpty && rows.isEmpty {
                    EmptyNote(text: "No steps in this range. WHOOP doesn't count steps, so this is Watch/iPhone only.")
                } else {
                Chart {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        BarMark(x: .value("Day", r.day, unit: .day), y: .value("Steps", r.v))
                            .foregroundStyle(by: .value("Device", r.device))
                            .opacity(r.day.isToday ? 0.45 : 1)
                            .cornerRadius(3)
                    }
                    ForEach(w) { d in
                        // Health's de-duplicated total — what the Health app shows.
                        PointMark(x: .value("Day", d.day, unit: .day), y: .value("Total", d.steps ?? 0))
                            .foregroundStyle(Lab.text).symbol(.diamond).symbolSize(28)
                    }
                    if let avg {
                        RuleMark(y: .value("Avg", avg)).foregroundStyle(Lab.text.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("AVG \(Int(avg).formatted())").font(Lab.label(8)).foregroundStyle(Lab.dim)
                            }
                    }
                }
                .chartForegroundStyleScale(domain: devices, range: devices.map(colorOf))
                .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                .chartXAxis { LabAxis.xDays }
                .chartYAxis { LabAxis.y }
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Steps by device over \(days) days, average \(avg.map { Int($0).formatted() } ?? "unknown") a day.")
                Text("Each bar is one device's own count; the diamond is Health's de-duplicated total (what the Health app shows). Today is faded: it's still counting.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
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
