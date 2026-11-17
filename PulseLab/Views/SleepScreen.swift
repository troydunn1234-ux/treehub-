import SwiftUI
import Charts

struct SleepScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 7
    @State private var source: Source = .watch
    @State private var pickedNight: Date?

    private static let stageOrder: [SleepStage] = [.deep, .core, .rem, .awake]

    private func stageColor(_ s: SleepStage) -> Color { NightSkyHypnogram.color(s) }

    var body: some View {
        LabScroll(kicker: "Night shift", title: "Sleep") {
            hypnogram
            RangePicker(days: $days)
            stages
            averages
        }
    }

    private var nights: [SleepNight] {
        let cut = Date().dayStart.adding(days: -(days - 1))
        return store.sleeps.filter { $0.night >= cut }
    }

    private var hypnogram: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTag("Last night · stages")
                    Spacer()
                    SourceChip(source: .watch)
                }
                if store.hypnogram.isEmpty {
                    EmptyNote(text: "Wear your Apple Watch to bed with Sleep turned on to see stages here.", symbol: "moon.zzz", title: "No stages from last night")
                } else {
                    NightSkyHypnogram(segments: store.hypnogram)
                }
            }
        }
    }

    private var stages: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        SectionTag("Stages per night")
                        Spacer(minLength: Lab.S.s)
                        sourcePicker.frame(width: 170)
                    }
                    VStack(alignment: .leading, spacing: Lab.S.s) {
                        SectionTag("Stages per night")
                        sourcePicker
                    }
                }
                let list = nights.filter { $0.source == source }
                if list.isEmpty {
                    EmptyNote(text: String(localized: "No \(source.name) sleep in this range yet. Try a longer range or the other tracker."),
                              symbol: "moon.zzz", title: "No nights in this range")
                } else {
                    Chart {
                        if let sel = pickedNight {
                            RuleMark(x: .value("Selected", sel, unit: .day))
                                .foregroundStyle(Color.white.opacity(0.18))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    nightTooltip(sel, list)
                                }
                        }
                        ForEach(list) { n in
                            ForEach(Self.stageOrder) { st in
                                BarMark(x: .value("Night", n.night, unit: .day), y: .value("Hours", n.minutes(st) / 60))
                                    .foregroundStyle(by: .value("Stage", L(st.title)))
                                    .opacity(pickedNight.map { Calendar.current.isDate($0, inSameDayAs: n.night) ? 1 : 0.35 } ?? 1)
                                    .cornerRadius(st == .awake ? 5 : 1)
                            }
                        }
                        RuleMark(y: .value("Goal", 8))
                            .foregroundStyle(Lab.warn.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 6))
                        RuleMark(y: .value("Goal", 8))
                            .foregroundStyle(Lab.warn.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("8 h goal").font(.caption2.weight(.semibold)).foregroundStyle(Lab.warn)
                            }
                    }
                    .chartForegroundStyleScale(domain: Self.stageOrder.map { L($0.title) }, range: Self.stageOrder.map(stageColor))
                    .chartLegend(position: .bottom, spacing: 8)
                    .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel(String(localized: "hours")) }
                    .scrubDays(list.map(\.night), selection: $pickedNight)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 210)
                    .chartSummary(String(localized: "\(source.name) sleep stages for \(list.count) nights, averaging \(fmtHM(Stats.mean(list.map(\.asleepMin)))) asleep."))
                }
            }
        }
    }

    private var sourcePicker: some View {
        Picker("Tracker", selection: $source) {
            ForEach(Source.allCases) { s in Text(s.label).tag(s) }
        }
        .pickerStyle(.segmented)
        .onChange(of: source) { _, _ in Lab.tick(); pickedNight = nil }
    }

    /// One night's stages under the finger, plus the total asleep.
    private func nightTooltip(_ day: Date, _ list: [SleepNight]) -> some View {
        let n = list.first { Calendar.current.isDate($0.night, inSameDayAs: day) }
        var lines: [LabChartTooltip.Line] = []
        if let n {
            for st in Self.stageOrder where n.minutes(st) > 0 {
                lines.append(.init(label: L(st.title), value: fmtHM(n.minutes(st)), color: stageColor(st)))
            }
        }
        return LabChartTooltip(title: LabChartTooltip.dayTitle(day), lines: lines,
                               note: n.map { String(localized: "Asleep \(fmtHM($0.asleepMin))") })
    }

    private var averages: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(String(localized: "\(days)-night average")) {
                    CardLink("Trend") { store.detail = .sleep }
                        .accessibilityLabel(String(localized: "Open sleep trend"))
                }
                VSRow(title: "Asleep", unit: "h", watch: avg(.watch) { $0.asleepMin / 60 }, whoop: avg(.whoop) { $0.asleepMin / 60 }, decimals: 1)
                Divider().overlay(Lab.line)
                VSRow(title: "Deep", unit: "min", watch: avg(.watch) { $0.deepMin }, whoop: avg(.whoop) { $0.deepMin })
                Divider().overlay(Lab.line)
                VSRow(title: "REM", unit: "min", watch: avg(.watch) { $0.remMin }, whoop: avg(.whoop) { $0.remMin })
                Divider().overlay(Lab.line)
                VSRow(title: "Efficiency", unit: "%", watch: effAvg(.watch), whoop: effAvg(.whoop))
                Text("Trackers split light vs deep sleep differently, so deep and REM minutes rarely match exactly. Watch the trend, not the single night.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Nights without an in-bed/awake record have no efficiency; leave them out instead of counting them as 0%.
    private func effAvg(_ s: Source) -> Double? {
        Stats.mean(nights.filter { $0.source == s && $0.asleepMin > 0 }.compactMap(\.efficiency))
    }

    private func avg(_ s: Source, _ f: (SleepNight) -> Double) -> Double? {
        Stats.mean(nights.filter { $0.source == s && $0.asleepMin > 0 }.map(f))
    }
}
