import SwiftUI
import UIKit
import SwiftData

@main
struct TreeHubApp: App {
    @State private var tracker = RouteTracker()

    let container: ModelContainer = TreeHubApp.makeContainer()

    /// Rootbound's one store. The app always opens `LocalStore.url` (never pass `storeURL` outside tests):
    /// RootboundTests/DataSafetyTests.swift reopens a store written at a temporary LocalStore-like path through this
    /// same code, and .github/scripts/data_guard.py refuses a build that changes the location.
    static func makeContainer(storeURL: URL = LocalStore.url, demo: Bool = DemoData.isOn) -> ModelContainer {
        let schema = Schema([Hug.self, Activity.self])
        if demo {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        // Syncs to your private iCloud when the app is signed with iCloud; otherwise stays on the phone.
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .automatic)) {
            return c
        }
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)) {
            return c
        }
        // Last resort so the app still opens.
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    init() {
        UserDefaults.standard.register(defaults: ["useMetric": false])
        // Hugs timed on the Rootbound Watch app arrive here (WatchHugs.swift).
        WatchHugInbox.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate { RootView() }
                // Rootbound Pro: "-demo -paywall" (review screenshot) and Unlock.shared.gate(...) open the paywall here.
                .paywallHost(spec: RootboundPro.spec)
                .environment(tracker)
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

enum AppTab: String, Hashable { case home, trees, collection }

struct WatchHugLog: Identifiable {
    let id = UUID()
    let hug: WatchHug
    let treeID: UUID?
}

struct RootView: View {
    /// Only the location-permission helper now (onboarding); Rootbound no longer records walks (Roamr does).
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @State private var tab: AppTab = .home
    @State private var showHugLog = false
    @State private var demoCelebration: CelebrationData?
    @ObservedObject private var watchInbox = WatchHugInbox.shared
    /// "Hug from Watch — pick tree", then the hug logger filled in with the Watch data.
    @State private var watchPrompt: WatchHug?
    @State private var watchLog: WatchHugLog?
    /// Hugs brought back after the Nov 15 storage mix-up (HugRescue), shown once.
    @State private var rescueReport: HugRescue.Report?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.forestDeep.ignoresSafeArea()
            Group {
                switch tab {
                case .home: HomeView(tab: $tab, showHugLog: $showHugLog, openWatchHug: openWatchHug)
                case .trees: TreesView()
                case .collection: CollectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(
                items: [
                    TabBarItem(id: "home", symbol: "house.fill", label: "Home"),
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
            HugLogView(editing: nil)
        }
        // Once after this update: bring back hugs saved in the wrong place on Nov 15.
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            if let report = await HugRescue.runOnce(in: context) { rescueReport = report }
        }
        .sheet(item: $rescueReport) { report in
            HugRescueSheet(report: report)
        }
        .sheet(item: $watchPrompt) { h in
            WatchHugPrompt(hug: h, onPick: { tree in
                watchPrompt = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { watchLog = WatchHugLog(hug: h, treeID: tree) }
            }, onDiscard: {
                watchInbox.remove(h.id)
                watchPrompt = nil
            })
        }
        .sheet(item: $watchLog) { w in
            HugLogView(editing: nil, watchHug: w.hug, preselectTree: w.treeID)
        }
        .onChange(of: watchInbox.pending.count) { old, new in if new > old { openWatchHug() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { RootboundWellness.publish(hugs: hugs) }
            if phase == .active {
                consumePendingAction(); RootboundWellness.publish(hugs: hugs); NatureRollStore.shared.scanIfAllowed()
                // Walks from Roamr / Apple Health onto the hugs they passed (no prompt).
                Task { await RoamrWalks.sync(hugs, context: context) }
            }
        }
        // Share hugs with Still Pointz (Shared/Wellness/WellnessBridge.swift).
        .onChange(of: hugs.count) { _, _ in RootboundWellness.publish(hugs: hugs) }
        .onReceive(NotificationCenter.default.publisher(for: RootboundPending.note)) { _ in
            consumePendingAction()
        }
        // rootbound://friends?c=RB1-… (a friend's shared trees, from a link or their QR code)
        .onOpenURL { url in
            // From Still Pointz: rootbound://hug opens the hug logger, rootbound://home just opens Home.
            if url.scheme == FriendShare.scheme, url.host == "hug" {
                if !showHugLog { tab = .home; showHugLog = true }
                return
            }
            if url.scheme == FriendShare.scheme, url.host == "home" { return }
            // rootbound://tree?id=<tree id>: that tree's page (back from a Still Pointz breath with it).
            if url.scheme == FriendShare.scheme, url.host == "tree" {
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:))
                showHugLog = false
                tab = .trees
                TreeBreaths.pendingTreeID = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: TreeBreaths.openTree, object: nil)
                }
                return
            }
            guard url.scheme == FriendShare.scheme, url.host == "friends",
                  let c = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value
            else { return }
            showHugLog = false
            FriendShare.pendingCode = c
            tab = .trees
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: FriendShare.incoming, object: nil)
            }
        }
        .onAppear {
            saveLeftoverStroll()
            if !DemoData.isOn { Task { await RoamrWalks.sync(hugs, context: context) } }
            if DemoData.isOn { setUpDemo() }
            consumePendingAction()
            if !DemoData.isOn { openWatchHug() }
        }
        .fullScreenCover(item: $demoCelebration) { c in
            CelebrationView(data: c) { demoCelebration = nil }
        }
    }

    /// Shows the newest Watch hug that still needs a tree (unless another sheet is already up).
    private func openWatchHug() {
        guard let h = watchInbox.pending.first, watchPrompt == nil, watchLog == nil, !showHugLog else { return }
        watchPrompt = h
    }

    /// Siri / Shortcuts / Control Center actions (RootboundActions.swift).
    private func consumePendingAction() {
        guard let action = RootboundPending.take() else { return }
        switch action {
        case .logHug:
            showHugLog = true
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

    /// A stroll that was still recording when Rootbound stopped recording walks: save it so nothing is lost
    /// (it shows under Settings › Past strolls).
    private func saveLeftoverStroll() {
        guard tracker.isActive, !DemoData.isOn, let a = tracker.finish(trimIdle: true) else { return }
        if a.distanceM > 10 || a.end.timeIntervalSince(a.start) > 60 {
            context.insert(a)
            try? context.save()
        }
    }

    private func setUpDemo() {
        DemoData.seed(context)
        switch DemoData.argument(after: "-tab") {
        case "trees": tab = .trees
        case "collection": tab = .collection
        default: tab = .home
        }
        if ProcessInfo.processInfo.arguments.contains("-hugLog") { showHugLog = true }
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
