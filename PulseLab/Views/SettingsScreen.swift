import SwiftUI

@MainActor
struct SettingsScreen: View {
    @Environment(LabStore.self) private var store
    @AppStorage("unitsImperial") private var imperial = true
    @AppStorage("unitsF") private var fahrenheit = true
    @State private var exportURL: URL?
    @State private var showDataCheck = false
    @State private var showTrust = false
    @State private var showSources = false
    @State private var weekly = Notify.enabled
    @State private var notifyDenied = false
    @State private var askWhoop = WhoopPrompt.askEnabled
    @State private var whoopReminder = WhoopPrompt.reminderOn
    @State private var whoopTime = WhoopPrompt.reminderTime
    @State private var whoopDenied = false
    @State private var showPlans = false
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        LabScroll(kicker: "Calibration", title: "Settings", showsStates: false) {
            pro
            sync
            health
            LabPanel(tint: Lab.whoop) {
                WhoopConnectView(accent: Lab.whoop)
            }
            whoopByHand
            trust
            dataCheck
            weeklySummary
            units
            export
            LabPanel(tint: Lab.violet) { MoreAppsRow(tint: Lab.violet).foregroundStyle(Lab.text) }
            about
        }
        .sheet(isPresented: $showPlans) { PaywallView(spec: PulseLabPro.spec) }
    }

    /// Pulse Lab Pro: plans, current subscription, restore.
    private var pro: some View {
        Button { showPlans = true } label: {
            LabPanel(tint: Lab.watch) {
                HStack(spacing: Lab.S.m) {
                    Image(systemName: "sparkles").font(.title3.weight(.bold)).foregroundStyle(Lab.watch)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pulse Lab Pro").font(Lab.title(16)).foregroundStyle(Lab.text)
                        Text(unlock.subscribed ? "Active. Change plan, cancel or restore here."
                             : unlock.isPro ? "Lifetime. Thank you!" : "Free week, then monthly, yearly or lifetime.")
                            .font(Lab.body(12)).foregroundStyle(Lab.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Lab.faint)
                }
            }
        }
        .buttonStyle(PressScale())
    }

    private var health: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(Lab.watch)
                    Text("Apple Health").font(Lab.display(18, .heavy)).foregroundStyle(Lab.text)
                    Spacer()
                    Text(store.healthAsked ? "CONNECTED" : "NOT SET UP").font(Lab.label(9)).foregroundStyle(store.healthAsked ? Lab.good : Lab.warn)
                }
                Text("Reads heart, HRV, sleep stages, breathing, SpO₂, wrist temp, energy, steps, workouts and more. Pulse Lab only writes the supplements you check off. Samples are split by source, so WHOOP data inside Health stays on WHOOP's side.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                Button {
                    Task { await store.connectHealth() }
                } label: {
                    Label(store.healthAsked ? "Re-check permissions" : "Connect Apple Health", systemImage: "heart.text.square")
                        .font(Lab.display(15, .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Lab.watch.opacity(0.18)))
                        .foregroundStyle(Lab.watch)
                }
                .buttonStyle(.plain)
                Text("Missing data? Settings → Health → Data Access & Devices → Pulse Lab → Turn On All.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Lab.faint)
            }
        }
    }

    private var sync: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync now").font(Lab.display(16, .heavy)).foregroundStyle(Lab.text)
                        Text("WHOOP + Apple Health, full refresh").font(Lab.mono(10)).foregroundStyle(Lab.faint)
                    }
                    Spacer()
                    SyncButton()
                }
                if store.loading { SyncProgressBar() }
                syncRow("WHOOP", WhoopClient.shared.isConnected ? WhoopClient.shared.lastSync : nil,
                        off: WhoopClient.shared.isConnected ? nil : (WhoopAuth.isConfigured ? "not connected" : "not set up yet"))
                syncRow("Apple Health", store.healthSynced, off: store.healthAsked ? nil : "not set up")
                syncRow("Apple Watch (newest sample)", store.lastWatchSample, off: nil)
                Button { showSources = true } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Lab.violet)
                        Text("Sources").font(Lab.title(15)).foregroundStyle(Lab.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Lab.faint)
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSources) { SourcesScreen().environment(store).presentationBackground(Lab.bg) }
            }
        }
    }

    private func syncRow(_ name: String, _ date: Date?, off: String?) -> some View {
        HStack {
            Circle().fill(off == nil && date != nil ? Lab.good : Lab.faint).frame(width: 6, height: 6)
            Text(name).font(Lab.body(13)).foregroundStyle(Lab.dim)
            Spacer()
            Text(off ?? date.map { $0.formatted(.relative(presentation: .named)) } ?? "never")
                .font(Lab.mono(11)).foregroundStyle(Lab.text)
        }
    }

    private var dataCheck: some View {
        Button { showDataCheck = true } label: {
            LabPanel(tint: Lab.violet) {
                HStack(spacing: Lab.S.m) {
                    Image(systemName: "stethoscope").font(.title3.weight(.bold)).foregroundStyle(Lab.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data check").font(Lab.title(16)).foregroundStyle(Lab.text)
                        Text("See what's arriving from Health and WHOOP, metric by metric, with the WHOOP sync log.")
                            .font(Lab.body(12)).foregroundStyle(Lab.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Lab.faint)
                }
            }
        }
        .buttonStyle(PressScale())
        .sheet(isPresented: $showDataCheck) { DataCheckView().environment(store) }
    }

    private var trust: some View {
        Button { showTrust = true } label: {
            LabPanel(tint: Lab.violet) {
                HStack(spacing: Lab.S.m) {
                    Image(systemName: "checkmark.shield.fill").font(.title3.weight(.bold)).foregroundStyle(Lab.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Who to trust").font(Lab.title(16)).foregroundStyle(Lab.text)
                            if !Unlock.shared.isPro { Text("PRO").font(Lab.label(8)).tracking(1.2).foregroundStyle(Lab.watch) }
                        }
                        Text("Metric by metric: which tracker to believe, why they differ, and how often yours agree.")
                            .font(Lab.body(12)).foregroundStyle(Lab.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Lab.faint)
                }
            }
        }
        .buttonStyle(PressScale())
        .sheet(isPresented: $showTrust) { TrustScreen().environment(store).presentationBackground(Lab.bg) }
    }

    /// Typing WHOOP numbers in by hand: the morning pop-up and the daily reminder notification.
    private var whoopByHand: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("WHOOP by hand", color: Lab.whoop)
                LogWhoopCard()
                Toggle("Ask me for WHOOP numbers each morning", isOn: $askWhoop).tint(Lab.whoop)
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
                    .onChange(of: askWhoop) { _, on in WhoopPrompt.askEnabled = on }
                Text("After 6 am, the first time you open Pulse Lab without a WHOOP recovery for today, the Log WHOOP sheet pops up once.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                Toggle("Daily reminder", isOn: $whoopReminder).tint(Lab.whoop)
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
                    .onChange(of: whoopReminder) { _, on in
                        let logged = store.hasWhoopRecoveryToday
                        if on {
                            Task {
                                let ok = await WhoopPrompt.enableReminder(loggedToday: logged)
                                if !ok { whoopReminder = false; whoopDenied = true }
                            }
                        } else {
                            WhoopPrompt.reminderOn = false
                            Task { await WhoopPrompt.reschedule(loggedToday: logged) }
                        }
                    }
                if whoopReminder {
                    DatePicker("Remind me at", selection: $whoopTime, displayedComponents: .hourAndMinute)
                        .tint(Lab.whoop)
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
                        .onChange(of: whoopTime) { _, t in
                            WhoopPrompt.reminderTime = t
                            let logged = store.hasWhoopRecoveryToday
                            Task { await WhoopPrompt.reschedule(loggedToday: logged) }
                        }
                }
                Text("“Log today's WHOOP — 20 seconds”, skipped on days you've already logged. Tap it to open the sheet.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                if whoopDenied {
                    Text("Notifications are off for Pulse Lab. Turn them on in Settings → Notifications → Pulse Lab.")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Lab.warn)
                }
            }
        }
    }

    /// Sunday 6 pm local: "WHOOP vs Watch this week" with one line of stats. Off by default.
    private var weeklySummary: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Weekly summary")
                Toggle("Sunday 6 pm notification", isOn: $weekly).tint(Lab.watch)
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
                    .onChange(of: weekly) { _, on in
                        if on {
                            Task {
                                let ok = await Notify.enable(agreements: store.agreements30)
                                if !ok { weekly = false; notifyDenied = true }
                            }
                        } else {
                            Notify.disable()
                        }
                    }
                Text(weekly ? "Next one reads: “\(Notify.line(store.agreements30))”" : "One line every Sunday: how many metrics agreed this week and the resting HR gap.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                if notifyDenied {
                    Text("Notifications are off for Pulse Lab. Turn them on in Settings → Notifications → Pulse Lab.")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(Lab.warn)
                }
            }
        }
    }

    private var units: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Units")
                Toggle("Miles & pounds", isOn: $imperial).tint(Lab.watch)
                Toggle("Fahrenheit", isOn: $fahrenheit).tint(Lab.watch)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Lab.text)
        }
    }

    private var export: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Export")
                Text("Every day from both trackers as a spreadsheet (CSV).").font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Share PulseLab.csv", systemImage: "square.and.arrow.up")
                            .font(Lab.display(15, .heavy)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Lab.whoop.opacity(0.18))).foregroundStyle(Lab.whoop)
                    }
                } else {
                    Button { if Unlock.shared.gate("CSV export") { exportURL = store.exportFile() } } label: {
                        Label("Build export", systemImage: Unlock.shared.isPro ? "tablecells" : "lock.fill")
                            .font(Lab.display(15, .heavy)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.06))).foregroundStyle(Lab.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var about: some View {
        Text("Pulse Lab is independent and not affiliated with Apple or WHOOP. Your data stays on this iPhone.")
            .font(.system(size: 11, design: .rounded)).foregroundStyle(Lab.faint)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
    }
}
