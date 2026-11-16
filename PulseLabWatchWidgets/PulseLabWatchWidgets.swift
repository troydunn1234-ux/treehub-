import SwiftUI
import WidgetKit

// Pulse Lab Watch complications: a circular recovery gauge and a rectangular summary (plus corner and
// inline). Self-contained: reads the snapshot the Watch app stores in its App Group
// (PulseLabWatch/WatchStore.swift, key "watchSnapshot").

@main
struct PulseLabWatchWidgets: WidgetBundle {
    var body: some Widget {
        RecoveryGaugeComplication()
        SummaryComplication()
    }
}

private enum Shared {
    static let suite = "group.com.troydunn.pulselab"
    static let key = "watchSnapshot"
    // Same palette as the iPhone app (Lab).
    static let good = Color(red: 0.22, green: 0.84, blue: 0.46)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.36, blue: 0.32)
    static let accent = Color(red: 1.00, green: 0.25, blue: 0.36)
}

struct PulseEntry: TimelineEntry {
    var date = Date()
    var recovery: Double?
    var isWhoop = true
    var sleepMin: Double?
    var hrv: Double?
    var strain: Double?
    var updatedAt: Date?

    static let placeholder = PulseEntry(recovery: 72, sleepMin: 432, hrv: 61, strain: 11.4, updatedAt: Date())

    static func read() -> PulseEntry {
        guard let d = UserDefaults(suiteName: Shared.suite)?.dictionary(forKey: Shared.key) else { return PulseEntry() }
        var e = PulseEntry()
        e.recovery = d["recovery"] as? Double
        e.isWhoop = (d["recoveryKind"] as? String ?? "whoop") == "whoop"
        e.sleepMin = d["sleepMin"] as? Double
        e.hrv = d["hrv"] as? Double
        e.strain = d["strain"] as? Double
        if let t = d["updatedAt"] as? Double { e.updatedAt = Date(timeIntervalSince1970: t) }
        // Yesterday's numbers aren't today's recovery: show them as missing after midnight.
        if let u = e.updatedAt, !Calendar.current.isDateInToday(u) { e.recovery = nil }
        return e
    }

    var sleepText: String {
        guard let m = sleepMin, m > 0 else { return "—" }
        return "\(Int(m) / 60)h\(String(format: "%02d", Int(m) % 60))"
    }
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        // The Watch app reloads timelines whenever new numbers arrive; this refresh just rolls over midnight.
        let next = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [.read()], policy: .after(min(next, Date().addingTimeInterval(4 * 3600)))))
    }
}

private func band(_ v: Double) -> Color { v >= 67 ? Shared.good : v >= 34 ? Shared.warn : Shared.bad }

struct RecoveryGaugeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseLabRecovery", provider: PulseProvider()) { e in
            RecoveryGaugeView(entry: e)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery as a gauge.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct RecoveryGaugeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    private var valueText: String { entry.recovery.map { "\(Int($0.rounded()))" } ?? "—" }

    var body: some View {
        switch family {
        case .accessoryCorner:
            Text(valueText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: entry.recovery ?? 0, in: 0...100) { Text("REC") }
                        .tint(Gradient(colors: [Shared.bad, Shared.warn, Shared.good]))
                }
                .accessibilityLabel(label)
        default:
            Gauge(value: entry.recovery ?? 0, in: 0...100) {
                Image(systemName: "heart.fill")
            } currentValueLabel: {
                Text(valueText).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(entry.recovery.map(band) ?? .gray)
            .widgetAccentable()
            .accessibilityLabel(label)
        }
    }

    private var label: String {
        guard let r = entry.recovery else { return String(localized: "Recovery not in yet") }
        return String(localized: "Recovery \(Int(r.rounded())) percent")
    }
}

struct SummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseLabSummary", provider: PulseProvider()) { e in
            SummaryView(entry: e)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Today")
        .description("Recovery, sleep, HRV and strain.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct SummaryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.recovery.map { "\(Int($0.rounded()))%" } ?? "—") · \(entry.sleepText) · HRV \(entry.hrv.map { "\(Int($0.rounded()))" } ?? "—")")
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 11, weight: .semibold))
                    Text("Pulse Lab").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Shared.accent)
                .widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.recovery.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(entry.recovery.map(band) ?? .secondary)
                    Text(entry.isWhoop ? "recovery" : "readiness").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("Sleep \(entry.sleepText) · HRV \(entry.hrv.map { "\(Int($0.rounded()))" } ?? "—") · Strain \(entry.strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")")
                    .font(.system(size: 12).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
