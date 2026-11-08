import SwiftUI
import UIKit
import SwiftData

@main
struct TrackHubApp: App {
    @State private var tracker = RouteTracker()

    let container: ModelContainer = {
        let schema = Schema([Activity.self])
        if TrackDemo.isOn {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            return c
        }
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            return c
        }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    init() {
        UserDefaults.standard.register(defaults: ["useMetric": false])
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate { TrackRootView() }
                .environment(tracker)
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

struct TrackRootView: View {
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    /// "track", "history", "stats" or "settings".
    @State private var tab: String = "track"

    private var tabItems: [TabBarItem] {
        [
            TabBarItem(id: "track", symbol: tracker.isActive ? "record.circle" : "location.north.circle.fill",
                       label: "Track", alert: tracker.isActive),
            TabBarItem(id: "history", symbol: "clock.arrow.circlepath", label: "History"),
            TabBarItem(id: "stats", symbol: "chart.bar.fill", label: "Stats"),
            TabBarItem(id: "settings", symbol: "gearshape.fill", label: "Settings"),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.forestDeep.ignoresSafeArea()
            Group {
                switch tab {
                case "history": HistoryView()
                case "stats": StatsView()
                case "settings": TrackSettingsView()
                default: TrackView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            FloatingTabBar(items: tabItems, selection: $tab)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: tab)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tracker.persist() }
        }
        .onAppear {
            if tracker.recoveredFromCrash { tab = "track" }
            if TrackDemo.isOn {
                TrackDemo.seed(context)
                switch TrackDemo.argument(after: "-tab") {
                case "history": tab = "history"
                case "stats": tab = "stats"
                case "settings": tab = "settings"
                default: tab = "track"
                }
                if ProcessInfo.processInfo.arguments.contains("-autostart") { tracker.start(kind: .run) }
                if ProcessInfo.processInfo.arguments.contains("-autodrive") { tracker.start(kind: .drive) }
            }
        }
    }
}
