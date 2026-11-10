import SwiftUI

@main
struct PulseLabApp: App {
    @State private var store = LabStore.shared

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
    var title: String {
        switch self {
        case .activity: "Moves"
        case .compare: "VS"
        default: rawValue.capitalized
        }
    }
    var dockTitle: String { title.uppercased() }
    var symbol: String {
        switch self {
        case .today: "waveform.path.ecg"
        case .sleep: "moon.zzz.fill"
        case .heart: "heart.text.square.fill"
        case .activity: "flame.fill"
        case .compare: "bolt.horizontal.fill"
        case .settings: "slider.horizontal.3"
        }
    }

    /// `-tab sleep` picks the starting tab (screenshots).
    static var launch: LabTab {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return .today }
        return named(args[i + 1]) ?? .today
    }

    /// Accepts both new names (moves, vs) and the old ones (activity, compare).
    static func named(_ s: String) -> LabTab? {
        switch s.lowercased() {
        case "moves": .activity
        case "vs": .compare
        default: LabTab(rawValue: s.lowercased())
        }
    }
}

struct RootView: View {
    @Environment(LabStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab = LabTab.launch
    @State private var lastMain = LabTab.launch == .settings ? LabTab.today : LabTab.launch
    @State private var splash = true

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
                ZStack {
                    screen(tab)
                        .id(tab)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 14)),
                            removal: .opacity))
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if tab != .settings {
                        LabDock(tab: $tab).padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .environment(\.labNav, LabNav(
                    openSettings: { withAnimation(.snappy) { tab = .settings } },
                    closeSettings: { withAnimation(.snappy) { tab = lastMain } }))
                .onChange(of: tab) { _, t in
                    if t != .settings { lastMain = t }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .onChange(of: store.jump) { _, t in
                    guard let t else { return }
                    withAnimation(.snappy) { tab = t }
                    store.jump = nil
                }
                .sheet(item: Binding(get: { store.detail }, set: { store.detail = $0 })) { m in
                    MetricDetailSheet(metric: m)
                        .environment(store)
                        .presentationDetents([.large])
                        .presentationBackground(Lab.bg)
                }
            }
            if splash && !reduceMotion {
                LaunchSplash { splash = false }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .tint(Lab.watch)
        .overlay(alignment: .top) { ToastView() }
        .task {
            #if DEBUG
            Stats.selfCheck()
            #endif
            if !showOnboarding { await store.refresh() }
        }
        .onChange(of: phase) { _, p in if p == .active && !showOnboarding { Task { await store.refresh() } } }
    }

    @ViewBuilder private func screen(_ t: LabTab) -> some View {
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

/// Scroll container every tab uses: title, pull-to-refresh, bottom padding for the tab bar.
struct LabScroll<Content: View>: View {
    let kicker: String
    let title: String
    /// Settings always shows its content; data tabs swap in loading / empty states.
    var showsStates = true
    @ViewBuilder var content: Content
    @Environment(LabStore.self) private var store
    @Environment(\.labNav) private var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenTitle(kicker: kicker, title: title)
                    VStack(alignment: .trailing, spacing: 10) {
                        if showsStates {
                            HeaderIconButton(symbol: "gearshape.fill", label: "Settings", action: nav.openSettings)
                        } else {
                            HeaderIconButton(symbol: "xmark", label: "Close settings", action: nav.closeSettings)
                        }
                        SyncPill()
                    }
                }
                if showsStates && !store.hasAnyData {
                    if store.loading || (!store.loadedOnce && store.healthAsked) {
                        SkeletonStack()
                    } else {
                        LabEmptyState.forStore(store)
                    }
                } else {
                    content
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
    }
}
