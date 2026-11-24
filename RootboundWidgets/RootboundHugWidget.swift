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
    /// The glow follows the light of the day: one entry now and one at each change (dawn, day, golden hour, night)
    /// over the next day. Nothing else changes, and nothing is read.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HugLaunchEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date()
        var dates = [now]
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for hour in [5, 9, 17, 21] {
                if let d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), d > now { dates.append(d) }
            }
        }
        let entries = dates.sorted().prefix(6).map { HugLaunchEntry(date: $0) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }
}

private enum HugPalette {
    static let forestDeep = Color(red: 0.04, green: 0.13, blue: 0.09)
    static let forest = Color(red: 0.08, green: 0.24, blue: 0.16)
    static let leaf = Color(red: 0.36, green: 0.72, blue: 0.42)
    static let glow = Color(red: 0.74, green: 0.96, blue: 0.55)

    /// Sunlight through the leaves, by the hour: peach at dawn, soft sun by day, amber at golden hour, moonlight.
    static func light(at date: Date) -> Color {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9: return Color(red: 1.0, green: 0.80, blue: 0.62)
        case 9..<17: return Color(red: 1.0, green: 0.96, blue: 0.74)
        case 17..<21: return Color(red: 1.0, green: 0.68, blue: 0.36)
        default: return Color(red: 0.64, green: 0.78, blue: 1.0)
        }
    }
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
                    ZStack {
                        LinearGradient(colors: [HugPalette.forest, HugPalette.forestDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                        // Sunlight falling into the forest from the top corner, tinted by the time of day.
                        RadialGradient(colors: [HugPalette.light(at: entry.date).opacity(0.30), .clear],
                                       center: .topTrailing, startRadius: 0, endRadius: 190)
                        Image(systemName: "tree.fill")
                            .font(.system(size: 120, weight: .bold))
                            .foregroundStyle(HugPalette.glow.opacity(0.06))
                            .offset(x: 46, y: 40)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                } else {
                    Color.clear
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Log a hug in Rootbound")
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
                    Text("Log a hug").font(.caption)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Log a hug", systemImage: "tree.fill")
        case .systemMedium:
            HStack(spacing: 14) {
                icon(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log a hug").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                        .widgetAccentable()
                    Text("Snap the tree, pin it on your map and see how you settled. Time it on your Watch for heart rate.")
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
                Text("Log a hug").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                    .widgetAccentable()
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Tap to start").font(.caption).foregroundStyle(.white.opacity(0.75))
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
        .configurationDisplayName("Log a hug")
        .description("Opens Rootbound straight to a new tree hug.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
