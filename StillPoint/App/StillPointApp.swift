import SwiftUI

@main
struct StillPointApp: App {
    @StateObject private var prefs = Prefs.shared
    @StateObject private var log = SessionLog.shared
    @StateObject private var link = PhoneLink.shared
    @StateObject private var router = Router()
    @StateObject private var unlock = Unlock.shared
    @StateObject private var heat = HeatStore.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneLink.shared.activate()
        Reminders.shared.activate()
        WidgetBridge.publish()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(prefs)
                .environmentObject(log)
                .environmentObject(link)
                .environmentObject(router)
                .environmentObject(heat)
                .preferredColorScheme(.dark)
                .tint(SP.amber)
                .onReceive(unlock.$isPro) { Prefs.shared.setPro($0) }
                .onboarding(StillPointOnboard.spec)
                // Widget / complication taps: stillpoint://practice/<id>
                .onOpenURL { url in
                    if let id = WidgetBridge.practiceId(from: url) { router.handle(practiceId: id) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                router.consumePending()
                WidgetBridge.publish()
                heat.refreshMissing()
            }
        }
    }
}

/// App-wide navigation state: which tab, and the session that's running (if any).
final class Router: ObservableObject {
    @Published var tab = 0
    @Published var running: SessionPlan? = nil
    @Published var showSettings = false
    /// Navigation inside the Today tab, so deep links can push a practice page.
    @Published var homePath = NavigationPath()

    /// Where Siri / Shortcuts leave the practice they want started; picked up on launch and foreground.
    static let pendingKey = "sp.pendingPractice"
    static let pendingNote = Notification.Name("sp.pendingPractice")

    func run(_ plan: SessionPlan) {
        Prefs.shared.markRecent(plan.practice.id)
        running = plan
    }

    /// Show a practice's page (Today tab).
    func show(_ p: Practice) {
        showSettings = false
        tab = 0
        homePath = NavigationPath()
        homePath.append(p)
    }

    /// Start a practice straight away at the usual length; locked ones go to their page instead.
    /// Does nothing while a session is already running, so a stray link never cuts one short.
    func handle(practiceId id: String) {
        guard let p = PracticeLibrary.shared.practice(id) else { return }
        if PracticeLibrary.shared.isLocked(p) { show(p); return }
        guard running == nil else { return }
        showSettings = false
        tab = 0
        let usual = Prefs.shared.settings.defaultMinutes
        let mins = p.minutes.contains(usual) ? usual : p.defaultMinutes
        run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: mins))
    }

    /// Queue a practice to start (from an App Intent); the app picks it up when it is in front.
    static func queue(practiceId id: String) {
        UserDefaults.standard.set(id, forKey: pendingKey)
        NotificationCenter.default.post(name: pendingNote, object: nil)
    }

    func consumePending() {
        guard let id = UserDefaults.standard.string(forKey: Self.pendingKey), !id.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        handle(practiceId: id)
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var link: PhoneLink
    @EnvironmentObject var log: SessionLog
    private let lib = PracticeLibrary.shared

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }
                .tag(0)
            TraditionsView()
                .tabItem { Label("Traditions", systemImage: "globe.asia.australia") }
                .tag(1)
            JourneyView()
                .tabItem { Label("Journey", systemImage: "leaf") }
                .tag(2)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .fullScreenCover(item: $router.running) { plan in
            PhoneRunView(plan: plan) { router.running = nil }
                .environmentObject(prefs)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView().environmentObject(prefs).environmentObject(link).environmentObject(log)
        }
        .onReceive(NotificationCenter.default.publisher(for: Router.pendingNote)) { _ in router.consumePending() }
        .onAppear {
            Reminders.onOpen = { router.tab = 0 }
            router.consumePending()
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
                router.tab = ["today": 0, "traditions": 1, "journey": 2][args[i + 1]] ?? 0
            }
            if let i = args.firstIndex(of: "-session"), i + 1 < args.count, let p = lib.practice(args[i + 1]) {
                router.run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: p.defaultMinutes))
            }
            if !args.contains("-demo") { MindfulHealth.shared.requestAuthorization() }
        }
    }
}

/// Slow drifting motes of light (still when Reduce Motion is on).
struct Motes: View {
    var count = 26
    var color: Color = SP.amber
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let a = Double(i) * 12.9898
                    let fx = (sin(a) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = (sin(a * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1)
                    let speed = 0.004 + 0.006 * abs(fx)
                    let x = (abs(fx) + sin(t * 0.05 + a) * 0.03) * Double(size.width)
                    var y = (abs(fy) - t * speed).truncatingRemainder(dividingBy: 1)
                    if y < 0 { y += 1 }
                    let r = 1.0 + 2.0 * abs(fy)
                    let alpha = 0.10 + 0.25 * (0.5 + 0.5 * sin(t * 0.4 + a))
                    let rect = CGRect(x: x - r, y: y * Double(size.height) - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// Still Point Pro: what the one-time unlock contains.
enum StillPointPro {
    static let spec = PaywallSpec(
        appName: "Still Point",
        headline: "Every practice, for good.",
        tagline: "Open all 45 practices from 12 traditions, plus every joint, lymph and stretch routine. One payment, no subscription.",
        tint: SP.gold, tint2: SP.amber,
        features: [
            .init(icon: "books.vertical.fill", title: "All 45 practices", detail: "Breathwork, stillness and movement from Zen, Sufi, Vedic, Taoist, Christian, Jewish, Stoic and more."),
            .init(icon: "figure.cooldown", title: "Every warm-up routine", detail: "Makkō-hō, Sūrya Namaskār, Ruesi Dat Ton, Ba Duan Jin and the rest, 2–10 minutes, with figures for each step."),
            .init(icon: "applewatch", title: "Everything on your Watch", detail: "Haptic breathing for the full library, straight from your wrist."),
            .init(icon: "heart.text.square.fill", title: "Journey with heart data", detail: "Every session kept with your heart-rate stats and Mindful Minutes in Apple Health."),
        ],
        freeNote: "The starter set — one practice from each tradition and two routines — stays free forever.",
        privacyURL: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/stillpoint/PRIVACY.md")
    )
}
