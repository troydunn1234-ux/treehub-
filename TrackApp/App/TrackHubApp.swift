import SwiftUI
import UIKit
import SwiftData
import UserNotifications

@main
struct TrackHubApp: App {
    @State private var tracker: RouteTracker

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
        UserDefaults.standard.register(defaults: ["useMetric": false, DriveDetector.enabledKey: true, DriveFinishedNotifier.enabledKey: true])
        UNUserNotificationCenter.current().delegate = DriveNotificationRouter.shared
        DriveDetector.registerCategory()
        DriveFinishedNotifier.shared.start()
        #if DEBUG
        if TrackDemo.isOn { CrashTrace.install() }
        #endif
        let t = RouteTracker()
        _tracker = State(initialValue: t)
        // Apple Watch: live stats out, start/stop in.
        if !TrackDemo.isOn { RoamrWatchBridge.shared.attach(tracker: t, container: container) }
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate { TrackRootView() }
                .environment(tracker)
                // "Go together" invite links: roamr://join?c=CODE (and the https join page form).
                .onOpenURL { url in Task { @MainActor in GroupSession.shared.handle(url: url) } }
                .preferredColorScheme(.dark)
                .tint(Theme.glow)
        }
        .modelContainer(container)
    }
}

struct TrackRootView: View {
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    /// "track", "history", "stats" or "settings".
    @State private var tab: String = "track"
    @State private var detector = DriveDetector.shared
    @State private var autoFinish = AutoFinish.shared

