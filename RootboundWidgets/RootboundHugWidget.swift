import SwiftUI
import WidgetKit

// "Hug a tree": Home Screen and Lock Screen widget that opens Rootbound's hug logger (rootbound://hug, handled in
// TreeHubApp.onOpenURL). It shows no hug data: this extension has no App Group, so it can't read the app's hugs.

struct HugLaunchEntry: TimelineEntry {
    let date: Date
}

struct HugLaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> HugLaunchEntry { HugLaunchEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (HugLaunchEntry) -> Void) { completion(HugLaunchEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HugLaunchEntry>) -> Void) {
        completion(Timeline(entries: [HugLaunchEntry(date: Date())], policy: .never))
    }
}

private enum HugPalette {
    static let forestDeep = Color(red: 0.04, green: 0.13, blue: 0.09)
    static let forest = Color(red: 0.08, green: 0.24, blue: 0.16)
    static let leaf = Color(red: 0.36, green: 0.72, blue: 0.42)
    static let glow = Color(red: 0.74, green: 0.96, blue: 0.55)
}

struct HugLaunchView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HugLaunchEntry

    var body: some View {
        content
            .widgetURL(URL(string: "rootbound://hug"))
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    LinearGradient(colors: [HugPalette.forest, HugPalette.forestDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Color.clear
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Log a tree hug in Rootbound")
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tree.fill").font(.title3).widgetAccentable()
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "tree.fill").font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Rootbound").font(.system(.headline, design: .rounded)).widgetAccentable()
                    Text("Log a tree hug").font(.caption)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Log a tree hug", systemImage: "tree.fill")
        case .systemMedium:
            HStack(spacing: 14) {
                icon(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hug a tree").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                        .widgetAccentable()
                    Text("Snap it, pin it on your tree map and see how you felt. Time it on your Watch for heart rate.")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                icon(size: 44)
                Spacer(minLength: 0)
                Text("Hug a tree").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                    .widgetAccentable()
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Tap to log it").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: "tree.fill")
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(HugPalette.forestDeep) : AnyShapeStyle(.primary))
            .frame(width: size, height: size)
            .background(Circle().fill(renderingMode == .fullColor
                                      ? AnyShapeStyle(LinearGradient(colors: [HugPalette.glow, HugPalette.leaf], startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(.white.opacity(0.2))))
            .widgetAccentable()
    }
}

struct RootboundHugWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RootboundHugWidget", provider: HugLaunchProvider()) { entry in
            HugLaunchView(entry: entry)
        }
        .configurationDisplayName("Hug a tree")
        .description("Opens Rootbound straight to a new tree hug.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
