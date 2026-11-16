import SwiftUI

// MARK: - Sync controls

/// Header button: full sync of WHOOP + Apple Health. Spins while a sync runs.
@MainActor
struct SyncButton: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await store.refresh(.user) }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(store.loading ? Lab.watch : Lab.text)
                .rotationEffect(.degrees(store.loading ? 360 : 0))
                .animation(store.loading && !Lab.reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.loading)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(store.loading)
        .accessibilityLabel(store.loading ? "Syncing" : "Sync now")
    }
}

/// Thin progress bar with what's being synced, shown under a screen title while a sync runs.
@MainActor
struct SyncProgressBar: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((store.syncLine ?? "Syncing").uppercased()).font(Lab.label(9)).tracking(0.4).foregroundStyle(Lab.dim).lineLimit(1)
                Spacer()
                Text("\(Int(store.syncProgress * 100))%").font(Lab.mono(10)).foregroundStyle(Lab.faint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(Lab.duel)
                        .frame(width: max(8, geo.size.width * store.syncProgress))
                        .animation(.easeOut(duration: 0.3), value: store.syncProgress)
                }
            }
            .frame(height: 4)
            if store.backfilling {
                Text("First sync reads your full history once. After that only new data is fetched.")
                    .font(Lab.body(11)).foregroundStyle(Lab.faint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Syncing, \(Int(store.syncProgress * 100)) percent")
    }
}

// MARK: - Sources

