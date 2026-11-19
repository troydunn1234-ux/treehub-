import SwiftUI
import WidgetKit

// Pulse Lab's signature on the Home Screen and Lock Screen: today's Watch vs WHOOP agreement score (resting HR,
// HRV, sleep and strain), from the numbers the app hands over in the App Group (PulseLab/Data/WidgetBridge.swift).

struct AgreementWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.troydunn.pulselab.agreement", provider: AgreementProvider()) { entry in
            AgreementView(snap: entry.snap)
                .containerBackground(for: .widget) { WidgetBackdrop() }
                .widgetURL(Bridge.deepLink)
        }
        .configurationDisplayName("Watch vs WHOOP")
        .description("How closely your Apple Watch and WHOOP agree today on resting HR, HRV, sleep and strain.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AgreementProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadyEntry { ReadyEntry(date: Date(), snap: .agreementPlaceholder) }

    func getSnapshot(in context: Context, completion: @escaping (ReadyEntry) -> Void) {
        let snap = Bridge.read()
        completion(ReadyEntry(date: Date(), snap: context.isPreview && snap.agreeOf == 0 ? .agreementPlaceholder : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadyEntry>) -> Void) {
        // The app reloads timelines after every sync; this refresh rolls the score over at midnight.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        let next = min(midnight, Date().addingTimeInterval(3600))
        completion(Timeline(entries: [ReadyEntry(date: Date(), snap: Bridge.read())], policy: .after(next)))
    }
}

extension Bridge.Snapshot {
    static let agreementPlaceholder: Bridge.Snapshot = {
        var s = Bridge.Snapshot.placeholder
        s.agreeScore = 75
        s.agreeOn = 3
        s.agreeOf = 4
        s.agreeSplit = "HRV"
        return s
    }()

    /// "3 of 4 agree" / "Waiting for both trackers".
    var agreeHeadline: String {
        guard agreeOf > 0 else { return String(localized: "Waiting for both trackers") }
        return String(localized: "\(agreeOn) of \(agreeOf) agree")
    }

    var agreeDetail: String {
        guard agreeOf > 0 else { return String(localized: "Open Pulse Lab to sync") }
        return agreeSplit.isEmpty ? String(localized: "Same story today") : String(localized: "Split: \(agreeSplit)")
    }

    var agreeSpoken: String {
        guard let s = agreeScore else { return String(localized: "Watch versus WHOOP: no agreement score yet") }
        return String(localized: "Watch versus WHOOP agree \(Int(s)) percent today, \(agreeHeadline). \(agreeDetail)")
    }
}

struct AgreementView: View {
    @Environment(\.widgetFamily) private var family
    let snap: Bridge.Snapshot

    private var shown: Bridge.Snapshot { snap }
    private var scoreText: String { shown.agreeScore.map { "\(Int($0))" } ?? "–" }
    private var tint: Color { shown.agreeScore.map(Palette.band) ?? Palette.faint }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Text(verbatim: "VS \(shown.agreeScore.map { "\(Int($0))%" } ?? "–") · \(shown.agreeHeadline)")
            case .systemMedium: medium
            default: small
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.agreeSpoken)
    }

    // MARK: Home Screen

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.horizontal.fill").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.accent).widgetAccentable()
            Text("Watch vs WHOOP").font(Palette.label(11)).foregroundStyle(Palette.dim).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func ring(size: CGFloat, line: CGFloat, font: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat((shown.agreeScore ?? 0) / 100))
                .stroke(LinearGradient(colors: [Palette.watch, Palette.whoop], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                Text(scoreText).font(Palette.number(font)).foregroundStyle(shown.agreeScore == nil ? Palette.faint : Palette.text)
                    .minimumScaleFactor(0.6)
                Text("agree").font(Palette.label(10)).foregroundStyle(Palette.faint)
            }
        }
        .frame(width: size, height: size)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack {
                Spacer(minLength: 0)
                ring(size: 70, line: 7, font: 24)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(shown.agreeHeadline).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(shown.agreeDetail).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            ring(size: 92, line: 8, font: 30)
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(shown.agreeHeadline).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(shown.agreeDetail).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    .lineLimit(2)
                Text("Resting HR · HRV · Sleep · Strain").font(Palette.label(10)).foregroundStyle(Palette.faint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let t = shown.updatedAt {
                    Text("Synced \(t, style: .relative) ago").font(Palette.label(10).monospacedDigit()).foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: shown.agreeScore ?? 0, in: 0...100) {
            Text(verbatim: "VS")
        } currentValueLabel: {
            Text(scoreText).font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "Watch vs WHOOP").font(.system(size: 13, weight: .bold)).widgetAccentable()
            Text(shown.agreeScore.map { String(localized: "\(Int($0))% agree · \(shown.agreeHeadline)") } ?? shown.agreeHeadline)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(shown.agreeDetail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
