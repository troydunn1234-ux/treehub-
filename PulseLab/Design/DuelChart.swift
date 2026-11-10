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

/// The signature chart: two glowing Catmull-Rom lines (wide soft line under a crisp one), an area
/// fading out under the Watch line, y-axis fitted to the data, and press-and-drag scrubbing with a
/// crosshair + glass tooltip + haptic ticks.
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

    @State private var rawSelection: Date?
    @State private var selectedDay: Date?

    private var watchShown: [DuelPoint] { solo == .whoop ? [] : watch }
    private var whoopShown: [DuelPoint] { solo == .watch ? [] : whoop }
    private var all: [DuelPoint] { watchShown + whoopShown }

    private var domain: ClosedRange<Double> {
        let v = all.map(\.value)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = Swift.max((hi - lo) * 0.2, Swift.max(abs(hi) * 0.02, 0.1))
        let low = includeZero ? Swift.min(0, lo) : lo - pad
        return low...(hi + pad)
    }

    private var areaPoints: [DuelPoint] { watchShown.isEmpty ? whoopShown : watchShown }
    private var areaColor: Color { watchShown.isEmpty ? Lab.whoop : Lab.watch }

    var body: some View {
        let d = domain
        let wAvg = Stats.mean(watchShown.map(\.value)), hAvg = Stats.mean(whoopShown.map(\.value))
        let watch = watchShown, whoop = whoopShown
        Chart {
            ForEach(areaPoints) { p in
                AreaMark(x: .value("Day", p.day, unit: .day),
                         yStart: .value("Base", d.lowerBound),
                         yEnd: .value(unit, p.value))
                    .foregroundStyle(LinearGradient(colors: [areaColor.opacity(0.32), areaColor.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(watch) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "Watch glow"))
                    .foregroundStyle(Lab.watch.opacity(0.16))
                    .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "Watch"))
                    .foregroundStyle(Lab.watch)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(whoop) { p in
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "WHOOP glow"))
                    .foregroundStyle(Lab.whoop.opacity(0.16))
                    .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value), series: .value("S", "WHOOP"))
                    .foregroundStyle(Lab.whoop)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            if showPoints {
                ForEach(all) { p in
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(Lab.color(p.source))
                        .symbolSize(16)
                }
            }
            if showAverages, let wAvg {
                RuleMark(y: .value("Watch avg", wAvg))
                    .foregroundStyle(Lab.watch.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if showAverages, let hAvg {
                RuleMark(y: .value("WHOOP avg", hAvg))
                    .foregroundStyle(Lab.whoop.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let sel = selectedDay {
                RuleMark(x: .value("Selected", sel, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(sel)
                    }
                ForEach(points(on: sel)) { p in
                    PointMark(x: .value("Day", p.day, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(Lab.color(p.source))
                        .symbolSize(90)
                }
            }
        }
        .chartYScale(domain: d)
        .chartYAxisLabel(position: .topLeading, alignment: .leading) {
            Text(unit.uppercased()).font(Lab.label(7)).tracking(1).foregroundStyle(Lab.faint)
        }
        .chartXSelection(value: $rawSelection)
        .chartXAxis { LabAxis.xDays }
        .chartYAxis { LabAxis.y }
        .frame(height: height)
        .onChange(of: rawSelection) { _, raw in
            let snapped = raw.flatMap(nearestDay)
            if snapped != selectedDay {
                selectedDay = snapped
                if snapped != nil { UISelectionFeedbackGenerator().selectionChanged() }
            }
        }
    }

    private func nearestDay(_ d: Date) -> Date? {
        all.min { abs($0.day.timeIntervalSince(d)) < abs($1.day.timeIntervalSince(d)) }?.day
    }

    private func points(on day: Date) -> [DuelPoint] {
        all.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private func tooltip(_ day: Date) -> some View {
        let pts = points(on: day)
        let w = pts.first { $0.source == .watch }?.value
        let h = pts.first { $0.source == .whoop }?.value
        return VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                .font(Lab.label(8)).tracking(1).foregroundStyle(Lab.dim)
            HStack(spacing: 10) {
                valueChip(w, .watch)
                valueChip(h, .whoop)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
    }

    @ViewBuilder private func valueChip(_ v: Double?, _ s: Source) -> some View {
        if let v {
            HStack(spacing: 3) {
                Circle().fill(Lab.color(s)).frame(width: 5, height: 5)
                Text(v.formatted(.number.precision(.fractionLength(decimals))))
                    .font(Lab.number(15, .black)).foregroundStyle(Lab.color(s))
                Text(unit).font(Lab.label(7)).foregroundStyle(Lab.faint)
            }
        }
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
                Text(solo == nil ? "PRESS & DRAG TO SCRUB" : "TAP A CHIP TO ISOLATE").font(Lab.label(7)).tracking(1).foregroundStyle(Lab.faint)
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
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("\(s.name)\(solo.wrappedValue == s ? ", isolated" : "")")
            .accessibilityHint("Tap to show only this tracker")
        } else {
            SourceChip(source: s)
        }
    }
}
