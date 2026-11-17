import SwiftUI
import Charts

struct ActivityScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var days = 7
    @State private var energyDay: Date?
    @State private var stepsDay: Date?

    var body: some View {
        LabScroll(kicker: "Output", title: "Moves") {
            todayTiles
            RangePicker(days: $days)
            energy
            steps
            workouts
        }
    }

    // MARK: Today

    private var todayTiles: some View {
        let w = store.today(.watch), h = store.today(.whoop)
        let (dist, du) = Units.distance(w?.distanceKm)
        // WHOOP's cycle usually hasn't closed this early; show the latest one and say so.
        let lastWhoop = store.days(.whoop).last { $0.strain != nil }
        let strain = h?.strain ?? lastWhoop?.strain
        let strainNote = h?.strain == nil && lastWhoop != nil ? String(localized: "/ 21 · last cycle") : "/ 21"
        let has = w != nil
        let z: (Double?) -> Double? = { $0 ?? (has ? 0 : nil) }
        let cols = typeSize.isAccessibilitySize ? 2 : 3
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader("Today", subtitle: has ? nil : "Nothing from your Watch yet today. Wear it a while, then pull to refresh.")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s, alignment: .topLeading), count: cols),
                          alignment: .leading, spacing: Lab.S.m) {
                    tile("Steps", w?.steps, String(localized: "steps"), 0, .watch, note: stepsToday)
                    tile("Active energy", w?.activeKcal, "kcal", 0, .watch)
                    tile("Exercise", w?.exerciseMin, "min", 0, .watch)
                    tile("Distance", dist, du, 1, .watch)
                    tile("Flights", z(w?.flights), String(localized: "floors"), 0, .watch)
                    tile("Strain", strain, strainNote, 1, .whoop)
                    tile("Daylight", z(w?.daylightMin), "min", 0, .watch)
                    tile("Stand", z(w?.standMin.map { $0 / 60 }), "h", 1, .watch)
                    tile("Mindful", z(w?.mindfulMin), "min", 0, .watch)
                }
            }
        }
    }

    /// "Watch 412 · iPhone 204" under today's steps.
    private var stepsToday: String? {
        let m = store.stepsByDevice[Date().dayStart] ?? [:]
        guard m.count > 1 else { return nil }
        return m.sorted { $0.value > $1.value }.map { "\($0.key.replacingOccurrences(of: "Apple ", with: "")) \(Int($0.value).formatted())" }.joined(separator: " · ")
    }

    /// Caption, then the number in its tracker's colour, then the unit (or why it's missing).
    private func tile(_ title: String, _ v: Double?, _ unit: String, _ d: Int, _ s: Source, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(Lab.color(s)).frame(width: 6, height: 6)
                Text(L(title)).font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            CountUp(value: v, decimals: d, size: 22, color: Lab.color(s))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(v == nil ? String(localized: "Not in yet") : (note ?? unit))
                .font(.caption2).foregroundStyle(Lab.faint)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(v.map { "\(L(title)), \(s.name): \(Lab.fmt($0, d)) \(note ?? unit)" }
                            ?? String(localized: "\(L(title)): not in yet"))
    }

    // MARK: Energy

    private var energy: some View {
        let w = store.days(.watch).recent(days), h = store.days(.whoop).recent(days)
        let wk = w.filter { $0.totalKcal != nil }, hk = h.filter { $0.totalKcal != nil }
        // The newest WHOOP cycle is still open when it's from today or yesterday.
        let openWhoop: Date? = hk.last.flatMap { $0.day >= Date().dayStart.adding(days: -1) ? $0.day : nil }
        let dayList = Array(Set((wk + hk).map(\.day))).sorted()
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader("Total calories burned") {
                    CardLink("Details") { store.detail = .calories }
                        .accessibilityHint("Opens the calories chart from 7 days to a year")
                }
                if wk.isEmpty && hk.isEmpty {
                    EmptyNote(text: "Calories from the Watch arrive through Apple Health; WHOOP's daily total arrives once WHOOP is connected.",
                              symbol: "flame", title: "No calories in this range")
                } else {
                    Chart {
                        if let sel = energyDay {
                            RuleMark(x: .value("Selected", sel, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.18))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    energyTooltip(sel, wk, hk, openWhoop)
                                }
                        }
                        ForEach(wk) { d in
                            BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.totalKcal ?? 0), width: .ratio(0.38))
                                .position(by: .value("Source", "Watch"))
                                .foregroundStyle(Lab.watch)
                                .opacity(barOpacity(d.day, faded: d.day.isToday, selected: energyDay))
                                .cornerRadius(3)
                        }
                        ForEach(hk) { d in
                            BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.totalKcal ?? 0), width: .ratio(0.38))
                                .position(by: .value("Source", "WHOOP"))
                                .foregroundStyle(Lab.whoop)
                                .opacity(barOpacity(d.day, faded: d.day == openWhoop, selected: energyDay))
                                .cornerRadius(3)
                        }
                    }
                    .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel("kcal") }
                    .scrubDays(dayList, selection: $energyDay)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 190)
                    .chartSummary(String(localized: "Daily calories over \(days) days. Apple Watch averages \(avgText(w)), WHOOP averages \(avgText(h)).") + " " + highText(wk + hk))
                    DuelLegend()
                }
                Text("Apple counts active + resting energy; WHOOP reports one total per cycle (converted from kJ). Faded bars are still counting (today on the Watch, the open cycle on WHOOP), so don't compare those yet.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func barOpacity(_ day: Date, faded: Bool, selected: Date?) -> Double {
        let base = faded ? 0.4 : 1
        guard let selected else { return base }
        return Calendar.current.isDate(day, inSameDayAs: selected) ? base : base * 0.35
    }

    private func energyTooltip(_ day: Date, _ w: [DayStat], _ h: [DayStat], _ openWhoop: Date?) -> some View {
        var lines: [LabChartTooltip.Line] = []
        if let v = w.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) })?.totalKcal {
            lines.append(.init(label: Source.watch.label, value: "\(Lab.fmt(v)) kcal", color: Lab.watch))
        }
        if let v = h.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) })?.totalKcal {
            lines.append(.init(label: Source.whoop.label, value: "\(Lab.fmt(v)) kcal", color: Lab.whoop))
        }
        let counting = day.isToday || (openWhoop.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false)
        return LabChartTooltip(title: LabChartTooltip.dayTitle(day), lines: lines,
                               note: counting ? String(localized: "Still counting") : nil)
    }

    private func avgText(_ d: [DayStat]) -> String {
        Stats.mean(d.compactMap(\.totalKcal)).map { "\(Lab.fmt($0)) kcal" } ?? String(localized: "no data")
    }

    private func highText(_ d: [DayStat]) -> String {
        guard let top = d.max(by: { ($0.totalKcal ?? 0) < ($1.totalKcal ?? 0) }), let v = top.totalKcal else { return "" }
        return String(localized: "Highest: \(Lab.fmt(v)) kcal on \(top.day.formatted(.dateTime.weekday(.wide).month().day())).")
    }

    // MARK: Steps

    /// Today's WHOOP steps (typed in by hand: WHOOP doesn't share steps); tap to add or edit.
    private var whoopStepsButton: some View {
        let v = store.whoopDays.stat(on: Date())?.steps
        return Button {
            Lab.tick()
            store.quickWhoop = .steps()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: v == nil ? "plus.circle.fill" : "pencil").font(.caption.weight(.bold))
                Text(v.map { "WHOOP \(Int($0.rounded()).formatted())" } ?? String(localized: "Add WHOOP steps"))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(Lab.whoop)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Lab.whoop.opacity(0.14)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(v == nil ? String(localized: "Add today's WHOOP steps") : String(localized: "Edit today's WHOOP steps"))
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
        let dayList = Array(Set(rows.map { $0.day } + w.map { $0.day })).sorted()
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader("Steps by device") { whoopStepsButton }
                if w.isEmpty && rows.isEmpty {
                    EmptyNote(text: "Watch and iPhone steps arrive through Apple Health. WHOOP doesn't count steps; tap Add WHOOP steps to type them in.",
                              symbol: "figure.walk", title: "No steps in this range")
                } else {
                    Chart {
                        if let sel = stepsDay {
                            RuleMark(x: .value("Selected", sel, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.18))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    stepsTooltip(sel, rows: rows, totals: w, colorOf: colorOf)
                                }
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            BarMark(x: .value("Day", r.day, unit: .day), y: .value("Steps", r.v))
                                .foregroundStyle(by: .value("Device", r.device))
                                .opacity(barOpacity(r.day, faded: r.day.isToday, selected: stepsDay))
                                .cornerRadius(3)
                        }
                        ForEach(w) { d in
                            // Health's de-duplicated total — what the Health app shows.
                            PointMark(x: .value("Day", d.day, unit: .day), y: .value("Total", d.steps ?? 0))
                                .foregroundStyle(Lab.text).symbol(.diamond).symbolSize(28)
                        }
                        if let avg {
                            RuleMark(y: .value("Average", avg)).foregroundStyle(Lab.text.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Average \(Int(avg).formatted())").font(.caption2.weight(.semibold)).foregroundStyle(Lab.dim)
                                }
                        }
                    }
                    .chartForegroundStyleScale(domain: devices, range: devices.map(colorOf))
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
                    .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel(String(localized: "steps")) }
                    .scrubDays(dayList, selection: $stepsDay)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 190)
                    .chartSummary(stepsSummary(w, avg: avg))
                }
                Text("Each bar is one device's own count; the diamond is Health's de-duplicated total (what the Health app shows). Today is faded: it's still counting.")
                    .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepsTooltip(_ day: Date, rows: [(day: Date, device: String, v: Double)], totals: [DayStat],
                              colorOf: (String) -> Color) -> some View {
        let mine = rows.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.sorted { $0.v > $1.v }
        var lines = mine.map { LabChartTooltip.Line(label: $0.device, value: Int($0.v).formatted(), color: colorOf($0.device)) }
        if let t = totals.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) })?.steps {
            lines.append(.init(label: String(localized: "Health total"), value: Int(t).formatted(), color: Lab.text))
        }
        return LabChartTooltip(title: LabChartTooltip.dayTitle(day), lines: lines,
                               note: day.isToday ? String(localized: "Still counting") : nil)
    }

    private func stepsSummary(_ w: [DayStat], avg: Double?) -> String {
        var s = String(localized: "Steps by device over \(days) days.")
        if let avg { s += " " + String(localized: "Average \(Int(avg).formatted()) a day.") }
        if let top = w.max(by: { ($0.steps ?? 0) < ($1.steps ?? 0) }), let v = top.steps {
            s += " " + String(localized: "Highest: \(Int(v).formatted()) on \(top.day.formatted(.dateTime.weekday(.wide).month().day())).")
        }
        return s
    }

    // MARK: Workouts

    private var workouts: some View {
        let cut = Date().dayStart.adding(days: -(days - 1))
        let m = Compare.matchWorkouts(store.workouts.filter { $0.start >= cut })
        let total = m.pairs.count + m.watchOnly.count + m.whoopOnly.count
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader("Workouts",
                           subtitle: total == 0 ? nil : String(localized: "\(m.pairs.count) recorded by both trackers"),
                           symbol: "figure.run", tint: Lab.violet)
                if total == 0 {
                    EmptyNote(text: "Workouts from your Watch or WHOOP in this range show up here, matched side by side when both recorded them.",
                              symbol: "figure.run", title: "No workouts in this range")
                }
                ForEach(m.pairs) { p in pairRow(p) }
                ForEach(Array((m.watchOnly + m.whoopOnly).enumerated()), id: \.element.id) { i, w in
                    if i > 0 || !m.pairs.isEmpty { Divider().overlay(Lab.line) }
                    singleRow(w)
                }
            }
        }
    }

    private func pairRow(_ p: Compare.WorkoutPair) -> some View {
        VStack(alignment: .leading, spacing: Lab.S.sm) {
            HStack(spacing: Lab.S.sm) {
                SymbolTile(symbol: p.watch.symbol, tint: Lab.text, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.watch.name).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(p.watch.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · " + fmtHM(p.watch.minutes))
                        .font(.caption.monospacedDigit()).foregroundStyle(Lab.dim)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: Lab.S.s) {
                pairColumn(p.watch, .watch)
                VStack(spacing: Lab.S.xs) {
                    deltaChip(String(localized: "Energy"), p.watch.kcal, p.whoop.kcal)
                    deltaChip(String(localized: "Avg HR"), p.watch.avgHR, p.whoop.avgHR)
                    deltaChip(String(localized: "Max HR"), p.watch.maxHR, p.whoop.maxHR)
                }
                .frame(width: 76)
                pairColumn(p.whoop, .whoop)
            }
        }
        .padding(Lab.S.sm)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
        .overlay(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).strokeBorder(Lab.line))
        .accessibilityElement(children: .combine)
    }

    private func pairColumn(_ w: WorkoutRec, _ s: Source) -> some View {
        VStack(alignment: s == .watch ? .leading : .trailing, spacing: Lab.S.xs) {
            SourceChip(source: s)
            stat(String(localized: "Energy"), w.kcal, "kcal", s)
            stat(String(localized: "Avg HR"), w.avgHR, "bpm", s)
            stat(String(localized: "Max HR"), w.maxHR, "bpm", s)
            if s == .whoop, let st = w.strain { stat(String(localized: "Strain"), st, "", s, decimals: 1) }
            else { stat(String(localized: "Time"), w.minutes, "min", s) }
        }
        .frame(maxWidth: .infinity, alignment: s == .watch ? .leading : .trailing)
    }

    private func stat(_ l: String, _ v: Double?, _ unit: String, _ s: Source, decimals: Int = 0) -> some View {
        VStack(alignment: s == .watch ? .leading : .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v.map { Lab.fmt($0, decimals) } ?? "—").font(Lab.mono(15, .semibold)).foregroundStyle(v == nil ? Lab.faint : Lab.color(s))
                if v != nil && !unit.isEmpty { Text(unit).font(Lab.label(8)).foregroundStyle(Lab.faint) }
            }
            Text(l).font(.caption2).foregroundStyle(Lab.faint)
        }
    }

    /// Watch − WHOOP, tinted toward whoever read higher.
    private func deltaChip(_ l: String, _ a: Double?, _ b: Double?) -> some View {
        VStack(spacing: 0) {
            if let a, let b {
                let d = a - b
                Text(abs(d) < 0.5 ? "=" : Lab.fmt(d, signed: true))
                    .font(Lab.mono(12, .semibold)).foregroundStyle(abs(d) < 0.5 ? Lab.dim : d > 0 ? Lab.watch : Lab.whoop)
            } else {
                Text("—").font(Lab.mono(12, .semibold)).foregroundStyle(Lab.faint)
            }
            Text(l).font(.caption2).foregroundStyle(Lab.faint).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func singleRow(_ w: WorkoutRec) -> some View {
        HStack(spacing: Lab.S.sm) {
            SymbolTile(symbol: w.symbol, tint: Lab.color(w.source), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(w.kcal.map { "\(fmtHM(w.minutes)) · \(Lab.fmt($0)) kcal" } ?? fmtHM(w.minutes))
                    .font(.caption.monospacedDigit()).foregroundStyle(Lab.dim)
            }
            Spacer(minLength: Lab.S.xs)
            SourceChip(source: w.source)
        }
        .padding(.vertical, Lab.S.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
