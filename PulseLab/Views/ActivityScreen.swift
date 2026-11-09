import SwiftUI
import Charts

struct ActivityScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 7

    var body: some View {
        LabScroll(kicker: "Output", title: "Activity") {
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
                SectionTag("Total calories burned")
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
                Text("Apple counts active + resting energy; WHOOP reports one total per cycle (converted from kJ).")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
            }
        }
    }

    private var steps: some View {
        let w = store.days(.watch).recent(days).filter { $0.steps != nil }
        let avg = Stats.mean(w.compactMap(\.steps))
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionTag("Steps"); Spacer(); SourceChip(source: .watch) }
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
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: p.watch.symbol).foregroundStyle(Lab.text)
                Text(p.watch.name).font(Lab.display(16, .heavy)).foregroundStyle(Lab.text)
                Spacer()
                Text(p.watch.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Lab.mono(10)).foregroundStyle(Lab.faint)
            }
            HStack {
                metric("KCAL", p.watch.kcal, p.whoop.kcal)
                metric("AVG HR", p.watch.avgHR, p.whoop.avgHR)
                metric("MAX HR", p.watch.maxHR, p.whoop.maxHR)
                VStack(spacing: 2) {
                    Text("STRAIN").font(Lab.label(8)).foregroundStyle(Lab.faint)
                    Text(p.whoop.strain.map { String(format: "%.1f", $0) } ?? "––").font(Lab.mono(14, .heavy)).foregroundStyle(Lab.whoop)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.5), Lab.whoop.opacity(0.5)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
    }

    private func metric(_ l: String, _ a: Double?, _ b: Double?) -> some View {
        VStack(spacing: 2) {
            Text(l).font(Lab.label(8)).foregroundStyle(Lab.faint)
            Text(a.map { "\(Int($0))" } ?? "––").font(Lab.mono(14, .heavy)).foregroundStyle(Lab.watch)
            Text(b.map { "\(Int($0))" } ?? "––").font(Lab.mono(14, .heavy)).foregroundStyle(Lab.whoop)
        }
        .frame(maxWidth: .infinity)
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
