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

    /// Every compared number agrees (two or more): the widget shows a small seal.
    var agreesFully: Bool { agreeOf >= 2 && agreeOn == agreeOf }

    /// The metrics they split on, from the comma-joined names the app hands over ("HRV, Sleep").
    var splitNames: [String] {
        agreeSplit.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Plain words: "HRV differs" / "HRV and Sleep differ" / "Same story today".
    var agreeDetail: String {
        guard agreeOf > 0 else { return String(localized: "Open Pulse Lab to sync") }
        let names = splitNames
        if names.isEmpty { return String(localized: "Same story today") }
        let list = names.formatted(.list(type: .and))
        return names.count == 1 ? String(localized: "\(list) differs") : String(localized: "\(list) differ")
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
    /// The detail line: green when they tell the same story, yellow when they split.
    private var tint: Color {
        guard shown.agreeOf > 0 else { return Palette.faint }
        return shown.splitNames.isEmpty ? Palette.good : Palette.warn
    }

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

    /// "Watch vs WHOOP" in the two data colours (white in tinted / accented Home Screen modes).
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.horizontal.fill").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.accent).widgetAccentable()
            (Text(verbatim: "Watch").foregroundStyle(Palette.watch)
                + Text(verbatim: " vs ").foregroundStyle(Palette.faint)
                + Text(verbatim: "WHOOP").foregroundStyle(Palette.whoop))
                .font(Palette.label(11)).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Same ring as Today in the app: Watch cyan up the left, WHOOP amber up the right, from a heart at the bottom;
    /// the two meet at the top only when they fully agree.
    private func ring(size: CGFloat, line: CGFloat, font: CGFloat) -> some View {
        let p = min(1, max(0, (shown.agreeScore ?? 0) / 100))
        return ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: line)
            ZStack {
                Circle().trim(from: 0, to: 0.5 * p)
                    .stroke(Palette.watch, style: StrokeStyle(lineWidth: line, lineCap: .round))
                Circle().trim(from: 1 - 0.5 * p, to: 1)
                    .stroke(Palette.whoop, style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            .rotationEffect(.degrees(90))
            .widgetAccentable()
            VStack(spacing: 0) {
                Text(scoreText).font(Palette.number(font)).foregroundStyle(shown.agreeScore == nil ? Palette.faint : Palette.text)
                    .minimumScaleFactor(0.6)
                Text("agree").font(Palette.label(10)).foregroundStyle(Palette.faint)
            }
            Image(systemName: "heart.fill")
                .font(.system(size: max(6, line * 0.9), weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: line * 2, height: line * 2)
                .background(Circle().fill(Palette.panel))
                .offset(y: size / 2)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
    }

    /// The headline, with a small seal when every number agrees.
    private func headline(_ font: Font) -> some View {
        HStack(spacing: 4) {
            Text(shown.agreeHeadline).font(font).foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            if shown.agreesFully {
                Image(systemName: "checkmark.seal.fill").font(font).foregroundStyle(Palette.good)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack {
                Spacer(minLength: 0)
                ring(size: 70, line: 7, font: 24)
                Spacer(minLength: 0)
            }
            // Room for the heart badge that sits on the ring's bottom edge.
            .padding(.bottom, 4)
            Spacer(minLength: 0)
            headline(.system(size: 12, weight: .semibold))
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
                headline(.system(size: 17, weight: .bold, design: .rounded))
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
            HStack(spacing: 4) {
                if let s = shown.agreeScore {
                    Text(verbatim: "\(Int(s))%").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Text(shown.agreeHeadline).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if shown.agreesFully {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            Text(shown.agreeDetail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
