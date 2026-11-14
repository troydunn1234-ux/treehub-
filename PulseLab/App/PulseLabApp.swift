import SwiftUI
import SwiftData

@main
struct PulseLabApp: App {
    @State private var store = LabStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .modelContainer(for: [Supplement.self, SuppDose.self])
        }
    }
}

enum LabTab: String, CaseIterable, Identifiable {
    case today, sleep, heart, activity, stack, compare, settings
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
        case .stack: "pills.fill"
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
    @ObservedObject private var unlock = Unlock.shared
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
        .paywallHost(spec: PulseLabPro.spec)
        .overlay(alignment: .top) { ToastView() }
        .task {
            #if DEBUG
            Stats.selfCheck()
            #endif
            if !showOnboarding { await store.refresh() }
        }
        .onChange(of: phase) { _, p in
            if p == .active && !showOnboarding { Task { await store.refresh() } }
            if p == .active { openPendingTab() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PulseLabPending.note)) { _ in openPendingTab() }
        .onAppear { openPendingTab() }
        .onOpenURL(perform: open)
    }

    /// Siri / Shortcuts / Control Center "open a section" (PulseLabActions.swift).
    private func openPendingTab() {
        guard let name = PulseLabPending.take(), let t = LabTab.named(name) else { return }
        withAnimation(.snappy) { tab = t }
    }

    /// `pulselab://today` (widget tap) jumps to Today. `pulselab://whoop` is the WHOOP OAuth
    /// callback, consumed by ASWebAuthenticationSession, so anything else is ignored here.
    private func open(_ url: URL) {
        guard url.scheme?.lowercased() == "pulselab", let host = url.host?.lowercased() else { return }
        guard host != "whoop", let t = LabTab.named(host) else { return }
        withAnimation(.snappy) { tab = t }
    }

    @ViewBuilder private func screen(_ t: LabTab) -> some View {
        switch t {
        case .today: TodayScreen()
        case .sleep: SleepScreen()
        case .heart: HeartScreen()
        case .activity: ActivityScreen()
        case .compare: if unlock.isPro { CompareScreen() } else { ProTeaser() }
        case .stack: SuppsView()
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


/// Pulse Lab Pro: what the one-time unlock contains.
enum PulseLabPro {
    static let spec = PaywallSpec(
        appName: "Pulse Lab",
        headline: "Settle it: Watch vs WHOOP.",
        tagline: "The full head-to-head lab, 90 days of history and shareable results. One payment, no subscription.",
        tint: Lab.watch, tint2: Lab.violet,
        features: [
            .init(icon: "bolt.horizontal.fill", title: "The VS tab", detail: "Day-by-day agreement scores for resting HR, HRV, sleep, SpO₂, respiratory rate, temperature and calories — and who's winning."),
            .init(icon: "calendar", title: "90-day history", detail: "Trends over three months instead of one, on every screen."),
            .init(icon: "square.and.arrow.up", title: "Share VS cards", detail: "Post the scoreboard as a clean image."),
            .init(icon: "tablecells", title: "CSV export", detail: "Every number Pulse Lab pulled, for your own spreadsheet."),
        ],
        freeNote: "Today, Sleep, Heart and Moves — with Watch and WHOOP side by side for 30 days — stay free.",
        privacyURL: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/pulselab/PRIVACY.md")
    )
}

/// A Pro screen, blurred, with the unlock on top. Defaults to the VS tab; `TrustScreen` reuses it.
struct ProTeaser<Content: View>: View {
    var symbol = "bolt.horizontal.fill"
    var title = "VS is Pro"
    var message = "The full Watch-vs-WHOOP scoreboard: which tracker agrees, where they split, and by how much."
    var context = "The VS lab"
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content.blur(radius: 14).allowsHitTesting(false).accessibilityHidden(true)
            LinearGradient(colors: [Lab.bg.opacity(0.2), Lab.bg.opacity(0.9)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 34, weight: .black)).foregroundStyle(Lab.watch)
                Text(title).font(Lab.display(28, .heavy)).foregroundStyle(Lab.text)
                Text(message)
                    .font(.system(size: 15, design: .rounded)).foregroundStyle(Lab.dim).multilineTextAlignment(.center)
                Button { Unlock.shared.gate(context) } label: {
                    Text("See what's inside").font(Lab.display(16, .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 13)
                        .background(Capsule().fill(Lab.watch))
                }
                .buttonStyle(PressScale())
            }
            .padding(28)
        }
    }
}

extension ProTeaser where Content == CompareScreen {
    /// The original VS-tab teaser.
    init() { self.init(content: { CompareScreen() }) }
}
