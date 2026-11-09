import SwiftUI
import Charts

struct SleepScreen: View {
    @Environment(LabStore.self) private var store
    @State private var days = 7
    @State private var source: Source = .watch

    private func stageColor(_ s: SleepStage) -> Color {
        switch s {
        case .awake: Color(red: 1, green: 0.42, blue: 0.42)
        case .rem: Lab.violet
        case .core: Lab.watch.opacity(0.75)
        case .deep: Color(red: 0.16, green: 0.36, blue: 1)
        }
    }

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
                    Chart(store.hypnogram) { seg in
                        RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                                      yStart: .value("Lo", Double(seg.stage.level) - 0.38), yEnd: .value("Hi", Double(seg.stage.level) + 0.38))
                            .foregroundStyle(stageColor(seg.stage))
                            .cornerRadius(3)
                    }
                    .chartYScale(domain: -0.6...3.6)
                    .chartYAxis {
                        AxisMarks(values: [0, 1, 2, 3]) { v in
                            AxisValueLabel {
                                let l = v.as(Int.self) ?? 0
                                Text(SleepStage.allCases.first { $0.level == l }?.title.uppercased() ?? "")
                                    .font(Lab.label(8)).foregroundStyle(Lab.faint)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine().foregroundStyle(Lab.line)
                            AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Lab.faint).font(Lab.mono(9, .medium))
                        }
                    }
                    .frame(height: 150)
                    .shadow(color: Lab.violet.opacity(0.4), radius: 8)
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
                                    .cornerRadius(2)
                            }
                        }
                        RuleMark(y: .value("Goal", 8))
                            .foregroundStyle(Lab.faint)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) { Text("8H").font(Lab.label(8)).foregroundStyle(Lab.faint) }
                    }
                    .chartForegroundStyleScale(["Deep": stageColor(.deep), "Light": stageColor(.core), "REM": stageColor(.rem), "Awake": stageColor(.awake)])
                    .chartLegend(position: .bottom, spacing: 8)
                    .chartXAxis { LabAxis.xDays }
                    .chartYAxis { LabAxis.y }
                    .frame(height: 200)
                }
            }
        }
    }

    private var averages: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTag("\(days)-night average")
                VSRow(title: "Asleep", unit: "h", watch: avg(.watch) { $0.asleepMin / 60 }, whoop: avg(.whoop) { $0.asleepMin / 60 }, decimals: 1)
                Divider().overlay(Lab.line)
                VSRow(title: "Deep", unit: "min", watch: avg(.watch) { $0.deepMin }, whoop: avg(.whoop) { $0.deepMin })
                Divider().overlay(Lab.line)
                VSRow(title: "REM", unit: "min", watch: avg(.watch) { $0.remMin }, whoop: avg(.whoop) { $0.remMin })
                Divider().overlay(Lab.line)
                VSRow(title: "Efficiency", unit: "%", watch: avg(.watch) { $0.efficiency ?? 0 }, whoop: avg(.whoop) { $0.efficiency ?? 0 })
                Text("Trackers split light vs deep sleep differently, so deep and REM minutes rarely match exactly. Watch the trend, not the single night.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.faint)
            }
        }
    }

    private func avg(_ s: Source, _ f: (SleepNight) -> Double) -> Double? {
        Stats.mean(nights.filter { $0.source == s && $0.asleepMin > 0 }.map(f))
    }
}
