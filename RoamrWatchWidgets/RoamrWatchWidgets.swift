import SwiftUI
import WidgetKit

// Roamr Watch complications: one tap from the watch face to Roamr's Start screen (Start drive, Walk, Ride, Run).
// Data-free on purpose: the Watch app keeps its live numbers in memory from the iPhone, so there is nothing
// shared to read here and no App Group is needed.

@main
struct RoamrWatchWidgets: WidgetBundle {
    var body: some Widget {
        RoamrLauncherComplication()
    }
}

private enum RWC {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.20)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let route = "point.topleft.down.to.point.bottomright.curvepath.fill"
}

struct LauncherEntry: TimelineEntry { let date: Date }

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) { completion(LauncherEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

struct RoamrLauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoamrLauncher", provider: LauncherProvider()) { _ in
            RoamrLauncherView()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Map a trip")
        .description("Opens Roamr to start a drive, walk, ride or run.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct RoamrLauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                Image(systemName: "car.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(RWC.amber)
                    .widgetAccentable()
                    .widgetLabel { Text(verbatim: "Roamr") }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "car.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RWC.amber).widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Roamr").font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(RWC.orange).widgetAccentable()
                        Text("Every mile, mapped").font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                        Text("Tap to start a drive").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label { Text("Roamr · Start a drive") } icon: { Image(systemName: "car.fill") }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: RWC.route)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RWC.amber)
                        .widgetAccentable()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Roamr: start mapping a trip"))
    }
}
