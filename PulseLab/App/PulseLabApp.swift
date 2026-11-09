import SwiftUI

@main
struct PulseLabApp: App {
    @State private var store = LabStore.shared

    init() {
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = UIColor(Lab.bg).withAlphaComponent(0.6)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum LabTab: String, CaseIterable, Identifiable {
    case today, sleep, heart, activity, compare, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .today: "waveform.path.ecg"
        case .sleep: "moon.zzz.fill"
        case .heart: "heart.text.square.fill"
        case .activity: "flame.fill"
        case .compare: "chart.xyaxis.line"
        case .settings: "slider.horizontal.3"
        }
    }

    /// `-tab sleep` picks the starting tab (screenshots).
    static var launch: LabTab {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = LabTab(rawValue: args[i + 1]) { return t }
        return .today
    }
}

struct RootView: View {
    @Environment(LabStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab = LabTab.launch

    private var showOnboarding: Bool {
        if ProcessInfo.processInfo.arguments.contains("-onboarding") { return true }
        return !onboarded && !LabStore.isDemo
    }

    var body: some View {
        ZStack {
            LabBackground()
            if showOnboarding {
                OnboardingView { onboarded = true; Task { await store.refresh() } }
                    .transition(.opacity)
            } else {
                TabView(selection: $tab) {
                    ForEach(LabTab.allCases) { t in
                        screen(t)
                            .tabItem { Label(t.title, systemImage: t.symbol) }
                            .tag(t)
                    }
                }
                .tint(Lab.watch)
            }
        }
        .task { if !showOnboarding { await store.refresh() } }
        .onChange(of: phase) { _, p in if p == .active && !showOnboarding { Task { await store.refresh() } } }
    }

    @ViewBuilder private func screen(_ t: LabTab) -> some View {
        ZStack {
            LabBackground()
            switch t {
            case .today: TodayScreen()
            case .sleep: SleepScreen()
            case .heart: HeartScreen()
            case .activity: ActivityScreen()
            case .compare: CompareScreen()
            case .settings: SettingsScreen()
            }
        }
    }
}

/// Scroll container every tab uses: title, pull-to-refresh, bottom padding for the tab bar.
struct LabScroll<Content: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var content: Content
    @Environment(LabStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    ScreenTitle(kicker: kicker, title: title)
                    if store.loading { ProgressView().tint(Lab.watch) }
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
    }
}
