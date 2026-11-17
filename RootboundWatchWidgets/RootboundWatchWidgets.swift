import SwiftUI
import WidgetKit

// Rootbound complication: tap to start a hug on the Watch (opens rootboundwatch://hug).

struct HugEntry: TimelineEntry {
    let date: Date
}

struct HugProvider: TimelineProvider {
    func placeholder(in context: Context) -> HugEntry { HugEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (HugEntry) -> Void) { completion(HugEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HugEntry>) -> Void) {
        completion(Timeline(entries: [HugEntry(date: Date())], policy: .never))
    }
}

struct StartHugComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HugEntry
    private let glow = Color(red: 0.74, green: 0.96, blue: 0.55)

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "tree.fill").font(.title3).foregroundStyle(glow)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rootbound").font(.system(.headline, design: .rounded))
                            .widgetAccentable()
                        Text("Tap to start a hug").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label("Start hug", systemImage: "tree.fill")
            case .accessoryCorner:
                Image(systemName: "tree.fill").font(.title3).foregroundStyle(glow)
                    .widgetAccentable()
                    .widgetLabel("Hug")
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "tree.fill").font(.title3).foregroundStyle(glow)
                        .widgetAccentable()
                }
            }
        }
        .widgetURL(URL(string: "rootboundwatch://hug"))
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel("Start a tree hug")
    }
}

@main
struct RootboundWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RootboundStartHug", provider: HugProvider()) { entry in
            StartHugComplicationView(entry: entry)
        }
        .configurationDisplayName("Start hug")
        .description("Tap to start timing a tree hug with live heart rate.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