    private var tabItems: [TabBarItem] {
        [
            TabBarItem(id: "track", symbol: tracker.isActive ? "record.circle" : "location.north.circle.fill",
                       label: "Track", alert: tracker.isActive),
            TabBarItem(id: "history", symbol: "clock.arrow.circlepath", label: "History"),
            TabBarItem(id: "stats", symbol: "chart.bar.fill", label: "Stats"),
            TabBarItem(id: "settings", symbol: "gearshape.fill", label: "Settings"),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.forestDeep.ignoresSafeArea()
            Group {
                switch tab {
                case "history": HistoryView()
                case "stats": StatsView()
                case "settings": TrackSettingsView()
                default: TrackView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            FloatingTabBar(items: tabItems, selection: $tab)
        }
        // "Go together": live group activities with friends (TrackApp/Group).
        .groupTogether(tab: $tab)
        .overlay(alignment: .top) {
            if detector.showBanner && !tracker.isActive {
                DriveBanner(onStart: startDriveFromPrompt, onDismiss: { detector.dismissBanner() })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if detector.showAlwaysCard && !detector.showBanner && !tracker.isActive {
                AlwaysLocationCard(onDismiss: { detector.dismissAlwaysCard() })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let left = autoFinish.secondsLeft, tracker.isActive {
                AutoFinishBanner(kind: tracker.kind, secondsLeft: left,
                                 onFinish: { autoFinish.finishNow() }, onKeep: { autoFinish.keepGoing() })
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: detector.showBanner)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: detector.showAlwaysCard)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: autoFinish.secondsLeft == nil)
        .onChange(of: tracker.autoFinishDue) { _, due in
            if due { autoFinish.ask() }
        }
        .onReceive(NotificationCenter.default.publisher(for: DriveDetector.startDriveNote)) { _ in
            consumePendingStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: RoamrPending.note)) { _ in
            consumePendingAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: DriveFinishedNotifier.openActivityNote)) { _ in
            // History picks up the saved id and pushes the activity.
            tab = "history"
        }
        .onChange(of: tracker.isActive) { _, active in
            if !active { detector.trackingEnded() } else { detector.showBanner = false }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: tab)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tracker.persist() }
            if phase == .active {
                consumePendingStart(); consumePendingAction(); detector.refresh()
                if UserDefaults.standard.string(forKey: DriveFinishedNotifier.pendingOpenKey) != nil { tab = "history" }
            }
        }
        .onAppear {
            autoFinish.attach(tracker)
            detector.isTracking = { [tracker] in tracker.isActive }
            detector.refresh()
            consumePendingStart()
            consumePendingAction()
            // Once after this update: ask for what auto-detect needs (Always location, motion, notifications).
            if !TrackDemo.isOn, detector.enabled, !UserDefaults.standard.bool(forKey: DriveDetector.permsAskedKey) {
                UserDefaults.standard.set(true, forKey: DriveDetector.permsAskedKey)
                Task { await detector.enable() }
            }
            if tracker.recoveredFromCrash { tab = "track" }
            if TrackDemo.isOn {
                TrackDemo.seed(context)
                switch TrackDemo.argument(after: "-tab") {
                case "history": tab = "history"
                case "stats": tab = "stats"
                case "settings": tab = "settings"
                default: tab = "track"
                }
                if ProcessInfo.processInfo.arguments.contains("-autostart") { tracker.start(kind: .run) }
                if ProcessInfo.processInfo.arguments.contains("-autodrive") { tracker.start(kind: .drive) }
            }
        }
    }

    private func consumePendingStart() {
        guard UserDefaults.standard.bool(forKey: DriveDetector.pendingStartKey) else { return }
        UserDefaults.standard.set(false, forKey: DriveDetector.pendingStartKey)
        startDriveFromPrompt()
    }

    /// Siri / Shortcuts / Control Center actions (RoamrActions.swift).
    private func consumePendingAction() {
        guard let action = RoamrPending.take() else { return }
        let kind: ActivityKind
        switch action {
        case .history: tab = "history"; return
        case .stats: tab = "stats"; return
        case .walk: kind = .walk
        case .run: kind = .run
        case .hike: kind = .hike
        case .ride: kind = .bike
        case .drive: kind = .drive
        }
        detector.showBanner = false
        tab = "track"
        guard !tracker.isActive else { return }
        if !tracker.canTrack { tracker.requestPermission(); return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        tracker.start(kind: kind)
    }

    private func startDriveFromPrompt() {
        detector.showBanner = false
        tab = "track"
        guard !tracker.isActive else { return }
        if !tracker.canTrack { tracker.requestPermission(); return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        tracker.start(kind: .drive)
    }
}

/// "Looks like your drive ended" banner with a countdown; finishes on its own unless you say keep going.
struct AutoFinishBanner: View {
    let kind: ActivityKind
    let secondsLeft: Int
    var onFinish: () -> Void
    var onKeep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.goldGradient).frame(width: 46, height: 46)
                Text("\(secondsLeft)").font(Theme.rounded(16, .black)).foregroundStyle(Theme.forestDeep).monospacedDigit()
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.title) over?").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                Text("You've been stopped a while. Finishing in \(secondsLeft)s.").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 6)
            Button(action: onFinish) {
                Text("Finish").font(Theme.rounded(14, .heavy)).foregroundStyle(Theme.forestDeep)
                    .padding(.horizontal, 14).padding(.vertical, 10).background(Theme.goldGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onKeep) {
                Text("Keep going").font(Theme.rounded(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 10).background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.gold.opacity(0.5), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .animation(.snappy, value: secondsLeft)
    }
}

/// "Driving? Start drive" banner shown in the app when you're moving fast and not recording.
struct DriveBanner: View {
    var onStart: () -> Void
    var onDismiss: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.leafGradient).frame(width: 46, height: 46)
                    .shadow(color: Theme.leaf.opacity(0.6), radius: pulse ? 14 : 6)
                Image(systemName: "car.fill").font(.system(size: 18, weight: .black)).foregroundStyle(Theme.forestDeep)
            }
            .scaleEffect(pulse ? 1.06 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Driving?").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                Text("Looks like you're moving fast").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 6)
            Button(action: onStart) {
                Text("Start drive")
                    .font(Theme.rounded(14, .heavy))
                    .foregroundStyle(Theme.forestDeep)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.leafGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.textDim)
                    .frame(width: 30, height: 30).background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.glow.opacity(0.5), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One-time nudge: auto-detect only catches drives with Roamr closed if Location is "Always".
struct AlwaysLocationCard: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 40, height: 40)
                    .background(Theme.goldGradient, in: Circle())
                Text("Catch every drive").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.textDim)
                        .frame(width: 30, height: 30).background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text("Set Location to Always so Roamr can catch drives when it's closed. It only takes a quick GPS check when you're moving, so it's easy on battery.")
                .font(Theme.rounded(13, .medium))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                onDismiss()
            } label: {
                Text("Open Settings")
                    .font(Theme.rounded(14, .heavy))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.goldGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.gold.opacity(0.5), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}


#if DEBUG
/// CI simulators don't write crash reports, so in demo mode a fatal signal prints its own backtrace to the log.
enum CrashTrace {
    static func install() {
        for sig in [SIGFPE, SIGILL, SIGTRAP, SIGSEGV, SIGBUS, SIGABRT] {
            signal(sig) { s in
                NSLog("CRASHTRACE signal %d", s)
                for line in Thread.callStackSymbols { NSLog("CRASHTRACE %@", line) }
                exit(128 + s)
            }
        }
    }
}
#endif
