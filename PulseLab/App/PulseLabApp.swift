import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct PulseLabApp: App {
    @UIApplicationDelegateAdaptor(PulseLabAppDelegate.self) private var appDelegate
    @State private var store = LabStore.shared
    private let container = CloudSync.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .modelContainer(container)
        }
    }
}

/// Background freshness: Health observer queries (woken by background delivery) and a periodic
/// BGAppRefreshTask that also pulls WHOOP, so widgets and the app are current before you open it.
final class PulseLabAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let refreshID = "com.troydunn.pulselab.refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Self.handle(task)
        }
        // Observer queries must be running whenever iOS wakes the app for new Health data.
        MainActor.assumeIsolated { LabStore.shared.startLiveUpdates() }
        UNUserNotificationCenter.current().delegate = self
        WatchSync.shared.activate()
        CloudSync.startManualSync()
        Self.schedule()
        return true
    }

    /// Show Pulse Lab's own reminders as banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tapping "Log today's WHOOP" opens the Log WHOOP sheet (pulselab://log-whoop).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let url = response.notification.request.content.userInfo["url"] as? String
        if url == MorningBriefing.url.absoluteString {
            // The morning briefing: open Today, where the briefing card sits on top.
            await MainActor.run { PulseLabPending.queue(tab: LabTab.today.rawValue) }
        } else if id.hasPrefix(WhoopPrompt.idPrefix) || url == WhoopPrompt.url.absoluteString {
            await MainActor.run { LogWhoopPending.queue() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: refreshID)
        req.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            await LabStore.shared.refresh(.background)
            if !Task.isCancelled { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

enum LabTab: String, CaseIterable, Identifiable {
    case today, sleep, heart, activity, stack, compare, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .sleep: String(localized: "Sleep")
        case .heart: String(localized: "Heart")
        case .activity: String(localized: "Moves")
        case .stack: String(localized: "Stack")
        case .compare: "VS"
        case .settings: String(localized: "Settings")
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
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
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
                        // Rebuilt when the text size changes so every Lab font picks up the new size.
                        .id("\(tab.rawValue)-\(typeSize)")
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
                    Group {
                        if m == .readiness { ReadinessSheet() } else { MetricDetailSheet(metric: m) }
                    }
                        .environment(store)
                        .presentationDetents([.large])
                        .presentationBackground(Lab.bg)
                }
                .background {
                    // Separate host so it never fights the metric sheet for the same presenter.
                    Color.clear
                        .sheet(item: Binding(get: { store.logWhoop }, set: { store.logWhoop = $0 })) { r in
                            LogWhoopSheet(day: r.day, auto: r.auto)
                                .environment(store)
                                .presentationBackground(Lab.bg)
                        }
                        .background {
                            Color.clear
                                .sheet(item: Binding(get: { store.quickWhoop }, set: { store.quickWhoop = $0 })) { r in
                                    WhoopQuickEditSheet(request: r)
                                        .environment(store)
                                        .presentationBackground(Lab.bg)
                                }
                        }
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
            if !showOnboarding {
                await store.refresh(.launch)
                askForWhoopIfDue()
                openDemoScreen()
            }
        }
        .onChange(of: phase) { _, p in
            if p == .active && !showOnboarding {
                Task {
                    await store.refresh(.foreground)
                    askForWhoopIfDue()
                }
            }
            if p == .active { openPendingTab(); openPendingLogWhoop() }
            if p == .background { PulseLabAppDelegate.schedule() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PulseLabPending.note)) { _ in openPendingTab() }
        .onReceive(NotificationCenter.default.publisher(for: LogWhoopPending.note)) { _ in openPendingLogWhoop() }
        .onAppear { openPendingTab(); openPendingLogWhoop() }
        .onOpenURL(perform: open)
    }

    /// `-demo -open <screen>`: opens a screen straight away (simulator QA and screenshots only).
    private func openDemoScreen() {
        guard let screen = DemoOpen.screen else { return }
        switch screen {
        case "logwhoop": store.logWhoop = LogWhoopRequest()
        case "logwhoopauto": store.logWhoop = LogWhoopRequest(auto: true)
        case "alldata", "sources": DemoOpen.pending = screen; tab = .settings
        case "moreapps":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MoreAppsSheet.present() }
        default: break
        }
    }

    /// Morning pop-up: after 6 am, once a day, when today has no WHOOP recovery yet (API, Health or typed).
    private func askForWhoopIfDue() {
        // Not mid-sync: WHOOP's recovery for today may be about to arrive (cold launch runs two refreshes at once).
        guard !showOnboarding, phase == .active, !store.loading, store.logWhoop == nil, store.detail == nil,
              WhoopPrompt.shouldAsk(store) else { return }
        WhoopPrompt.markAsked()
        store.logWhoop = LogWhoopRequest(auto: true)
    }

    /// Notification tap / Siri "Log WHOOP": open the sheet on today.
    private func openPendingLogWhoop() {
        guard LogWhoopPending.take(), !showOnboarding else { return }
        presentLogWhoop()
    }

    /// Closes a metric sheet first if one is up (two sheets can't share one presenter).
    private func presentLogWhoop() {
        guard store.logWhoop == nil else { return }
        if store.detail != nil {
            store.detail = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.logWhoop = LogWhoopRequest() }
        } else {
            store.logWhoop = LogWhoopRequest()
        }
    }

    /// Siri / Shortcuts / Control Center "open a section" (PulseLabActions.swift).
    private func openPendingTab() {
        guard let name = PulseLabPending.take(), let t = LabTab.named(name) else { return }
        withAnimation(.snappy) { tab = t }
    }

    /// `pulselab://today` (widget tap) jumps to Today. `pulselab://whoop-callback` is the WHOOP OAuth
    /// callback, consumed by ASWebAuthenticationSession, so anything else is ignored here.
    private func open(_ url: URL) {
        guard url.scheme?.lowercased() == "pulselab", let host = url.host?.lowercased() else { return }
        // Morning reminder / shortcut: type today's WHOOP numbers.
        if host == "log-whoop" {
            if !showOnboarding { presentLogWhoop() }
            return
        }
        // Food Book handing over its supplement stack.
        if host == "stack-import" {
            withAnimation(.snappy) { tab = .stack }
            if let n = StackImport.run(url, into: modelContext) {
                store.toast = n > 0 ? "Brought over \(n) supplement\(n == 1 ? "" : "s") from Food Book" : "Your stack was already here"
            } else {
                store.toast = "Couldn't read the stack from Food Book. Try again."
            }
            return
        }
        guard host != "whoop", host != "whoop-callback", let t = LabTab.named(host) else { return }
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

/// `-demo -open <screen>` launch flag (simulator QA and screenshots; ignored without -demo).
enum DemoOpen {
    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard a.contains("-demo"), let i = a.firstIndex(of: "-open"), i + 1 < a.count else { return nil }
        return a[i + 1].lowercased()
    }
    /// Screen a deeper view should open once it appears ("sources", "alldata"); taken once.
    @MainActor static var pending: String?
    @MainActor static func take(_ name: String) -> Bool {
        guard pending == name else { return false }
        pending = nil
        return true
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
                        HStack(spacing: 8) {
                            SyncButton()
                            if showsStates {
                                HeaderIconButton(symbol: "gearshape.fill", label: "Settings", action: nav.openSettings)
                            } else {
                                HeaderIconButton(symbol: "xmark", label: "Close settings", action: nav.closeSettings)
                            }
                        }
                        SyncPill()
                    }
                }
                if store.loading { SyncProgressBar() }
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
        .refreshable { await store.refresh(.user) }
    }
}


/// Pulse Lab Pro: what the subscription (or lifetime unlock) contains.
enum PulseLabPro {
    static let spec = PaywallSpec(
        appName: "Pulse Lab",
        headline: "Settle it: Watch vs WHOOP.",
        tagline: "The full head-to-head lab, 90 days of history and shareable results. Try it free for a week.",
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
