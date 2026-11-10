import SwiftUI
import Charts

struct SleepScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 7
    @State private var source: Source = .watch

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
                    EmptyNote(text: "Wear your Apple Watch to bed with Sleep turned on to see stages here.")
                } else {
                    NightSkyHypnogram(segments: store.hypnogram)
                }
            }
        }
    }

    private var stages: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTag("Stages per night")
                    Spacer()
                    Picker("Source", selection: $source) {
                        ForEach(Source.allCases) { s in Text(s.short).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .onChange(of: source) { _, _ in Lab.tick() }
                }
                let list = nights.filter { $0.source == source }
                if list.isEmpty {
                    EmptyNote(text: "No \(source.name) sleep in this range yet.")
                } else {
                    Chart {
                        ForEach(list) { n in
                            ForEach([SleepStage.deep, .core, .rem, .awake]) { st in
                                BarMark(x: .value("Night", n.night, unit: .day), y: .value("Hours", n.minutes(st) / 60))
                                    .foregroundStyle(by: .value("Stage", st.title))
                                    .cornerRadius(st == .awake ? 5 : 1)
                            }
                        }
                        RuleMark(y: .value("Goal", 8))
                            .foregroundStyle(Lab.warn.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 6))
                        RuleMark(y: .value("Goal", 8))
                            .foregroundStyle(Lab.warn.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) { Text("8H GOAL").font(Lab.label(8)).foregroundStyle(Lab.warn) }
                    }
                    .chartForegroundStyleScale(["Deep": stageColor(.deep), "Light": stageColor(.core), "REM": stageColor(.rem), "Awake": stageColor(.awake)])
                    .chartLegend(position: .bottom, spacing: 8)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 200)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(source.name) sleep stages for \(list.count) nights, averaging \(fmtHM(Stats.mean(list.map(\.asleepMin)))) asleep.")
                }
            }
        }
    }

    private var averages: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTag("\(days)-night average")
                    Spacer()
                    Button { store.detail = .sleep } label: {
                        Text("TREND").font(Lab.label(9)).foregroundStyle(Lab.watch)
                    }
                    .accessibilityLabel("Open sleep trend")
                }
                VSRow(title: "Asleep", unit: "h", watch: avg(.watch) { $0.asleepMin / 60 }, whoop: avg(.whoop) { $0.asleepMin / 60 }, decimals: 1)
                Divider().overlay(Lab.line)
                VSRow(title: "Deep", unit: "min", watch: avg(.watch) { $0.deepMin }, whoop: avg(.whoop) { $0.deepMin })
                Divider().overlay(Lab.line)
                VSRow(title: "REM", unit: "min", watch: avg(.watch) { $0.remMin }, whoop: avg(.whoop) { $0.remMin })
                Divider().overlay(Lab.line)
                VSRow(title: "Efficiency", unit: "%", watch: effAvg(.watch), whoop: effAvg(.whoop))
                Text("Trackers split light vs deep sleep differently, so deep and REM minutes rarely match exactly. Watch the trend, not the single night.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
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
