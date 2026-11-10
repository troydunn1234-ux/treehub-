import SwiftUI
import Charts

/// Tap any metric: 7/30/90-day chart for both trackers, min/max/avg table, agreement, and what the metric means.
struct MetricDetailSheet: View {
    let metric: MetricKey
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    @State private var solo: Source?

    private struct Point: Identifiable { let day: Date; let value: Double; let source: Source; var id: String { "\(source.rawValue)\(day.timeIntervalSince1970)" } }

    private var points: [Point] {
        let cut = Date().dayStart.adding(days: -(days - 1))
        if metric.usesNights {
            return store.sleeps.filter { $0.night >= cut }.compactMap { n in
                metric.nightValue(n).map { Point(day: n.night.dayStart, value: $0, source: n.source) }
            }
            .sorted { $0.day < $1.day }
        }
        return Source.allCases.flatMap { s in
            store.days(s).recent(days).compactMap { d in metric.value(d).map { Point(day: d.day, value: $0, source: s) } }
        }
    }

    private var agreement: Agreement? {
        guard let name = metric.compareName else { return nil }
        return Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
            .first { $0.metric == name && $0.n > 0 }
    }

    var body: some View {
        let pts = points
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: "Metric", title: metric.title)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.07)))
                        }
                        .accessibilityLabel("Close")
                    }
                    RangePicker(days: $days)
                    chart(pts)
                    table(pts)
                    if let a = agreement { agreementCard(a) }
                    LabPanel(tint: Lab.violet) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTag("What it is · why they differ")
                            Text(metric.explanation).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func chart(_ pts: [Point]) -> some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                DuelLegend(solo: $solo)
                if pts.isEmpty {
                    EmptyNote(text: "No \(metric.title.lowercased()) in the last \(days) days.")
                } else {
                    DuelChart(watch: pts.filter { $0.source == .watch }.map { DuelPoint(day: $0.day, value: $0.value, source: .watch) },
                              whoop: pts.filter { $0.source == .whoop }.map { DuelPoint(day: $0.day, value: $0.value, source: .whoop) },
                              unit: metric.unit, decimals: metric.decimals, height: 240, showPoints: days <= 30, solo: solo)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary(pts))
                }
            }
        }
    }

    private func table(_ pts: [Point]) -> some View {
        LabPanel(tint: Lab.violet) {
            VStack(spacing: 10) {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(["MIN", "AVG", "MAX", "DAYS"], id: \.self) { h in
                        Text(h).font(Lab.label(9)).foregroundStyle(Lab.faint).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                ForEach(Source.allCases) { s in
                    let v = pts.filter { $0.source == s }.map(\.value)
                    HStack {
                        SourceChip(source: s).frame(maxWidth: .infinity, alignment: .leading)
                        cell(v.min(), s)
                        cell(Stats.mean(v), s)
                        cell(v.max(), s)
                        Text("\(v.count)").font(Lab.mono(13)).foregroundStyle(Lab.dim).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.name): minimum \(fmt(v.min())), average \(fmt(Stats.mean(v))), maximum \(fmt(v.max())), \(v.count) days")
                }
            }
        }
    }

    private func cell(_ v: Double?, _ s: Source) -> some View {
        Text(fmt(v)).font(Lab.mono(14, .heavy)).foregroundStyle(Lab.color(s))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .minimumScaleFactor(0.7).lineLimit(1)
    }

    private func agreementCard(_ a: Agreement) -> some View {
        LabPanel(tint: Lab.good) {
            HStack(spacing: 16) {
                ArcGauge(value: a.score, label: "Agree", color: a.score >= 70 ? Lab.good : a.score >= 45 ? Lab.warn : Lab.bad, size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.verdict).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Lab.text)
                    Text("\(a.n) \(metric.usesNights ? "nights" : "days") measured by both").font(Lab.mono(11)).foregroundStyle(Lab.dim)
                    if let w = winner(a) { CrownChip(source: w.0, label: w.1) }
                }
            }
        }
    }

    /// Who "wins": higher reader for absolute metrics, steadier one otherwise.
    private func winner(_ a: Agreement) -> (Source, String)? {
        if let h = a.higher { return (h, "READS HIGHER") }
        let sw = Stats.sd(a.pairs.map(\.watch)), sh = Stats.sd(a.pairs.map(\.whoop))
        guard let sw, let sh, sw > 0, sh > 0, abs(sw - sh) / max(sw, sh) > 0.1 else { return nil }
        return (sw < sh ? .watch : .whoop, "STEADIER")
    }

    private func fmt(_ v: Double?) -> String {
        v.map { $0.formatted(.number.precision(.fractionLength(metric.decimals))) } ?? "––"
    }

    private func summary(_ pts: [Point]) -> String {
        Source.allCases.map { s in
            let v = pts.filter { $0.source == s }.map(\.value)
            guard let m = Stats.mean(v) else { return "\(s.name): no data" }
            return "\(s.name) averages \(fmt(m)) \(metric.unit) over \(v.count) days"
        }
        .joined(separator: ". ")
    }
}
