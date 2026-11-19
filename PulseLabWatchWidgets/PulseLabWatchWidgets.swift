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
        AgreementComplication()
    }
}

private enum Shared {
    static let suite = "group.com.troydunn.pulselab"
    static let key = "watchSnapshot"
    // Same palette as the iPhone app (Lab): Watch = cyan, WHOOP = amber, red accent for the brand mark.
    static let watch = Color(red: 0.25, green: 0.80, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.64, blue: 0.20)
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
    /// Today's Watch vs WHOOP agreement (0–100) and how many metrics agree / were compared.
    var agreeScore: Double?
    var agreeOn = 0
    var agreeOf = 0
    var agreeSplit = ""

    static let placeholder = PulseEntry(recovery: 72, sleepMin: 432, hrv: 61, strain: 11.4, updatedAt: Date(),
                                        agreeScore: 75, agreeOn: 3, agreeOf: 4, agreeSplit: "HRV")

    static func read() -> PulseEntry {
        guard let d = UserDefaults(suiteName: Shared.suite)?.dictionary(forKey: Shared.key) else { return PulseEntry() }
        var e = PulseEntry()
        e.recovery = d["recovery"] as? Double
        e.isWhoop = (d["recoveryKind"] as? String ?? "whoop") == "whoop"
        e.sleepMin = d["sleepMin"] as? Double
        e.hrv = d["hrv"] as? Double
        e.strain = d["strain"] as? Double
        if let t = d["updatedAt"] as? Double { e.updatedAt = Date(timeIntervalSince1970: t) }
        e.agreeScore = d["agreeScore"] as? Double
        e.agreeOn = d["agreeOn"] as? Int ?? 0
        e.agreeOf = d["agreeOf"] as? Int ?? 0
        e.agreeSplit = d["agreeSplit"] as? String ?? ""
        // Yesterday's numbers aren't today's recovery (or agreement): show them as missing after midnight.
        if let u = e.updatedAt, !Calendar.current.isDateInToday(u) {
            e.recovery = nil
            e.agreeScore = nil; e.agreeOn = 0; e.agreeOf = 0; e.agreeSplit = ""
        }
        return e
    }

    var sleepText: String {
        guard let m = sleepMin, m > 0 else { return "—" }
        return "\(Int(m) / 60)h\(String(format: "%02d", Int(m) % 60))"
    }

    /// "WHOOP recovery" or "Watch readiness", for labels and VoiceOver.
    var scoreName: String { isWhoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness") }

    /// Everything on the rectangular complication, in words.
    var spoken: String {
        var parts: [String] = [recovery.map { "\(scoreName) \(Int($0.rounded()))" } ?? String(localized: "No recovery score yet")]
        if let m = sleepMin, m > 0 {
            let t = Duration.seconds(Int(m.rounded()) * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
            parts.append(String(localized: "Sleep \(t)"))
        }
        if let h = hrv { parts.append(String(localized: "HRV \(Int(h.rounded())) milliseconds")) }
        if let s = strain { parts.append(String(localized: "Strain \(s.formatted(.number.precision(.fractionLength(1))))")) }
        return parts.joined(separator: ", ")
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
        guard let r = entry.recovery else { return String(localized: "No recovery score yet") }
        return "\(entry.scoreName) \(Int(r.rounded()))"
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
            Text(verbatim: "\(entry.recovery.map { "\(Int($0.rounded()))%" } ?? "—") · \(entry.sleepText) · HRV \(entry.hrv.map { "\(Int($0.rounded()))" } ?? "—")")
                .accessibilityLabel(entry.spoken)
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
                    Text(entry.isWhoop ? String(localized: "recovery") : String(localized: "readiness"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(entry.isWhoop ? Shared.whoop : Shared.watch)
                }
                Text("Sleep \(entry.sleepText) · HRV \(entry.hrv.map { "\(Int($0.rounded()))" } ?? "—") · Strain \(entry.strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")")
                    .font(.system(size: 12).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.spoken)
        }
    }
}

// MARK: - Agreement

/// Today's Watch vs WHOOP agreement score: circular gauge, corner, rectangular and inline.
struct AgreementComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulseLabAgreement", provider: PulseProvider()) { e in
            AgreementComplicationView(entry: e)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Watch vs WHOOP")
        .description("How closely your Watch and WHOOP agree today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct AgreementComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    private var scoreText: String { entry.agreeScore.map { "\(Int($0))" } ?? "–" }
    private var headline: String {
        entry.agreeOf > 0 ? String(localized: "\(entry.agreeOn) of \(entry.agreeOf) agree") : String(localized: "Waiting for both")
    }
    private var spoken: String {
        guard let a = entry.agreeScore else { return String(localized: "Watch versus WHOOP: no agreement score yet") }
        return String(localized: "Watch versus WHOOP agree \(Int(a)) percent, \(headline)")
    }
    private var gradient: Gradient { Gradient(colors: [Shared.watch, Shared.whoop]) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                Text(scoreText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .widgetCurvesContent()
                    .widgetLabel {
                        Gauge(value: entry.agreeScore ?? 0, in: 0...100) { Text(verbatim: "VS") }
                            .tint(gradient)
                    }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill").font(.system(size: 11, weight: .semibold))
                        Text("Watch vs WHOOP").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Shared.accent)
                    .widgetAccentable()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.agreeScore.map { "\(Int($0))%" } ?? "–")
                            .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(entry.agreeScore.map(band) ?? .secondary)
                        Text(headline).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(entry.agreeOf == 0 ? String(localized: "Open Pulse Lab to sync")
                         : entry.agreeSplit.isEmpty ? String(localized: "Same story today") : String(localized: "Split: \(entry.agreeSplit)"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                Text(verbatim: "VS \(entry.agreeScore.map { "\(Int($0))%" } ?? "–") · \(headline)")
            default:
                Gauge(value: entry.agreeScore ?? 0, in: 0...100) {
                    Text(verbatim: "VS")
                } currentValueLabel: {
                    Text(scoreText).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(gradient)
                .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
