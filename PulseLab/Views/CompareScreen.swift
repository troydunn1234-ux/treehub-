import SwiftUI
import Charts

struct CompareScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 30
    @State private var focus: String = "Resting HR"

    private var agreements: [Agreement] {
        Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
    }

    var body: some View {
        let list = agreements
        LabScroll(kicker: "Lab results", title: "VS") {
            VSSlam()
            RangePicker(days: $days)
            if list.allSatisfy({ $0.n == 0 }) {
                noOverlap
            } else {
                scoreboard(list)
                ForEach(Array(list.filter { $0.n > 0 }.enumerated()), id: \.element.id) { i, a in
                    FightRow(round: i + 1, agreement: a, winner: winner(a), selected: focus == a.metric) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.snappy) { focus = a.metric }
                    }
                    if focus == a.metric {
                        detail(a).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            method
        }
        .onAppear(perform: takeFocus)
        .onChange(of: store.focusCompare) { _, _ in takeFocus() }
    }

    private func takeFocus() {
        guard let f = store.focusCompare else { return }
        withAnimation(.snappy) { focus = f }
        store.focusCompare = nil
    }

    /// Both trackers haven't measured the same days yet.
    @ViewBuilder private var noOverlap: some View {
        if !store.whoopConnected && store.whoopDays.isEmpty {
            LabEmptyState(icon: "bolt.heart.fill", title: "WHOOP isn't connected",
                          message: "Compare needs both trackers. Connect WHOOP (or turn on WHOOP's Apple Health integration) to start the duel.",
                          button: "Connect WHOOP", tint: Lab.whoop) { store.go(.settings) }
        } else {
            LabEmptyState(icon: "hourglass", title: "Not enough overlap yet",
                          message: "Wear both for a couple of days and nights. Every metric unlocks after 3 days measured by both.",
                          button: nil, tint: Lab.violet, action: nil)
        }
    }

    /// Who "wins" a metric: higher reader for absolute metrics, else the steadier (less noisy) tracker.
    private func winner(_ a: Agreement) -> (Source, String)? {
        guard a.n >= 3 else { return nil }
        if let h = a.higher { return (h, "HIGHER") }
        guard let sw = Stats.sd(a.pairs.map(\.watch)), let sh = Stats.sd(a.pairs.map(\.whoop)), sw > 0, sh > 0,
              abs(sw - sh) / max(sw, sh) > 0.1 else { return nil }
        return (sw < sh ? .watch : .whoop, "STEADIER")
    }

    /// Overall: agreement gauge in the middle, rounds "won" (reads higher / steadier) on each side.
    private func scoreboard(_ list: [Agreement]) -> some View {
        let scored = list.filter { $0.n >= 3 }
        let overall = Stats.mean(scored.map(\.score))
        let wins = scored.compactMap { winner($0)?.0 }
        let w = wins.filter { $0 == .watch }.count, h = wins.filter { $0 == .whoop }.count
        return LabPanel(tint: Lab.violet) {
            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    tally(.watch, w)
                    ArcGauge(value: overall, label: "Agree", color: overall.map { $0 >= 70 ? Lab.good : $0 >= 45 ? Lab.warn : Lab.bad } ?? Lab.violet, size: 116)
                    tally(.whoop, h)
                }
                Text("\(scored.count) metrics measured by both · crowns go to the tracker that reads higher, or steadier when they match.")
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Lab.faint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func tally(_ s: Source, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text(s.short).font(Lab.label(10)).tracking(2).foregroundStyle(Lab.color(s))
            CountUp(value: Double(n), size: 40, color: Lab.color(s))
            Text("CROWNS").font(Lab.label(7)).tracking(1.4).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ l: String, _ v: Double?, _ u: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l).font(Lab.label(8)).foregroundStyle(Lab.faint)
            Text(v.map { String(format: abs($0) < 10 ? "%.2f" : "%.0f", $0) } ?? "––").font(Lab.mono(14, .heavy)).foregroundStyle(c)
            Text(u).font(Lab.label(8)).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bland–Altman: each day is a dot at (average of both, difference). The band shows the usual spread.
    private func detail(_ a: Agreement) -> some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("\(a.metric) · \(a.trendOnly ? "day by day" : "difference plot")")
                if a.n < 3 {
                    EmptyNote(text: "Needs at least 3 days where both trackers measured \(a.metric.lowercased()).")
                } else if a.trendOnly {
                    // Normalise both to z-scores so SDNN and RMSSD sit on one scale.
                    let zw = z(a.pairs.map(\.watch)), zh = z(a.pairs.map(\.whoop))
                    Chart {
                        ForEach(Array(a.pairs.enumerated()), id: \.offset) { i, p in
                            LineMark(x: .value("Day", p.day, unit: .day), y: .value("z", zw[i]), series: .value("S", "Watch"))
                                .foregroundStyle(Lab.watch).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
                            LineMark(x: .value("Day", p.day, unit: .day), y: .value("z", zh[i]), series: .value("S", "WHOOP"))
                                .foregroundStyle(Lab.whoop).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        RuleMark(y: .value("0", 0)).foregroundStyle(Lab.faint)
                    }
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(a.metric) trend for both trackers, correlation \(String(format: "%.2f", a.correlation ?? 0)).")
                    Text("Each line is scaled to its own average, so you can see if they rise and fall together. Correlation r = \(String(format: "%.2f", a.correlation ?? 0)).")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
                } else {
                    let b = a.bias ?? 0, sd = a.sdDiff ?? 0
                    Chart {
                        RectangleMark(xStart: .value("lo", minMean(a)), xEnd: .value("hi", maxMean(a)),
                                      yStart: .value("l", b - 1.96 * sd), yEnd: .value("u", b + 1.96 * sd))
                            .foregroundStyle(LinearGradient(colors: [Lab.watch.opacity(0.16), Lab.violet.opacity(0.10), Lab.whoop.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                        RuleMark(y: .value("bias", b)).foregroundStyle(Lab.text.opacity(0.7))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("AVG GAP \(String(format: "%+.1f", b))").font(Lab.label(8)).foregroundStyle(Lab.dim)
                            }
                        RuleMark(y: .value("zero", 0)).foregroundStyle(Lab.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        ForEach(a.pairs) { p in
                            PointMark(x: .value("Average", (p.watch + p.whoop) / 2), y: .value("Watch − WHOOP", p.watch - p.whoop))
                                .foregroundStyle((p.watch >= p.whoop ? Lab.watch : Lab.whoop).opacity(0.25))
                                .symbolSize(160)
                            PointMark(x: .value("Average", (p.watch + p.whoop) / 2), y: .value("Watch − WHOOP", p.watch - p.whoop))
                                .foregroundStyle(p.watch >= p.whoop ? Lab.watch : Lab.whoop)
                                .symbolSize(40)
                        }
                    }
                    .chartXScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(Lab.line)
                            AxisValueLabel().foregroundStyle(Lab.faint).font(Lab.mono(9, .medium))
                        }
                    }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 200)
                    .shadow(color: Lab.watch.opacity(0.25), radius: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Difference plot for \(a.metric). On average Apple Watch reads \(String(format: "%+.1f", b)) \(a.unit) versus WHOOP across \(a.n) days.")
                    Text("Dots above the line: Watch read higher (cyan). Below: WHOOP read higher (amber). The shaded band is where 95% of days fall.")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
                }
            }
        }
    }

    private func minMean(_ a: Agreement) -> Double { a.pairs.map { ($0.watch + $0.whoop) / 2 }.min() ?? 0 }
    private func maxMean(_ a: Agreement) -> Double { a.pairs.map { ($0.watch + $0.whoop) / 2 }.max() ?? 1 }

    private func z(_ v: [Double]) -> [Double] {
        guard let m = Stats.mean(v), let s = Stats.sd(v), s > 0 else { return v.map { _ in 0 } }
        return v.map { ($0 - m) / s }
    }

    private var method: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTag("How we compare")
                Text("""
                Only days (or nights) where both trackers recorded a value are compared. "Agree" means within \
                3 bpm resting HR, 20 min of sleep, 1 breath/min, 2% SpO₂, 0.3 °C or 250 kcal. HRV is compared by \
                trend because Apple Watch logs SDNN and WHOOP logs RMSSD. Readiness is Pulse Lab's own Watch \
                score, not an Apple metric.
                """)
                .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
            }
        }
    }
}
