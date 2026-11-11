import SwiftUI
import WidgetKit

// Couch Remote on the watch face: a TV icon and the TV you're controlling. Tap to open the remote.
// Self-contained: reads only the App Group (written by the Watch app and the iPhone app).

@main
struct ClankerrWidgets: WidgetBundle {
    var body: some Widget {
        CouchRemoteComplication()
    }
}

private enum CRShared {
    static let appGroup = "group.com.troydunn.clicker"
    static let tvNameKey = "tvName"
    static let deepLink = URL(string: "couchremote://remote")!

    static func tvName() -> String {
        let name = UserDefaults(suiteName: appGroup)?.string(forKey: tvNameKey) ?? ""
        return name.trimmingCharacters(in: .whitespaces)
    }
}

private enum CRPalette {
    static let magenta = Color(red: 1.0, green: 0.24, blue: 0.62)
    static let violet = Color(red: 0.55, green: 0.33, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
    static let accent = LinearGradient(colors: [magenta, violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CREntry: TimelineEntry {
    let date: Date
    let tvName: String
    var hasTV: Bool { !tvName.isEmpty }
}

struct CRProvider: TimelineProvider {
    func placeholder(in context: Context) -> CREntry { CREntry(date: Date(), tvName: "Living Room TV") }

    func getSnapshot(in context: Context, completion: @escaping (CREntry) -> Void) {
        completion(CREntry(date: Date(), tvName: context.isPreview ? "Living Room TV" : CRShared.tvName()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CREntry>) -> Void) {
        // The apps reload the timeline whenever the TV changes; refresh on our own every hour as a backstop.
        let entry = CREntry(date: Date(), tvName: CRShared.tvName())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CouchRemoteComplication: Widget {
    let kind = "CouchRemoteComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CRProvider()) { entry in
            CRComplicationView(entry: entry)
                .widgetURL(CRShared.deepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Couch Remote")
        .description("Open the remote for your TV.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct CRComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: CREntry

    private var title: String { entry.hasTV ? entry.tvName : "Couch Remote" }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                icon(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                        .widgetAccentable()
                    Text(entry.hasTV ? "Tap for the remote" : "Pair a TV on iPhone")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label(title, systemImage: "tv.fill")
        #if os(watchOS)
        case .accessoryCorner:
            icon(size: 22)
                .widgetLabel { Text(title).font(.system(size: 13, weight: .bold, design: .rounded)) }
        #endif
        default:
            // accessoryCircular
            ZStack {
                AccessoryWidgetBackground()
                icon(size: 24)
            }
            .widgetLabel { Text(title) }
        }
    }

    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        if mode == .fullColor {
            Image(systemName: "tv.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(CRPalette.accent)
        } else {
            Image(systemName: "tv.fill")
                .font(.system(size: size, weight: .black))
                .widgetAccentable()
        }
    }
}