/// Settings → Sources: which data sources are connected, when each last synced, and how much history is in.
@MainActor
struct SourcesScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showDataCheck = false
    @State private var showAllData = false
    @State private var confirmRebuild = false
    private var whoop: WhoopClient { WhoopClient.shared }

    var body: some View {
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: "Where your data comes from", title: "Sources")
                        Spacer()
                        CloseButton { dismiss() }
                    }
                    syncAll
                    whoopCard
                    healthCard
                    watchCard
                    fitnessCard
                    tools
                }
                .padding(.horizontal, Lab.S.m)
                .padding(.top, Lab.S.m)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh(.user) }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDataCheck) { DataCheckView().environment(store) }
        .sheet(isPresented: $showAllData) { AllDataScreen().environment(store).presentationBackground(Lab.bg) }
        .onAppear {
            if DemoOpen.take("alldata") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showAllData = true } }
        }
    }

    // MARK: cards

    private var syncAll: some View {
        LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync everything").font(Lab.title(17)).foregroundStyle(Lab.text)
                        Text("WHOOP and Apple Health, plus anything that arrived late in the last 3 days.")
                            .font(Lab.body(12)).foregroundStyle(Lab.dim)
                    }
                    Spacer()
                    SyncButton()
                }
                if store.loading { SyncProgressBar() }
                Text("Pulse Lab also refreshes by itself when new Health data arrives, when you open it, and in the background.")
                    .font(Lab.body(11)).foregroundStyle(Lab.faint)
            }
        }
    }

    private var whoopCard: some View {
        let configured = WhoopAuth.isConfigured || WhoopAuth.shared.hasPastedCredentials
        let status: (String, Color) = LabStore.isDemo ? ("DEMO", Lab.good)
            : whoop.isConnected ? ("CONNECTED", Lab.good)
            : configured ? ("NOT CONNECTED", Lab.warn) : ("NOT SET UP YET", Lab.faint)
        return LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                header("WHOOP", icon: "bolt.heart.fill", tint: Lab.whoop, status: status)
                if whoop.isConnected {
                    line("Last synced", ago(whoop.lastSync))
                    line("History from", day(whoop.cycles.last?.start))
                    line("Days · nights · workouts", "\(whoop.cycles.count) · \(whoop.sleeps.filter { $0.nap != true }.count) · \(whoop.workouts.count)")
                    line("Recovery scored", "\(whoop.recoveries.filter { $0.score != nil }.count)")
                    if whoop.isSyncing, let st = whoop.stage { line("Now syncing", st) }
                    if let e = whoop.lastError { Text(e).font(Lab.body(12)).foregroundStyle(Lab.bad) }
                } else {
                    WhoopConnectView(accent: Lab.whoop)
                }
                if let t = store.lastWhoopInHealth {
                    line("WHOOP in Health, newest", ago(t))
                }
                if !store.manual.isEmpty {
                    line("Typed in by hand", "\(store.manual.count) day\(store.manual.count == 1 ? "" : "s")")
                }
                LogWhoopCard()
            }
        }
    }

    private var healthCard: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                header("Apple Health", icon: "heart.fill", tint: Lab.watch,
                       status: store.healthAsked ? ("CONNECTED", Lab.good) : ("NOT SET UP", Lab.warn))
                if store.healthAsked {
                    line("Last read", ago(store.healthSynced))
                    line("History from", store.backfilling ? "reading…" : day(store.historyFrom))
                    line("Days with data", "\(store.watchDays.count)")
                    line("Sleep nights · workouts", "\(store.sleeps.filter { $0.source == .watch }.count) · \(store.workouts.filter { $0.source == .watch }.count)")
                    Text("Missing a metric? iPhone Settings → Health → Data Access & Devices → Pulse Lab → Turn On All.")
                        .font(Lab.body(11)).foregroundStyle(Lab.faint)
                } else {
                    Button { Task { await store.connectHealth() } } label: {
                        Text("Connect Apple Health").font(Lab.display(15, .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Lab.watch.opacity(0.18))).foregroundStyle(Lab.watch)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var watchCard: some View {
        let last = store.lastWatchSample
        let live = last.map { Date().timeIntervalSince($0) < 3 * 86_400 } ?? false
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                header(store.watchName ?? "Apple Watch", icon: "applewatch", tint: Lab.watch,
                       status: live ? ("SENDING DATA", Lab.good) : last == nil ? ("NOT SEEN", Lab.faint) : ("QUIET", Lab.warn))
                line("Newest heart rate", ago(last))
                if let d = store.watchDays.last(where: { $0.hrv != nil })?.day { line("Newest HRV", day(d)) }
                if let n = store.lastNight(.watch) { line("Newest sleep", day(n.night)) }
                if !live {
                    Text("The Watch reaches Pulse Lab through Apple Health. Wear it and keep it paired; data shows up after it syncs to your iPhone.")
                        .font(Lab.body(11)).foregroundStyle(Lab.faint)
                }
            }
        }
    }

    private var fitnessCard: some View {
        let today = store.watchDays.stat(on: Date())
        let lastWorkout = store.workouts.filter { $0.source == .watch }.map(\.start).max()
        return LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                header("Fitness", icon: "figure.run", tint: Lab.accent,
                       status: today == nil ? ("NO DATA TODAY", Lab.faint) : ("TODAY IN", Lab.good))
                line("Move", today?.activeKcal.map { "\(Int($0)) kcal" } ?? "—")
                line("Exercise", today?.exerciseMin.map { "\(Int($0)) min" } ?? "—")
                line("Stand", today?.standHours.map { "\(Int($0)) h" } ?? "—")
                line("Steps", today?.steps.map { Int($0).formatted() } ?? "—")
                line("Newest workout", day(lastWorkout))
            }
        }
    }

    private var tools: some View {
        LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Button { showAllData = true } label: {
                    HStack {
                        Image(systemName: "square.grid.3x3.fill").foregroundStyle(Lab.accent)
                        Text("All data, every metric").font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Lab.faint)
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(Lab.line)
                Button { showDataCheck = true } label: {
                    HStack {
                        Image(systemName: "stethoscope").foregroundStyle(Lab.accent)
                        Text("Data check, metric by metric").font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Lab.faint)
                    }
                }
                .buttonStyle(.plain)
                Divider().overlay(Lab.line)
                Button { confirmRebuild = true } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise").foregroundStyle(Lab.warn)
                        Text("Rebuild full history").font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.loading)
                .confirmationDialog("Re-read everything?", isPresented: $confirmRebuild, titleVisibility: .visible) {
                    Button("Rebuild history") { Task { await store.rebuildHistory() } }
                } message: {
                    Text("Reads 2 years from Apple Health and your whole WHOOP history again. Use it if old days look wrong or you deleted data.")
                }
            }
        }
    }

    // MARK: bits

    private func header(_ title: String, icon: String, tint: Color, status: (String, Color)) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(Lab.display(18, .heavy)).foregroundStyle(Lab.text).lineLimit(1)
            Spacer()
            Text(status.0).font(Lab.label(9)).foregroundStyle(status.1)
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Lab.body(13)).foregroundStyle(Lab.dim)
            Spacer()
            Text(v).font(Lab.mono(12)).foregroundStyle(Lab.text)
        }
    }

    private func ago(_ d: Date?) -> String {
        guard let d else { return "never" }
        return d.formatted(.relative(presentation: .named))
    }

    private func day(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
