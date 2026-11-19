import AppIntents
import SwiftUI
import WidgetKit

// Couch Remote on the Home Screen: power, volume and mute buttons that work without opening the app
// (iOS 17 interactive widget). Each button runs TVControlKeyIntent, the same intent the Control Center
// controls use, so the key is sent from the app's process to the paired TV. Tapping elsewhere opens the remote.

struct CRHomeEntry: TimelineEntry {
    let date: Date
    let tvName: String
}

struct CRHomeProvider: TimelineProvider {
    private static func name() -> String {
        (UserDefaults(suiteName: "group.com.troydunn.clicker")?.string(forKey: "tvName") ?? "").trimmingCharacters(in: .whitespaces)
    }
    func placeholder(in context: Context) -> CRHomeEntry { CRHomeEntry(date: Date(), tvName: "Living Room TV") }
    func getSnapshot(in context: Context, completion: @escaping (CRHomeEntry) -> Void) {
        completion(CRHomeEntry(date: Date(), tvName: context.isPreview ? "Living Room TV" : Self.name()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CRHomeEntry>) -> Void) {
        // WidgetBridge reloads timelines when the TV changes; hourly is only a backstop.
        completion(Timeline(entries: [CRHomeEntry(date: Date(), tvName: Self.name())], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct CouchRemoteHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CouchRemoteHome", provider: CRHomeProvider()) { entry in
            CRHomeView(entry: entry)
                .widgetURL(URL(string: "couchremote://remote")!)
                .containerBackground(for: .widget) { CRHomeBackground() }
        }
        .configurationDisplayName("TV Remote")
        .description("Power, volume and mute for your TV, right on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum CRHomeLook {
    static let magenta = Color(red: 1.0, green: 0.24, blue: 0.62)
    static let violet = Color(red: 0.55, green: 0.33, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
}

private struct CRHomeBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.024, blue: 0.065)
            RadialGradient(colors: [CRHomeLook.violet.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
            RadialGradient(colors: [CRHomeLook.cyan.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 160)
        }
    }
}

struct CRHomeView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: CRHomeEntry
    private var paired: Bool { !entry.tvName.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if paired {
                if family == .systemMedium {
                    HStack(spacing: 8) { keys }
                } else {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow { key(.power); key(.mute) }
                        GridRow { key(.volumeDown); key(.volumeUp) }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("Open Couch Remote to pair your TV, then these buttons work from here.")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tv.fill").font(.system(size: 13, weight: .black))
                .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(CRHomeLook.cyan) : AnyShapeStyle(.primary))
                .widgetAccentable()
            Text(paired ? entry.tvName : "Couch Remote")
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var keys: some View {
        key(.power); key(.volumeDown); key(.volumeUp); key(.mute)
    }

    private func key(_ k: TVControlKey) -> some View {
        Button(intent: TVControlKeyIntent(key: k)) {
            Image(systemName: Self.symbol(k))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(k == .power && renderingMode == .fullColor ? AnyShapeStyle(CRHomeLook.magenta) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 44)
                .background(Color.white.opacity(renderingMode == .fullColor ? 0.10 : 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .widgetAccentable(k == .power)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(k))
    }

    static func symbol(_ k: TVControlKey) -> String {
        switch k {
        case .power: return "power"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"
        }
    }
    static func label(_ k: TVControlKey) -> String {
        switch k {
        case .power: return "TV power"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        }
    }
}
