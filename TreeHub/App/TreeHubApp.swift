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
            RootView()
                .environment(tracker)
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable { case home, track, trees, collection }

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
                case .track: TrackView()
                case .trees: TreesView()
                case .collection: CollectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(tab: $tab, recording: tracker.isActive) { showHugLog = true }
        }
        .sheet(isPresented: $showHugLog) {
            HugLogView(editing: nil)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tracker.persist() }
        }
        .onAppear {
            if tracker.recoveredFromCrash { tab = .track }
            if DemoData.isOn { setUpDemo() }
        }
        .fullScreenCover(item: $demoCelebration) { c in
            CelebrationView(data: c) { demoCelebration = nil }
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
            tracker.start(kind: .run)
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

struct TabBar: View {
    @Binding var tab: AppTab
    var recording: Bool
    var onHug: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "house.fill", "Home")
            item(.track, recording ? "record.circle" : "location.north.line.fill", recording ? "Live" : "Track")
            Button(action: onHug) {
                ZStack {
                    Circle().fill(Theme.leafGradient).frame(width: 64, height: 64)
                        .shadow(color: Theme.glow.opacity(0.6), radius: 14)
                    Image(systemName: "tree.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.forestDeep)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.forestDeep, Theme.gold)
                        .offset(x: 20, y: -20)
                }
            }
            .buttonStyle(.plain)
            .haptic(.medium)
            .offset(y: -18)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Log a tree hug")
            item(.trees, "tree.circle.fill", "Grove")
            item(.collection, "sparkles", "Collection")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func item(_ t: AppTab, _ symbol: String, _ label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.pulse, isActive: t == .track && recording)
                Text(label).font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(tab == t ? Theme.glow : (t == .track && recording ? Color.red : Color.white.opacity(0.55)))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .haptic()
    }
}
