import SwiftUI
import Charts

struct CompareScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 30
    @State private var focus: String = "Resting HR"
    @State private var showTrust = false

    private var agreements: [Agreement] {
        Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
    }

    var body: some View {
        let list = agreements
        LabScroll(kicker: "Lab results", title: "VS") {
            VSSlam()
            ViewThatFits(in: .horizontal) {
                HStack {
                    RangePicker(days: $days)
                    Spacer(minLength: Lab.S.s)
                    trustButton
                }
                VStack(alignment: .leading, spacing: Lab.S.s) {
                    RangePicker(days: $days)
                    trustButton
                }
            }
            if list.allSatisfy({ $0.n == 0 }) {
                noOverlap
            } else {
                verdictCard(list)
                scoreboard(list)
                roundsHeader
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
            method(list)
        }
        .onAppear(perform: takeFocus)
        .onChange(of: store.focusCompare) { _, _ in takeFocus() }
        .sheet(isPresented: $showTrust) {
            TrustScreen().environment(store).presentationBackground(Lab.bg)
        }
    }

    /// Header button → "Who to trust" (metric-by-metric guidance).
    private var trustButton: some View {
        Button {
            Lab.tick()
            showTrust = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.footnote.weight(.semibold))
                Text("Who to trust").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Lab.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(Lab.accent.opacity(0.15)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Opens guidance on which tracker to believe for each metric")
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
                          button: "Sync now", tint: Lab.accent) { Task { await store.refresh(.user) } }
        }
    }

    /// One-paragraph verdict: who reads higher on how many metrics, and where the two agree best.
    private func verdictCard(_ list: [Agreement]) -> some View {
        let scored = list.filter { $0.n >= 3 }
        let whoopHigher = scored.filter { $0.higher == .whoop }.count
        let watchHigher = scored.filter { $0.higher == .watch }.count
        let best = scored.filter { !$0.trendOnly }.max { ($0.agreePercent ?? 0) < ($1.agreePercent ?? 0) }
        let bestR = scored.compactMap { a in a.correlation.map { (a, $0) } }.max { $0.1 < $1.1 }
        var lines: [String] = []
        if whoopHigher > watchHigher { lines.append(String(localized: "WHOOP reads higher on \(whoopHigher) of \(scored.count) metrics.")) }
        else if watchHigher > whoopHigher { lines.append(String(localized: "Apple Watch reads higher on \(watchHigher) of \(scored.count) metrics.")) }
        else if !scored.isEmpty { lines.append(String(localized: "Neither tracker reads consistently higher.")) }
        if let best, let p = best.agreePercent {
            let pct = (p / 100).formatted(.percent.precision(.fractionLength(0)))
            let tol = "\(best.tolerance.formatted()) \(best.unit)"
            lines.append(String(localized: "Strongest agreement: \(L(best.metric)), \(pct) of days within \(tol)."))
        }
        if let bestR {
            let r = bestR.1.formatted(.number.precision(.fractionLength(2)))
            lines.append(String(localized: "Best trend match: \(L(bestR.0.metric)) (r = \(r))."))
        }
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader(String(localized: "Verdict · \(days) days"), symbol: "checkmark.seal.fill", tint: Lab.accent)
                if lines.isEmpty {
                    Text("A few more days where both trackers measured the same thing and the verdict fills in.")
                        .font(.subheadline).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(lines, id: \.self) { l in
                        LabBullet(l, tint: Lab.accent, color: Lab.text)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Who "wins" a metric: higher reader for absolute metrics, else the steadier (less noisy) tracker.
    private func winner(_ a: Agreement) -> (Source, String)? {
        guard a.n >= 3 else { return nil }
        if let h = a.higher { return (h, String(localized: "reads higher")) }
        guard let sw = Stats.sd(a.pairs.map(\.watch)), let sh = Stats.sd(a.pairs.map(\.whoop)), sw > 0, sh > 0,
              abs(sw - sh) / max(sw, sh) > 0.1 else { return nil }
        return (sw < sh ? .watch : .whoop, String(localized: "steadier"))
    }

    /// Overall: agreement gauge in the middle, rounds "won" (reads higher / steadier) on each side.
    private func scoreboard(_ list: [Agreement]) -> some View {
        let scored = list.filter { $0.n >= 3 }
        let overall = Stats.mean(scored.map(\.score))
        let wins = scored.compactMap { winner($0)?.0 }
        let w = wins.filter { $0 == .watch }.count, h = wins.filter { $0 == .whoop }.count
        return LabPanel {
            VStack(spacing: Lab.S.sm) {
                HStack(alignment: .center) {
                    tally(.watch, w)
                    ArcGauge(value: overall, label: "Agree", color: overall.map { $0 >= 70 ? Lab.good : $0 >= 45 ? Lab.warn : Lab.bad } ?? Lab.faint, size: 116)
                    tally(.whoop, h)
                }
                Text("\(scored.count) metrics measured by both. Crowns go to the tracker that reads higher, or the steadier one when they match.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tally(_ s: Source, _ n: Int) -> some View {
        VStack(spacing: 4) {
            SourceChip(source: s)
            CountUp(value: Double(n), size: 40, color: Lab.color(s))
            Text("crowns").font(.caption).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(s.name): \(n) crowns"))
    }

    private var roundsHeader: some View {
        CardHeader("Round by round", subtitle: "Tap a metric for the day-by-day detail")
            .padding(.top, Lab.S.s)
    }

    /// The focused metric in plain words, plus its chart: a difference plot, or (HRV) both trends side by side.
    private func detail(_ a: Agreement) -> some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader(String(localized: "\(L(a.metric)) in plain words"))
                Text(a.plain).font(.subheadline).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
                if !a.why.isEmpty { InfoBox(text: a.why) }
                Divider().overlay(Lab.line)
                CardHeader(a.trendOnly ? "Day by day" : "Difference plot",
                           subtitle: a.n >= 3 ? "Press and drag the chart to read each day" : nil)
                if a.n < 3 {
                    EmptyNote(text: String(localized: "Needs at least 3 days where both trackers measured \(L(a.metric).lowercased())."),
                              symbol: "calendar.badge.clock", title: "Not enough days yet")
                } else if a.trendOnly {
                    AgreementTrendChart(agreement: a)
                    Text("Each line is scaled to its own average, so you can see whether they rise and fall together.")
                        .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                } else {
                    AgreementScatter(agreement: a)
                    Text("Each dot is one day. Above the line, the Watch read higher (cyan); below it, WHOOP did (amber). The shaded band is where 95% of days fall.")
                        .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What counts as agreeing, metric by metric, straight from the comparison's own tolerances.
    private func method(_ list: [Agreement]) -> some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader("How we compare", symbol: "ruler", tint: Lab.accent)
                Text("Only days (or nights) when both trackers recorded a value count. A day agrees when the two land within:")
                    .font(.subheadline).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Divider().overlay(Lab.line) }
                        HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
                            Text(L(a.metric)).font(.subheadline).foregroundStyle(Lab.text)
                            Spacer(minLength: Lab.S.s)
                            Text(tolerance(a)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Lab.dim)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, Lab.S.s)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Lab.S.sm)
                .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
                Text("Readiness is Pulse Lab's own score from your Watch, not a number Apple shows.")
                    .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tolerance(_ a: Agreement) -> String {
        if a.trendOnly { return String(localized: "Same direction (SDNN vs RMSSD)") }
        if a.unit == "h" { return "± \(Int((a.tolerance * 60).rounded())) min" }
        return "± \(a.tolerance.formatted()) \(a.unit)"
    }
}

// MARK: - Charts

/// HRV-style comparison: both trackers on their own scale (z-scores), with press-and-drag to read the raw
/// numbers for a day.
struct AgreementTrendChart: View {
    let agreement: Agreement
    @State private var selected: Date?

    private func z(_ v: [Double]) -> [Double] {
        guard let m = Stats.mean(v), let s = Stats.sd(v), s > 0 else { return v.map { _ in 0 } }
        return v.map { ($0 - m) / s }
    }

    var body: some View {
        let a = agreement
        let zw = z(a.pairs.map(\.watch)), zh = z(a.pairs.map(\.whoop))
        let pick = selected.flatMap { s in a.pairs.firstIndex { Calendar.current.isDate($0.day, inSameDayAs: s) } }
        Chart {
            RuleMark(y: .value("Average", 0)).foregroundStyle(Lab.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            ForEach(Array(a.pairs.enumerated()), id: \.offset) { i, p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value("z", zw[i]), series: .value("S", "Watch"))
                    .foregroundStyle(Lab.watch).interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                LineMark(x: .value("Day", p.day, unit: .day), y: .value("z", zh[i]), series: .value("S", "WHOOP"))
                    .foregroundStyle(Lab.whoop).interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let i = pick {
                let p = a.pairs[i]
                RuleMark(x: .value("Selected", p.day, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        LabChartTooltip(title: LabChartTooltip.dayTitle(p.day), lines: [
                            .init(label: Source.watch.label, value: value(p.watch), color: Lab.watch),
                            .init(label: Source.whoop.label, value: value(p.whoop), color: Lab.whoop),
                        ])
                    }
                PointMark(x: .value("Day", p.day, unit: .day), y: .value("z", zw[i])).foregroundStyle(Lab.watch).symbolSize(70)
                PointMark(x: .value("Day", p.day, unit: .day), y: .value("z", zh[i])).foregroundStyle(Lab.whoop).symbolSize(70)
            }
        }
        .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel(String(localized: "vs own average (SD)")) }
        .scrubDays(a.pairs.map(\.day), selection: $selected)
        .chartXAxis { LabAxis.xDays }
        .chartYAxis { LabAxis.y }
        .frame(height: 190)
        .chartSummary(summary)
    }

    private func value(_ v: Double) -> String { "\(v.formatted(.number.precision(.fractionLength(0)))) \(agreement.unit)" }

    private var summary: String {
        let a = agreement
        let r = (a.correlation ?? 0).formatted(.number.precision(.fractionLength(2)))
        let w = Stats.mean(a.pairs.map(\.watch)).map(value) ?? "—", h = Stats.mean(a.pairs.map(\.whoop)).map(value) ?? "—"
        return String(localized: "\(L(a.metric)) trend for both trackers over \(a.n) days. Apple Watch averages \(w), WHOOP \(h). Correlation \(r).")
    }
}

/// Bland–Altman difference plot: each day is a dot at (average of both, Watch − WHOOP); the band is the usual
/// spread. Press and drag to read a day's two numbers.
struct AgreementScatter: View {
    let agreement: Agreement
    @State private var rawX: Double?
    @State private var picked: Date?

    private func mid(_ p: Agreement.Pair) -> Double { (p.watch + p.whoop) / 2 }

    var body: some View {
        let a = agreement
        let b = a.bias ?? 0, sd = a.sdDiff ?? 0
        let lo = a.pairs.map(mid).min() ?? 0, hi = a.pairs.map(mid).max() ?? 1
        let sel = picked.flatMap { d in a.pairs.first { $0.day == d } }
        Chart {
            RectangleMark(xStart: .value("Low", lo), xEnd: .value("High", hi),
                          yStart: .value("Lower", b - 1.96 * sd), yEnd: .value("Upper", b + 1.96 * sd))
                .foregroundStyle(LinearGradient(colors: [Lab.watch.opacity(0.16), Color.white.opacity(0.04), Lab.whoop.opacity(0.16)], startPoint: .top, endPoint: .bottom))
            RuleMark(y: .value("Average gap", b)).foregroundStyle(Lab.text.opacity(0.7))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Average gap \(Lab.fmt(b, 1, signed: true))").font(.caption2.weight(.semibold)).foregroundStyle(Lab.dim)
                }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Lab.faint).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            ForEach(a.pairs) { p in
                let dim = sel != nil && sel?.day != p.day
                PointMark(x: .value("Average", mid(p)), y: .value("Watch − WHOOP", p.watch - p.whoop))
                    .foregroundStyle((p.watch >= p.whoop ? Lab.watch : Lab.whoop).opacity(dim ? 0.1 : 0.25))
                    .symbolSize(160)
                PointMark(x: .value("Average", mid(p)), y: .value("Watch − WHOOP", p.watch - p.whoop))
                    .foregroundStyle((p.watch >= p.whoop ? Lab.watch : Lab.whoop).opacity(dim ? 0.4 : 1))
                    .symbolSize(40)
            }
            if let p = sel {
                RuleMark(x: .value("Selected", mid(p)))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(p)
                    }
                PointMark(x: .value("Average", mid(p)), y: .value("Watch − WHOOP", p.watch - p.whoop))
                    .foregroundStyle(Lab.text)
                    .symbolSize(90)
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel("Watch − WHOOP · " + a.unit) }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Lab.line)
                AxisValueLabel().foregroundStyle(Lab.faint).font(LabAxis.labelFont)
            }
        }
        .chartYAxis { LabAxis.y }
        .chartXSelection(value: $rawX)
        .onChange(of: rawX) { _, r in
            let nearest = r.flatMap { r in a.pairs.min { abs(mid($0) - r) < abs(mid($1) - r) } }
            if nearest?.day != picked { picked = nearest?.day }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .frame(height: 210)
        .chartSummary(summary)
    }

    private func fmt(_ v: Double) -> String { Lab.fmt(v, abs(v) < 10 ? 1 : 0) }

    private func tooltip(_ p: Agreement.Pair) -> some View {
        let u = agreement.unit
        return LabChartTooltip(title: LabChartTooltip.dayTitle(p.day), lines: [
            .init(label: Source.watch.label, value: "\(fmt(p.watch)) \(u)", color: Lab.watch),
            .init(label: Source.whoop.label, value: "\(fmt(p.whoop)) \(u)", color: Lab.whoop),
            .init(label: String(localized: "Gap"), value: "\(Lab.fmt(p.watch - p.whoop, abs(p.watch - p.whoop) < 10 ? 1 : 0, signed: true)) \(u)", color: Lab.text),
        ])
    }

    private var summary: String {
        let a = agreement
        let gap = "\(Lab.fmt(a.bias ?? 0, 1, signed: true)) \(a.unit)"
        let within = a.pairs.filter { abs($0.watch - $0.whoop) <= a.tolerance }.count
        return String(localized: "Difference plot for \(L(a.metric)) over \(a.n) days. On average Apple Watch reads \(gap) versus WHOOP. \(within) of \(a.n) days within \(a.tolerance.formatted()) \(a.unit).")
    }
}
