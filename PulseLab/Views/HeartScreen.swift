import SwiftUI
import Charts

struct HeartScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 30

    var body: some View {
        LabScroll(kicker: "Engine room", title: "Heart") {
            RangePicker(days: $days)
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
                HStack {
                    SectionTag(title)
                    Spacer()
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint)
                    if let metric {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.detail = metric
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(Lab.watch)
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel("Open \(title.lowercased()) details")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    avgBlock(wAvg, .watch, decimals)
                    avgBlock(hAvg, .whoop, decimals)
                    Spacer()
                }
                if w.isEmpty && h.isEmpty {
                    EmptyNote(text: "No data in this range yet.")
                } else {
                    DuelChart(watch: .from(w, .watch), whoop: .from(h, .whoop), unit: unit, decimals: decimals, height: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title) over \(days) days. Apple Watch average \(fmtA(wAvg, decimals, unit)), WHOOP average \(fmtA(hAvg, decimals, unit)).")
                }
                if let note { Text(note).font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint) }
            }
        }
    }

    private func fmtA(_ v: Double?, _ d: Int, _ u: String) -> String {
        v.map { "\($0.formatted(.number.precision(.fractionLength(d)))) \(u)" } ?? "no data"
    }

    private func avgBlock(_ v: Double?, _ s: Source, _ decimals: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CountUp(value: v, decimals: decimals, size: 24, color: Lab.color(s))
            Text("\(s.short) AVG").font(Lab.label(8)).foregroundStyle(Lab.color(s).opacity(0.7))
        }
    }

    /// WHOOP recovery vs Pulse Lab readiness, day by day.
    private var readinessChart: some View {
        let w = series(.watch) { $0.recovery }, h = series(.whoop) { $0.recovery }
        let from = Date().dayStart.adding(days: -(days - 1))
        return LabPanel(tint: Lab.good) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Recovery vs readiness")
                Chart {
                    RectangleMark(xStart: .value("s", from), xEnd: .value("e", Date()), yStart: .value("lo", 67), yEnd: .value("hi", 100))
                        .foregroundStyle(Lab.good.opacity(0.06))
                    RectangleMark(xStart: .value("s", from), xEnd: .value("e", Date()), yStart: .value("lo", 0), yEnd: .value("hi", 34))
                        .foregroundStyle(Lab.bad.opacity(0.06))
                    ForEach(Array(h.enumerated()), id: \.offset) { _, p in
                        BarMark(x: .value("Day", p.0, unit: .day), y: .value("Recovery", p.1))
                            .foregroundStyle(Lab.band(p.1).opacity(0.75))
                            .cornerRadius(2)
                    }
                    ForEach(Array(w.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Day", p.0, unit: .day), y: .value("Readiness", p.1))
                            .foregroundStyle(Lab.watch)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { LabAxis.xDays }
                .chartYAxis { LabAxis.y }
                .frame(height: 170)
                HStack(spacing: 14) {
                    Label("WHOOP recovery", systemImage: "square.fill").foregroundStyle(Lab.whoop)
                    Label("Watch readiness", systemImage: "line.diagonal").foregroundStyle(Lab.watch)
                }
                .font(Lab.label(9))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.detail = .recovery }
        .accessibilityAddTraits(.isButton)
    }

    private var fitness: some View {
        let t = store.days(.watch).recent(days)
        let vo2 = t.compactMap(\.vo2).last, walk = Stats.mean(t.compactMap(\.walkHR)), rec = Stats.mean(t.compactMap(\.hrRecovery))
        let (wt, wu) = Units.weight(t.compactMap(\.weightKg).last)
        return LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { SectionTag("Fitness"); Spacer(); SourceChip(source: .watch) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    tile("VO₂ MAX", vo2, "ml/kg·min", 1)
                    tile("WALKING HR", walk, "bpm", 0)
                    tile("HR RECOVERY", rec, "bpm/1 min", 0)
                    tile("WEIGHT", wt, wu, 1)
                }
            }
        }
    }

    private func tile(_ l: String, _ v: Double?, _ u: String, _ d: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(Lab.label(9)).foregroundStyle(Lab.dim)
            CountUp(value: v, decimals: d, size: 22, color: Lab.text)
            Text(u).font(Lab.label(8)).foregroundStyle(Lab.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
