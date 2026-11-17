import SwiftUI
import Charts

// Sauna vs recovery: do mornings after a heat day look different (HRV, resting heart rate)?

enum RecoveryMetric: String, CaseIterable, Identifiable {
    case hrv, rhr
    var id: String { rawValue }
    var title: LocalizedStringKey { self == .hrv ? "HRV" : "Resting HR" }
    var unit: String { self == .hrv ? "ms" : "bpm" }
    var higherIsBetter: Bool { self == .hrv }
}

/// One day: heat minutes that day, and the next morning's numbers.
struct RecoveryDay: Identifiable, Hashable {
    let day: Date
    let heatMinutes: Double
    let nextHRV: Double?
    let nextRHR: Double?
    var id: Date { day }
    var isHeatDay: Bool { heatMinutes >= 1 }
    func value(_ m: RecoveryMetric) -> Double? { m == .hrv ? nextHRV : nextRHR }
}

struct RecoveryGroup: Identifiable {
    let label: String
    let average: Double
    let count: Int
    let heat: Bool
    var id: String { label }
}

final class RecoveryModel: ObservableObject {
    @Published private(set) var days: [RecoveryDay] = []
    @Published private(set) var loaded = false
    @Published private(set) var sources: [String] = []

    /// Pair each day (last 90, up to yesterday) with the next morning's readings.
    func load(heat: [HeatEntry]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var minutesByDay: [Date: Double] = [:]
        for h in heat where h.minutes >= 1 { minutesByDay[cal.startOfDay(for: h.start), default: 0] += h.minutes }
        // Start no earlier than a month before the first heat session, so "other days" stay comparable.
        let firstHeat = minutesByDay.keys.min() ?? today
        let floor = cal.date(byAdding: .day, value: -90, to: today) ?? today
        let from = max(floor, cal.date(byAdding: .day, value: -30, to: firstHeat) ?? floor)

        if ProcessInfo.processInfo.arguments.contains("-demo") {
            days = Self.demo(from: from, to: today, minutes: minutesByDay)
            sources = ["WHOOP"]
            loaded = true
            return
        }
        MindfulHealth.shared.requestRecoveryAccess { [weak self] _ in
            MindfulHealth.shared.morningRecovery(since: from) { rec in
                guard let self else { return }
                var out: [RecoveryDay] = []
                var d = from
                while d < today {
                    guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                    let r = rec[next]
                    out.append(RecoveryDay(day: d, heatMinutes: minutesByDay[d] ?? 0, nextHRV: r?.hrv, nextRHR: r?.restingHR))
                    d = next
                }
                self.days = out
                self.sources = Array(Set(rec.values.flatMap(\.sources))).sorted()
                self.loaded = true
            }
        }
    }

    func groups(_ m: RecoveryMetric) -> [RecoveryGroup] {
        func group(_ heat: Bool) -> RecoveryGroup? {
            let vals = days.filter { $0.isHeatDay == heat }.compactMap { $0.value(m) }
            guard !vals.isEmpty else { return nil }
            return RecoveryGroup(label: heat ? String(localized: "After heat") : String(localized: "Other days"),
                                 average: vals.reduce(0, +) / Double(vals.count), count: vals.count, heat: heat)
        }
        return [group(true), group(false)].compactMap { $0 }
    }

    var hasAnyReading: Bool { days.contains { $0.nextHRV != nil || $0.nextRHR != nil } }

