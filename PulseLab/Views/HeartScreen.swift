import SwiftUI
import Charts

struct HeartScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var days = 30
    @State private var solo: Source?
    @State private var recoveryDay: Date?

    var body: some View {
        LabScroll(kicker: "Engine room", title: "Heart") {
            ViewThatFits(in: .horizontal) {
                HStack {
                    RangePicker(days: $days)
                    Spacer(minLength: Lab.S.s)
                    DuelLegend(solo: $solo, compact: true)
                }
                VStack(alignment: .leading, spacing: Lab.S.xs) {
                    RangePicker(days: $days)
                    DuelLegend(solo: $solo, compact: true)
                }
            }
            trend("Resting heart rate", unit: "bpm", lowerIsBetter: true, metric: .rhr) { $0.rhr }
            trend("Heart rate variability", unit: "ms", lowerIsBetter: false, note: "Apple Watch measures SDNN, WHOOP measures RMSSD, so WHOOP usually reads higher. Compare the shape of the lines, not the gap.", metric: .hrv) { $0.hrv }
            readinessChart
            trend("Respiratory rate", unit: "br/min", lowerIsBetter: true, decimals: 1, metric: .resp) { $0.resp }
            trend("Blood oxygen", unit: "%", lowerIsBetter: false, decimals: 1, metric: .spo2) { $0.spo2 }
            trend("Temperature deviation", unit: Units.fahrenheit ? "°F" : "°C", lowerIsBetter: true, decimals: 2,
                  note: "Change from your own baseline (Watch: wrist while asleep · WHOOP: skin).", metric: .temp) { Units.tempDelta($0.tempDev).0 }
            fitness
        }
    }

    private func series(_ s: Source, _ f: (DayStat) -> Double?) -> [(Date, Double)] {
        store.days(s).recent(days).compactMap { d in f(d).map { (d.day, $0) } }
    }

    private func trend(_ title: String, unit: String, lowerIsBetter: Bool, decimals: Int = 0, note: String? = nil,
                       metric: MetricKey? = nil, _ f: @escaping (DayStat) -> Double?) -> some View {
        let w = series(.watch, f), h = series(.whoop, f)
        let wAvg = Stats.mean(w.map(\.1)), hAvg = Stats.mean(h.map(\.1))
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title) {
                    if let metric {
                        CardLink("Details") { store.detail = metric }
                            .accessibilityLabel(String(localized: "Open \(L(title).lowercased()) details"))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    avgBlock(wAvg, .watch, decimals, unit)
                    avgBlock(hAvg, .whoop, decimals, unit)
                    Spacer()
                }
                if w.isEmpty && h.isEmpty {
                    EmptyNote(text: "Try a longer range, or wear both trackers for a few days.", symbol: "chart.xyaxis.line", title: "No readings in this range")
                } else {
                    DuelChart(watch: .from(w, .watch), whoop: .from(h, .whoop), unit: unit, decimals: decimals, height: 180, solo: solo)
                        .chartSummary(String(localized: "\(L(title)) over \(days) days. Apple Watch average \(fmtA(wAvg, decimals, unit)), WHOOP average \(fmtA(hAvg, decimals, unit))."))
                }
                if let note { Text(L(note)).font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private func fmtA(_ v: Double?, _ d: Int, _ u: String) -> String {
        v.map { "\($0.formatted(.number.precision(.fractionLength(d)))) \(u)" } ?? String(localized: "no data")
    }

    private func avgBlock(_ v: Double?, _ s: Source, _ decimals: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                CountUp(value: v, decimals: decimals, size: 24, color: Lab.color(s))
                if v != nil { Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint) }
            }
            Text(String(localized: "\(s.label) average")).font(.caption.weight(.medium)).foregroundStyle(Lab.color(s).opacity(0.8))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(s.name) average: \(fmtA(v, decimals, unit))"))
    }

    /// WHOOP recovery vs Pulse Lab readiness, day by day.
    private var readinessChart: some View {
        let w = series(.watch) { $0.recovery }, h = series(.whoop) { $0.recovery }
        let from = Date().dayStart.adding(days: -(days - 1))
        let dayList = Array(Set(w.map { $0.0 } + h.map { $0.0 })).sorted()
        return LabPanel(tint: Lab.good) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader("Recovery vs readiness") {
                    CardLink("Details") { store.detail = .recovery }
                        .accessibilityHint("Opens recovery and readiness from 7 days to a year")
                }
                if w.isEmpty && h.isEmpty {
                    EmptyNote(text: "WHOOP recovery and Watch readiness land here each morning.", symbol: "chart.bar.xaxis", title: "No scores in this range")
                } else {
                    Chart {
                        RectangleMark(xStart: .value("s", from), xEnd: .value("e", Date()), yStart: .value("lo", 67), yEnd: .value("hi", 100))
                            .foregroundStyle(Lab.good.opacity(0.06))
                        RectangleMark(xStart: .value("s", from), xEnd: .value("e", Date()), yStart: .value("lo", 0), yEnd: .value("hi", 34))
                            .foregroundStyle(Lab.bad.opacity(0.06))
                        if let sel = recoveryDay {
                            RuleMark(x: .value("Selected", sel, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.25))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    recoveryTooltip(sel, w, h)
                                }
                        }
                        ForEach(Array(h.enumerated()), id: \.offset) { _, p in
                            BarMark(x: .value("Day", p.0, unit: .day), y: .value("Recovery", p.1))
                                .foregroundStyle(Lab.band(p.1).opacity(0.75))
                                .opacity(recoveryDay.map { Calendar.current.isDate($0, inSameDayAs: p.0) ? 1 : 0.35 } ?? 1)
                                .cornerRadius(2)
                        }
                        ForEach(Array(w.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("Day", p.0, unit: .day), y: .value("Readiness", p.1))
                                .foregroundStyle(Lab.watch)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.monotone)
                        }
                        if let sel = recoveryDay, let r = w.first(where: { Calendar.current.isDate($0.0, inSameDayAs: sel) }) {
                            PointMark(x: .value("Day", r.0, unit: .day), y: .value("Readiness", r.1))
                                .foregroundStyle(Lab.watch)
                                .symbolSize(70)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel(String(localized: "score")) }
                    .scrubDays(dayList, selection: $recoveryDay)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 180)
                    .chartSummary(recoverySummary(w, h))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { recoveryLegend }
                    VStack(alignment: .leading, spacing: 6) { recoveryLegend }
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    @ViewBuilder private var recoveryLegend: some View {
        Label("WHOOP recovery (bars)", systemImage: "chart.bar.fill").foregroundStyle(Lab.whoop)
        Label("Watch readiness (line)", systemImage: "line.diagonal").foregroundStyle(Lab.watch)
    }

    private func recoveryTooltip(_ day: Date, _ w: [(Date, Double)], _ h: [(Date, Double)]) -> some View {
        var lines: [LabChartTooltip.Line] = []
        if let v = h.first(where: { Calendar.current.isDate($0.0, inSameDayAs: day) })?.1 {
            lines.append(.init(label: String(localized: "WHOOP recovery"), value: "\(Int(v.rounded()))%", color: Lab.band(v)))
        }
        if let v = w.first(where: { Calendar.current.isDate($0.0, inSameDayAs: day) })?.1 {
            lines.append(.init(label: String(localized: "Watch readiness"), value: "\(Int(v.rounded()))", color: Lab.watch))
        }
        return LabChartTooltip(title: LabChartTooltip.dayTitle(day), lines: lines)
    }

    private func recoverySummary(_ w: [(Date, Double)], _ h: [(Date, Double)]) -> String {
        let r = Stats.mean(h.map { $0.1 }).map { "\(Int($0.rounded())) %" } ?? String(localized: "no data")
        let a = Stats.mean(w.map { $0.1 }).map { "\(Int($0.rounded()))" } ?? String(localized: "no data")
        return String(localized: "WHOOP recovery and Watch readiness over \(days) days. Recovery averages \(r), readiness averages \(a).")
    }

    private var fitness: some View {
        let t = store.days(.watch).recent(days)
        let vo2 = t.compactMap(\.vo2).last, walk = Stats.mean(t.compactMap(\.walkHR)), rec = Stats.mean(t.compactMap(\.hrRecovery))
        let (wt, wu) = Units.weight(t.compactMap(\.weightKg).last)
        return LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader("Fitness") { SourceChip(source: .watch) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s, alignment: .topLeading),
                                         count: typeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: 14) {
                    tile("VO₂ max", vo2, "ml/kg·min", 1)
                    tile("Walking HR", walk, "bpm", 0)
                    tile("HR recovery", rec, String(localized: "bpm in 1 min"), 0)
                    tile("Weight", wt, wu, 1)
                }
            }
        }
    }

    private func tile(_ l: String, _ v: Double?, _ u: String, _ d: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(l)).font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
            CountUp(value: v, decimals: d, size: 22, color: Lab.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(v == nil ? String(localized: "Not in yet") : u).font(.caption2).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(v.map { "\(L(l)): \(Lab.fmt($0, d)) \(u)" } ?? String(localized: "\(L(l)): not in yet"))
    }
}
