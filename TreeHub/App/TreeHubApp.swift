import SwiftUI
import UIKit
import SwiftData

@main
struct TreeHubApp: App {
    @State private var tracker = RouteTracker()

    let container: ModelContainer = {
        let schema = Schema([Hug.self, Activity.self])
        if DemoData.isOn {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        // Syncs to your private iCloud when the app is signed with iCloud; otherwise stays on the phone.
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            return c
        }
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) {
            return c
        }
        // Last resort so the app still opens.
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    init() {
        UserDefaults.standard.register(defaults: ["useMetric": false])
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate { RootView() }
                .environment(tracker)
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

enum AppTab: String, Hashable { case home, track, trees, collection }

struct RootView: View {
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @State private var showHugLog = false
    @State private var demoCelebration: CelebrationData?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.forestDeep.ignoresSafeArea()
            Group {
                switch tab {
                case .home: HomeView(tab: $tab, showHugLog: $showHugLog)
                case .track: TrackView(onHug: { showHugLog = true })
                case .trees: TreesView()
                case .collection: CollectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(
                items: [
                    TabBarItem(id: "home", symbol: "house.fill", label: "Home"),
                    TabBarItem(id: "track", symbol: tracker.isActive ? "record.circle" : "figure.walk", label: "Stroll", alert: tracker.isActive),
                    TabBarItem(id: "trees", symbol: "tree.fill", label: "Grove"),
                    TabBarItem(id: "collection", symbol: "sparkles", label: "Collection"),
                ],
                selection: Binding(get: { tab.rawValue }, set: { tab = AppTab(rawValue: $0) ?? .home }),
                centerSymbol: "heart.fill",
                centerLabel: "Log a tree hug",
                centerAction: { showHugLog = true }
            )
        }
        .sheet(isPresented: $showHugLog) {
            HugLogView(editing: nil, strollID: tracker.isActive ? tracker.sessionID : nil)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tracker.persist() }
            if phase == .active { consumePendingAction() }
        }
        .onReceive(NotificationCenter.default.publisher(for: RootboundPending.note)) { _ in
            consumePendingAction()
        }
        .onAppear {
            if tracker.recoveredFromCrash { tab = .track }
            if DemoData.isOn { setUpDemo() }
            consumePendingAction()
        }
        .fullScreenCover(item: $demoCelebration) { c in
            CelebrationView(data: c) { demoCelebration = nil }
        }
    }

    /// Siri / Shortcuts / Control Center actions (RootboundActions.swift).
    private func consumePendingAction() {
        guard let action = RootboundPending.take() else { return }
        switch action {
        case .logHug:
            showHugLog = true
        case .stroll, .hike:
            tab = .track
            guard !tracker.isActive else { return }
            if !tracker.canTrack { tracker.requestPermission(); return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            tracker.start(kind: action == .hike ? .hike : .walk)
        case .home:
            showHugLog = false
            tab = .home
        case .grove:
            showHugLog = false
            tab = .trees
        case .collection:
            showHugLog = false
            tab = .collection
        }
    }

    private func setUpDemo() {
        DemoData.seed(context)
        switch DemoData.argument(after: "-tab") {
        case "track": tab = .track
        case "trees": tab = .trees
        case "collection": tab = .collection
        default: tab = .home
        }
        if ProcessInfo.processInfo.arguments.contains("-hugLog") { showHugLog = true }
        if ProcessInfo.processInfo.arguments.contains("-autostart") {
            tab = .track
            tracker.start(kind: .walk)
        }
        if ProcessInfo.processInfo.arguments.contains("-celebrate") {
            var b = XPBreakdown()
            b.add("Tree hug", 50); b.add("Breathwork 12 min", 60); b.add("Barefoot grounding", 25)
            b.add("Tree selfie", 10); b.add("3-day streak", 30)
            let badges = GameEngine.badges(hugs: [], activities: []).filter { ["barefoot", "dawn", "twelve"].contains($0.id) }
            demoCelebration = CelebrationData(breakdown: b, leaf: LeafType.find("moonlit"), newBadges: badges,
                                              levelBefore: GameEngine.level(for: 400), levelAfter: GameEngine.level(for: 575),
                                              treeName: "Grandpa Oak")
        }
    }
}