    /// Plain-English summary of the comparison.
    func caption(_ m: RecoveryMetric) -> String {
        let g = groups(m)
        let heat = g.first(where: { $0.heat })
        let other = g.first(where: { !$0.heat })
        let name = m == .hrv ? String(localized: "morning HRV") : String(localized: "resting heart rate")
        guard hasAnyReading else {
            return String(localized: "No HRV or resting heart rate in Apple Health yet. Wear your Watch or WHOOP to sleep and this fills in by itself.")
        }
        guard let heat else {
            return String(localized: "No sauna or steam days with a reading the next morning yet. Log a few sessions and sleep with your tracker on.")
        }
        guard let other else {
            return String(localized: "Every day with a reading was a heat day, so there's nothing to compare with yet.")
        }
        let a = Int(heat.average.rounded()), b = Int(other.average.rounded())
        var text = String(localized: "After sauna or steam days your \(name) averaged \(a) \(m.unit) (\(heat.count) mornings), against \(b) \(m.unit) on other days (\(other.count) mornings).")
        let diff = heat.average - other.average
        if abs(diff) < max(1, other.average * 0.03) {
            text += " " + String(localized: "That's about the same.")
        } else {
            let better = m.higherIsBetter ? diff > 0 : diff < 0
            let n = Int(abs(diff).rounded())
            let dir = diff > 0 ? String(localized: "\(n) \(m.unit) higher") : String(localized: "\(n) \(m.unit) lower")
            text += " " + (better ? String(localized: "That's \(dir), which usually points to better recovery.")
                                  : String(localized: "That's \(dir), which can mean the heat is still taking something out of you."))
        }
        if heat.count < 5 || other.count < 5 {
            text += " " + String(localized: "Only a few mornings so far, so treat this as an early hint.")
        } else {
            text += " " + String(localized: "A pattern, not proof: sleep, training, alcohol and illness move these numbers too.")
        }
        return text
    }

    private static func demo(from: Date, to: Date, minutes: [Date: Double]) -> [RecoveryDay] {
        let cal = Calendar.current
        var out: [RecoveryDay] = []
        var d = from
        var i = 0
        while d < to {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            let m = minutes[d] ?? (i % 4 == 1 ? 15 + Double(i % 3) * 3 : 0)
            let wobble = sin(Double(i) * 1.3) * 5
            out.append(RecoveryDay(day: d, heatMinutes: m,
                                   nextHRV: i % 7 == 3 ? nil : 46 + wobble + (m > 0 ? 5 : 0),
                                   nextRHR: 56 - wobble * 0.3 - (m > 0 ? 1.5 : 0)))
            d = next
            i += 1
        }
        return out
    }
}

