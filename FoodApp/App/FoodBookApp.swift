import SwiftUI
import SwiftData

@main
struct FoodBookApp: App {
    /// One container for the whole process, so Siri quick logs (Intents.swift) write to the same store the app shows.
    static let sharedContainer: ModelContainer = {
        let schema = Schema([FoodEntry.self, Supplement.self, SuppDose.self, DayLog.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    let container: ModelContainer = FoodBookApp.sharedContainer

    init() {
        // Apple Watch: today's numbers out, quick logs and check-offs in.
        FoodWatchBridge.shared.attach(container: container)
        // Apple Health (Whoop + Apple Watch arrive through Health): meals out, burned calories in.
        FoodHealth.shared.attach(container: container)
        // Home Screen widget: today's numbers in the App Group.
        WidgetBridge.shared.attach(container: container)
    }

    var body: some Scene {
        WindowGroup {
            Splash { RootTabs() }
                .onAppear { LegacyImport.runOnce(into: container.mainContext); DemoFood.seedIfNeeded(container.mainContext) }
                .onOpenURL { url in
                    // foodbook://snap (widget) opens the camera on Today.
                    guard url.scheme == "foodbook" else { return }
                    if url.host == "snap" { FoodDeepLink.shared.snapRequests += 1 }
                }
        }
        .modelContainer(container)
    }
}

/// Requests that arrive by URL (widget taps) and are acted on by whichever view is showing.
@MainActor
@Observable
final class FoodDeepLink {
    static let shared = FoodDeepLink()
    /// Bumped for every foodbook://snap; Today opens the camera when it changes.
    var snapRequests = 0
    /// Bumped by Siri / Control Center "open supplement stack"; RootTabs switches to Stack.
    var stackRequests = 0
    /// Bumped just before a Siri / Control Center snap, so RootTabs is on Food before Today sees the snap.
    var foodTabRequests = 0

    /// Siri / Shortcuts / Control Center actions (FoodBookActions.swift). The short wait lets Today be on
    /// screen first (fresh launch, or coming from Stack), so it sees the snap request change.
    func consumePending() {
        guard let action = FoodBookPending.take() else { return }
        switch action {
        case .stack:
            stackRequests += 1
        case .snap:
            foodTabRequests += 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self.snapRequests += 1
            }
        }
    }
}

/// Food and Supplements, switched with a floating pill at the bottom.
struct RootTabs: View {
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-supps") ? 1 : 0
    @State private var deepLink = FoodDeepLink.shared
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var ns
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if tab == 0 { TodayView().transition(.opacity) } else { SuppsView().transition(.opacity) }
            }
            HStack(spacing: 4) {
                pill(0, "Food", "fork.knife")
                pill(1, "Stack", "pills.fill")
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Ember.line))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .padding(.leading, 20)
            .padding(.bottom, 30)
        }
        .preferredColorScheme(.dark)
        .onChange(of: deepLink.snapRequests) { _, _ in withAnimation { tab = 0 } }
        .onChange(of: deepLink.stackRequests) { _, _ in withAnimation { tab = 1 } }
        .onChange(of: deepLink.foodTabRequests) { _, _ in tab = 0 }
        .onReceive(NotificationCenter.default.publisher(for: FoodBookPending.note)) { _ in deepLink.consumePending() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { deepLink.consumePending() } }
        .onAppear { deepLink.consumePending() }
    }
    private func pill(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = i }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(title, systemImage: symbol)
                .font(Ember.font(15, .bold))
                .foregroundStyle(tab == i ? .white : Ember.dim)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background { if tab == i { Capsule().fill(Ember.fire).matchedGeometryEffect(id: "pill", in: ns) } }
        }
        .buttonStyle(Squish())
    }
}

/// A quick ember-glow intro, then the app.
struct Splash<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var done = false
    @State private var pop = false
    var body: some View {
        ZStack {
            content().opacity(done ? 1 : 0)
            if !done {
                ZStack {
                    Ember.bg.ignoresSafeArea()
                    Circle().fill(Ember.fire).frame(width: 220, height: 220).blur(radius: 70).opacity(pop ? 0.7 : 0)
                    VStack(spacing: 10) {
                        Text("🍳").font(.system(size: 64)).scaleEffect(pop ? 1 : 0.3)
                        Text("Food Book").font(Ember.font(34, .black)).foregroundStyle(Ember.fire).opacity(pop ? 1 : 0)
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { pop = true }
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeOut(duration: 0.35)) { done = true }
        }
    }
}

/// Sample day for simulator screenshots only (launch with -demo).
enum DemoFood {
    static func seedIfNeeded(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        let today = Day.key(Date())
        let items: [(String, Double, Double, Double, Double, Meal)] = [
            ("Greek yogurt", 150, 20, 8, 4, .breakfast), ("Banana", 105, 1.3, 27, 0.4, .breakfast),
            ("Cold brew", 5, 0, 0, 0, .breakfast), ("Chicken burrito bowl", 650, 42, 70, 20, .lunch),
            ("Protein bar", 210, 20, 22, 7, .snacks)]
        for (n, cal, p, c, f, m) in items {
            context.insert(FoodEntry(name: n, cal: cal, protein: p, carbs: c, fat: f, meal: m, day: today))
        }
        let stack: [(String, String, String, SuppTime)] = [("Vitamin D3", "5000 IU", "☀️", .morning), ("Omega-3", "2 softgels", "🐟", .morning),
            ("Creatine", "5 g", "💪", .anytime), ("Protein powder", "1 scoop", "🥤", .anytime), ("Magnesium", "400 mg", "🌙", .night)]
        for (i, (n, d, e, t)) in stack.enumerated() { context.insert(Supplement(name: n, dose: d, emoji: e, time: t, order: i)) }
        if let first = try? context.fetch(FetchDescriptor<Supplement>()).first { context.insert(SuppDose(suppID: first.id, day: today)) }
        try? context.save()
    }
}
