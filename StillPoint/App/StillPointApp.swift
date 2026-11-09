import SwiftUI

@main
struct StillPointApp: App {
    @StateObject private var prefs = Prefs.shared
    @StateObject private var log = SessionLog.shared
    @StateObject private var link = PhoneLink.shared
    @StateObject private var router = Router()

    init() {
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(prefs)
                .environmentObject(log)
                .environmentObject(link)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(SP.amber)
        }
    }
}

/// App-wide navigation state: which tab, and the session that's running (if any).
final class Router: ObservableObject {
    @Published var tab = 0
    @Published var running: SessionPlan? = nil
    @Published var showSettings = false

    func run(_ plan: SessionPlan) {
        Prefs.shared.markRecent(plan.practice.id)
        running = plan
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
            SettingsView().environmentObject(prefs).environmentObject(link)
        }
        .onAppear {
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