/// The card: two bars (after heat vs other days, with sample sizes), a scatter of minutes vs next morning, a caption.
struct RecoveryCard: View {
    @EnvironmentObject var log: SessionLog
    @StateObject private var model = RecoveryModel()
    @State private var metric: RecoveryMetric = .hrv
    @State private var retries = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Heat days in the sauna's soft ember, other days in the app's calm blue.
    private static var heatStyle: LinearGradient {
        LinearGradient(colors: [HeatKind.sauna.tint, HeatKind.sauna.tint.opacity(0.55)], startPoint: .top, endPoint: .bottom)
    }
    private static var otherStyle: LinearGradient {
        LinearGradient(colors: [SP.accent.opacity(0.85), SP.indigo.opacity(0.55)], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            VStack(alignment: .leading, spacing: SP.s1) {
                Label {
                    Text("Sauna & recovery")
                } icon: {
                    Image(systemName: "flame").foregroundStyle(HeatKind.sauna.tint)
                }
                .font(.headline).foregroundStyle(SP.ink)
                .accessibilityAddTraits(.isHeader)
                Text("Next-morning numbers after heat days, compared with other days.")
                    .font(.footnote).foregroundStyle(SP.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Measure", selection: $metric) {
                ForEach(RecoveryMetric.allCases) { m in Text(m.title).tag(m) }
            }
            .pickerStyle(.segmented)

            if !model.loaded {
                loading
            } else if !model.hasAnyReading {
                noReadings
            } else {
                let groups = model.groups(metric)
                if !groups.isEmpty {
                    bars(groups)
                    scatter
                }
                Text(model.caption(metric))
                    .font(.subheadline).foregroundStyle(SP.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceNote)
                    .font(.caption).foregroundStyle(SP.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .spCard()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: metric)
        .sensoryFeedback(.selection, trigger: metric)
        .sensoryFeedback(.impact(weight: .light), trigger: retries)
        .onAppear { model.load(heat: log.heatEntries) }
    }

    /// Placeholder bars while Apple Health answers (no spinner).
    private var loading: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack(alignment: .bottom, spacing: SP.s8) {
                SPSkeleton(height: 120, width: 64, radius: 8)
                SPSkeleton(height: 90, width: 64, radius: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .bottom)
            SPSkeleton(height: 12)
            SPSkeleton(height: 12, width: 200)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading recovery numbers"))
    }

    /// No HRV or resting heart rate in Health yet: say how it fills in, and offer to look again.
    private var noReadings: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack(alignment: .top, spacing: SP.s3) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(SP.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(SP.accent.opacity(0.12)))
                    .accessibilityHidden(true)
                Text(model.caption(metric))
                    .font(.subheadline).foregroundStyle(SP.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                retries += 1
                model.load(heat: log.heatEntries)
            } label: {
                Label("Check again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SPSecondaryButtonStyle())
        }
    }

    private var sourceNote: String {
        let from = model.sources.isEmpty ? "" : String(localized: "From: \(model.sources.joined(separator: ", ")). ")
        return from + String(localized: "WHOOP's recovery score isn't shared with Apple Health, but the HRV and resting heart rate it measures are, so they count here. HRV is the morning average (midnight to noon).")
    }

    private var axisFont: Font { .system(.caption2, design: .rounded).monospacedDigit() }

    private func bars(_ groups: [RecoveryGroup]) -> some View {
        Chart(groups) { g in
            BarMark(x: .value("Group", g.label), y: .value(metric.unit, g.average), width: .ratio(0.5))
                .foregroundStyle(g.heat ? Self.heatStyle : Self.otherStyle)
                .cornerRadius(8)
                .annotation(position: .top, spacing: 4) {
                    VStack(spacing: 0) {
                        Text("\(Int(g.average.rounded())) \(metric.unit)")
                            .font(.system(.footnote, design: .rounded).weight(.semibold)).monospacedDigit()
                            .foregroundStyle(SP.ink)
                        Text("n = \(g.count)").font(.caption2).monospacedDigit().foregroundStyle(SP.faint)
                    }
                }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel().font(axisFont).foregroundStyle(SP.faint)
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.footnote).foregroundStyle(SP.dim) }
        }
        .frame(height: 170)
        // Two labels share the width: past xxLarge they would collide (the spoken summary covers big text).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(groups.map { "\($0.label): \(Int($0.average.rounded())) \(metric.unit), \($0.count) mornings" }.joined(separator: ". ")))
    }

    private var scatter: some View {
        let pts = model.days.filter { $0.value(metric) != nil }
        return VStack(alignment: .leading, spacing: SP.s2) {
            Text("Minutes of heat vs next morning").font(.footnote.weight(.semibold)).foregroundStyle(SP.dim)
            Chart(pts) { d in
                PointMark(x: .value("Heat minutes", d.heatMinutes), y: .value(metric.unit, d.value(metric) ?? 0))
                    .foregroundStyle(d.isHeatDay ? HeatKind.sauna.tint : SP.accent.opacity(0.55))
                    .symbolSize(d.isHeatDay ? 60 : 30)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("min of sauna / steam that day", alignment: .center)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().font(axisFont).foregroundStyle(SP.faint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().font(axisFont).foregroundStyle(SP.faint)
                }
            }
            .frame(height: 150)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Scatter chart of heat minutes against the next morning's \(metric == .hrv ? "HRV" : "resting heart rate"), \(pts.count) days"))
            HStack(spacing: SP.s4) {
                legendDot(HeatKind.sauna.tint, Text("After heat"))
                legendDot(SP.accent.opacity(0.55), Text("Other days"))
            }
            .font(.caption).foregroundStyle(SP.dim)
            .accessibilityHidden(true)
        }
    }

    private func legendDot(_ color: Color, _ label: Text) -> some View {
        HStack(spacing: SP.s1) {
            Circle().fill(color).frame(width: 8, height: 8)
            label
        }
    }
}
