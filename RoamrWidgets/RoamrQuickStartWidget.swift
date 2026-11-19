import AppIntents
import SwiftUI
import WidgetKit

// Home Screen / Lock Screen widget: start mapping a drive, ride, hike, run or walk in one tap, and log a fill-up.
// Data-free on purpose: the extension has no App Group, so it never reads trips. Each button runs an intent from
// TrackApp/App/RoamrActions.swift, which opens Roamr and starts recording (same path as the Control Center controls).

private enum QS {
    static let background = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.20)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.32)
    static let dim = Color.white.opacity(0.65)
    static let tile = Color.white.opacity(0.09)
    static let gradient = LinearGradient(colors: [amber, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let trackURL = URL(string: "roamr://track")
}

struct QuickStartEntry: TimelineEntry {
    let date: Date
}

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry { QuickStartEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) {
        completion(QuickStartEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        // Nothing here changes over time.
        completion(Timeline(entries: [QuickStartEntry(date: Date())], policy: .never))
    }
}

struct RoamrQuickStartWidget: Widget {
    static let kind = "com.troydunn.roamr.widget.quickstart"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: QuickStartProvider()) { _ in
            QuickStartView()
                .containerBackground(for: .widget) {
                    ZStack {
                        QS.background
                        RadialGradient(colors: [QS.orange.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 180)
                    }
                }
                .widgetURL(QS.trackURL)
        }
        .configurationDisplayName("Map a trip")
        .description("Start mapping a drive, ride, hike, run or walk in one tap, or log a fill-up.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickStartView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(QS.amber)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(verbatim: "ROAMR").font(.system(size: 10, weight: .heavy, design: .rounded)).kerning(1.2)
                    .foregroundStyle(QS.dim)
            }
            Text("Every mile, mapped.")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            driveButton(height: 40)
            HStack(spacing: 6) {
                iconButton(.ride, "bicycle", String(localized: "Start a ride"))
                iconButton(.hike, "figure.hiking", String(localized: "Start a hike"))
                iconButton(.walk, "figure.walk", String(localized: "Start a walk"))
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Text("Drives, rides and hikes on a night map, with MPG from every fill-up.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(QS.dim)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Button(intent: LogGasIntent()) {
                    Label("Log gas", systemImage: "fuelpump.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(QS.gold)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(QS.gold.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Log a fill-up"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                driveButton(height: 44)
                HStack(spacing: 6) {
                    iconButton(.ride, "bicycle", String(localized: "Start a ride"))
                    iconButton(.hike, "figure.hiking", String(localized: "Start a hike"))
                }
                HStack(spacing: 6) {
                    iconButton(.run, "figure.run", String(localized: "Start a run"))
                    iconButton(.walk, "figure.walk", String(localized: "Start a walk"))
                }
            }
            .frame(width: 132)
        }
    }

    private func driveButton(height: CGFloat) -> some View {
        Button(intent: StartRoamrTrackingIntent(kind: .drive)) {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.system(size: 13, weight: .black))
                Text("Start drive").font(.system(size: 13, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(QS.background)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(QS.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Start mapping a drive"))
    }

    private func iconButton(_ kind: RoamrKindOption, _ symbol: String, _ label: String) -> some View {
        Button(intent: StartRoamrTrackingIntent(kind: kind)) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(QS.amber)
                .widgetAccentable()
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(QS.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 20, weight: .bold))
                .widgetAccentable()
        }
        .accessibilityLabel(Text("Open Roamr to map a trip"))
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill").font(.system(size: 18, weight: .bold)).widgetAccentable()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Roamr").font(.system(size: 13, weight: .heavy, design: .rounded)).widgetAccentable()
                Text("Every mile, mapped").font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                Text("Tap to start a trip").font(.system(size: 11, weight: .regular, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
