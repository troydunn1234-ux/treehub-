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
        LabScroll(kicker: "Lab results", title: "Compare") {
            RangePicker(days: $days)
            scoreboard(list)
            if let a = list.first(where: { $0.metric == focus }) { detail(a) }
            ForEach(list.filter { $0.n > 0 }) { a in row(a) }
            method
        }
    }

    /// Overall: how many metrics agree, and who reads higher where.
    private func scoreboard(_ list: [Agreement]) -> some View {
        let scored = list.filter { $0.n >= 3 }
        let overall = Stats.mean(scored.map(\.score))
        let watchHigher = scored.filter { $0.higher == .watch }.map(\.metric)
        let whoopHigher = scored.filter { $0.higher == .whoop }.map(\.metric)
        return LabPanel(tint: Lab.violet) {
            HStack(spacing: 18) {
                GaugeRing(value: overall, label: "Agreement", color: overall.map { $0 >= 70 ? Lab.good : $0 >= 45 ? Lab.warn : Lab.bad } ?? Lab.violet, size: 116)
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(scored.count) metrics measured by both").font(Lab.mono(11)).foregroundStyle(Lab.dim)
                    higherLine(.watch, watchHigher)
                    higherLine(.whoop, whoopHigher)
                }
            }
        }
    }

    private func higherLine(_ s: Source, _ metrics: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(s.short) READS HIGHER").font(Lab.label(9)).tracking(1.2).foregroundStyle(Lab.color(s))
            Text(metrics.isEmpty ? "Nothing notable" : metrics.joined(separator: " · "))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
        }
    }

    private func row(_ a: Agreement) -> some View {
        Button { withAnimation(.snappy) { focus = a.metric } } label: {
            LabPanel(tint: focus == a.metric ? Lab.watch : Lab.violet) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(a.metric).font(Lab.display(17, .heavy)).foregroundStyle(Lab.text)
                        Spacer()
                        Text(a.agreePercent.map { "\(Int($0))%" } ?? "––").font(Lab.mono(18, .heavy))
                            .foregroundStyle(a.score >= 70 ? Lab.good : a.score >= 45 ? Lab.warn : Lab.bad)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule().fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * min(1, a.score / 100))
                        }
                    }
                    .frame(height: 6)
                    HStack(spacing: 12) {
                        stat("WATCH AVG", a.meanWatch, a.unit, Lab.watch)
                        stat("WHOOP AVG", a.meanWhoop, a.unit, Lab.whoop)
                        stat(a.trendOnly ? "CORREL." : "AVG GAP", a.trendOnly ? a.correlation : a.bias, a.trendOnly ? "r" : a.unit, Lab.text)
                    }
                    Text(a.verdict + " · \(a.n) days").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                }
            }
        }
        .buttonStyle(.plain)
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
                    Text("Each line is scaled to its own average, so you can see if they rise and fall together. Correlation r = \(String(format: "%.2f", a.correlation ?? 0)).")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
                } else {
                    let b = a.bias ?? 0, sd = a.sdDiff ?? 0
                    Chart {
                        RectangleMark(xStart: .value("lo", minMean(a)), xEnd: .value("hi", maxMean(a)),
                                      yStart: .value("l", b - 1.96 * sd), yEnd: .value("u", b + 1.96 * sd))
                            .foregroundStyle(Lab.violet.opacity(0.12))
                        RuleMark(y: .value("bias", b)).foregroundStyle(Lab.text.opacity(0.7))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("AVG GAP \(String(format: "%+.1f", b))").font(Lab.label(8)).foregroundStyle(Lab.dim)
                            }
                        RuleMark(y: .value("zero", 0)).foregroundStyle(Lab.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        ForEach(a.pairs) { p in
                            PointMark(x: .value("Average", (p.watch + p.whoop) / 2), y: .value("Watch − WHOOP", p.watch - p.whoop))
                                .foregroundStyle(p.watch >= p.whoop ? Lab.watch : Lab.whoop)
                                .symbolSize(46)
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
