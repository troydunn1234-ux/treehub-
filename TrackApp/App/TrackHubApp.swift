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
            TrackRootView()
                .environment(tracker)
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

enum TrackTab: Hashable { case track, history, stats, settings }

struct TrackRootView: View {
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var tab: TrackTab = .track

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.forestDeep.ignoresSafeArea()
            Group {
                switch tab {
                case .track: TrackView()
                case .history: HistoryView()
                case .stats: StatsView()
                case .settings: TrackSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                item(.track, tracker.isActive ? "record.circle" : "location.north.circle.fill", tracker.isActive ? "Live" : "Track")
                item(.history, "clock.arrow.circlepath", "History")
                item(.stats, "chart.bar.fill", "Stats")
                item(.settings, "gearshape.fill", "Settings")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tracker.persist() }
        }
        .onAppear {
            if tracker.recoveredFromCrash { tab = .track }
            if TrackDemo.isOn {
                TrackDemo.seed(context)
                switch TrackDemo.argument(after: "-tab") {
                case "history": tab = .history
                case "stats": tab = .stats
                default: tab = .track
                }
                if ProcessInfo.processInfo.arguments.contains("-autostart") { tracker.start(kind: .run) }
            }
        }
    }

    private func item(_ t: TrackTab, _ symbol: String, _ label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.pulse, isActive: t == .track && tracker.isActive)
                Text(label).font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(tab == t ? Theme.glow : (t == .track && tracker.isActive ? Color.red : Color.white.opacity(0.55)))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(label)")
        .haptic()
    }
}
