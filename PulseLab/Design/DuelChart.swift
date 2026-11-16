import Charts
import SwiftUI

/// One point on a Watch-vs-WHOOP line chart.
struct DuelPoint: Identifiable, Equatable {
    let day: Date
    let value: Double
    let source: Source
    var id: String { "\(source.rawValue)-\(day.timeIntervalSince1970)" }
}

extension Array where Element == DuelPoint {
    static func from(_ pts: [(Date, Double)], _ s: Source) -> [DuelPoint] { pts.map { DuelPoint(day: $0.0, value: $0.1, source: s) } }
}

/// The signature chart, and the reference for every other chart in the app: two crisp monotone lines
/// (Watch cyan, WHOOP amber), a faint area under the first, optional dashed averages and a personal
/// normal band, hairline grid, unit in the corner, and press-and-drag scrubbing that snaps to a day
/// and shows one tooltip with both values.
struct DuelChart: View {
    let watch: [DuelPoint]
    let whoop: [DuelPoint]
    var unit: String
    var decimals: Int = 0
    var height: CGFloat = 170
    var showAverages = true
    /// Force the y-axis to start at 0 (only for metrics where 0 is meaningful).
    var includeZero = false
    var showPoints = false
    /// When set, only this source is drawn (tap a legend chip to isolate).
    var solo: Source? = nil
    /// Shaded horizontal band (your personal normal range), drawn behind the lines.
    var band: ClosedRange<Double>? = nil

    @State private var selectedDay: Date?

    private var watchShown: [DuelPoint] { solo == .whoop ? [] : watch }
    private var whoopShown: [DuelPoint] { solo == .watch ? [] : whoop }
    private var all: [DuelPoint] { watchShown + whoopShown }

    private var domain: ClosedRange<Double> {
        let v = all.map(\.value)
        guard var lo = v.min(), var hi = v.max() else { return 0...1 }
        if let band { lo = Swift.min(lo, band.lowerBound); hi = Swift.max(hi, band.upperBound) }
        let pad = Swift.max((hi - lo) * 0.2, Swift.max(abs(hi) * 0.02, 0.1))
        let low = includeZero ? Swift.min(0, lo) : lo - pad
        return low...(hi + pad)
    }

    private var areaPoints: [DuelPoint] { watchShown.isEmpty ? whoopShown : watchShown }
    private var areaColor: Color { watchShown.isEmpty ? Lab.whoop : Lab.watch }
    /// Few points: show dots so single readings aren't invisible.
    private var dots: Bool { showPoints || all.count <= 10 }

    var body: some View {
        let d = domain
        let wAvg = Stats.mean(watchShown.map(\.value)), hAvg = Stats.mean(whoopShown.map(\.value))
        let watch = watchShown, whoop = whoopShown
        Chart {
            if let band, let first = all.map(\.day).min(), let last = all.map(\.day).max() {
                RectangleMark(xStart: .value("From", first, unit: .day), xEnd: .value("To", last, unit: .day),
                              yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(Color.white.opacity(0.06))
            }
            ForEach(areaPoints) { p in
                AreaMark(x: .value("Day", p.day, unit: .day),
                         yStart: .value("Base", d.lowerBound),
                         yEnd: .value(unit, p.value))
                    .foregroundStyle(LinearGradient(colors: [areaColor.opacity(0.18), areaColor.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(watch) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "Watch"))
                    .foregroundStyle(Lab.watch)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(whoop) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "WHOOP"))
                    .foregroundStyle(Lab.whoop)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if dots {
                ForEach(all) { p in
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(Lab.color(p.source))
                        .symbolSize(18)
                }
            }
            if showAverages, let wAvg {
                RuleMark(y: .value("Watch avg", wAvg))
                    .foregroundStyle(Lab.watch.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if showAverages, let hAvg {
                RuleMark(y: .value("WHOOP avg", hAvg))
                    .foregroundStyle(Lab.whoop.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let sel = selectedDay {
                RuleMark(x: .value("Selected", sel, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(sel)
                    }
                ForEach(points(on: sel)) { p in
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(Lab.color(p.source))
                        .symbolSize(70)
                }
            }
        }
        .chartYScale(domain: d)
        .chartYAxisLabel(position: .topLeading, alignment: .leading) { LabAxis.unitLabel(unit) }
        .scrubDays(Array(Set(all.map(\.day))).sorted(), selection: $selectedDay)
        .chartXAxis { LabAxis.xDays }
        .chartYAxis { LabAxis.y }
        .frame(height: height)
    }

    private func points(on day: Date) -> [DuelPoint] {
        all.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private func tooltip(_ day: Date) -> some View {
        let pts = points(on: day)
        var lines: [LabChartTooltip.Line] = []
        for s in Source.allCases {
            if let v = pts.first(where: { $0.source == s })?.value {
                lines.append(.init(label: s.label, value: unit.isEmpty ? Lab.fmt(v, decimals) : Lab.fmt(v, decimals) + " " + unit, color: Lab.color(s)))
            }
        }
        return LabChartTooltip(title: LabChartTooltip.dayTitle(day), lines: lines)
    }
}

/// "● WATCH  ● WHOOP" legend chips under a chart. Pass `solo` to make the chips tappable:
/// tapping one isolates that source, tapping again shows both.
struct DuelLegend: View {
    var solo: Binding<Source?>? = nil
    /// Chips only (no hint text), for tight headers.
    var compact = false
    var body: some View {
        HStack(spacing: 8) {
            chip(.watch)
            chip(.whoop)
            if !compact {
                Spacer()
                Text(solo == nil ? "Press and drag to scrub" : "Tap a chip to isolate").font(.caption2).foregroundStyle(Lab.faint)
            }
        }
    }

    @ViewBuilder private func chip(_ s: Source) -> some View {
        if let solo {
            Button {
                Lab.tick()
                withAnimation(.snappy) { solo.wrappedValue = solo.wrappedValue == s ? nil : s }
            } label: {
                SourceChip(source: s)
                    .opacity(solo.wrappedValue == nil || solo.wrappedValue == s ? 1 : 0.35)
                    .overlay(Capsule().strokeBorder(Lab.color(s).opacity(solo.wrappedValue == s ? 0.9 : 0), lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("\(s.name)\(solo.wrappedValue == s ? ", isolated" : "")")
            .accessibilityHint("Tap to show only this tracker")
        } else {
            SourceChip(source: s)
        }
    }
}
