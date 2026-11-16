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
    @State private var briefing = MorningBriefing.enabled
    @State private var cloud = CloudSync.userEnabled
    @State private var showPlans = false
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        LabScroll(kicker: "Calibration", title: "Settings", showsStates: false) {
            pro
            sync
            health
            LabPanel {
                WhoopConnectView(accent: Lab.whoop)
            }
            morningBriefing
            whoopByHand
            if CloudSync.built { iCloud }
            trust
            dataCheck
            weeklySummary
            units
            export
            MoreAppsGate { LabPanel { MoreAppsRow(tint: Lab.accent).foregroundStyle(Lab.text) } }
            about
        }
        .sheet(isPresented: $showPlans) { PaywallView(spec: PulseLabPro.spec) }
        .onAppear {
            // -demo -open sources / alldata (simulator QA): Sources first; it opens All data itself.
            if DemoOpen.take("sources") || DemoOpen.pending == "alldata" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showSources = true }
            }
        }
    }

    /// Pulse Lab Pro: plans, current subscription, restore.
    private var pro: some View {
        Button { showPlans = true } label: {
            linkCard("sparkles", "Pulse Lab Pro",
                     unlock.subscribed ? "Active. Change plan, cancel or restore here."
                     : unlock.isPro ? "Lifetime. Thank you!" : "Free week, then monthly, yearly or lifetime.")
        }
        .buttonStyle(PressScale())
    }

    /// One tappable settings card: icon tile, title, one-line subtitle, chevron.
    private func linkCard(_ icon: String, _ title: String, _ subtitle: String, pro: Bool = false) -> some View {
        LabPanel {
            HStack(spacing: Lab.S.sm) {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(Lab.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Lab.accent.opacity(0.15)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L(title)).font(.headline).foregroundStyle(Lab.text)
                        if pro {
                            Text("PRO").font(Lab.label(9)).foregroundStyle(Lab.accent)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Lab.accent.opacity(0.15)))
                        }
                    }
                    Text(L(subtitle)).font(.footnote).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Lab.S.s)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.faint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var health: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTag("Apple Health")
                    Spacer()
                    statusPill(store.healthAsked ? "Connected" : "Not set up", ok: store.healthAsked)
                }
                Text("Reads heart, HRV, sleep stages, breathing, SpO₂, wrist temp, energy, steps, workouts and more. Pulse Lab only writes the supplements you check off. Samples are split by source, so WHOOP data inside Health stays on WHOOP's side.")
                    .font(.footnote).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.connectHealth() }
                } label: {
                    Label(store.healthAsked ? "Re-check permissions" : "Connect Apple Health", systemImage: "heart.text.square")
                }
                .buttonStyle(LabSecondaryButton())
                Text("Missing data? Settings → Health → Data Access & Devices → Pulse Lab → Turn On All.")
                    .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusPill(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Lab.good : Lab.warn).frame(width: 6, height: 6)
            Text(L(text)).font(.caption.weight(.semibold)).foregroundStyle(ok ? Lab.good : Lab.warn)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill((ok ? Lab.good : Lab.warn).opacity(0.12)))
    }

    private var sync: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTag("Sync now")
                        Text("WHOOP + Apple Health, full refresh").font(.footnote).foregroundStyle(Lab.dim)
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
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Lab.accent)
                            .accessibilityHidden(true)
                        Text("Sources").font(.body.weight(.semibold)).foregroundStyle(Lab.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.faint)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSources) { SourcesScreen().environment(store).presentationBackground(Lab.bg) }
            }
        }
    }

    private func syncRow(_ name: String, _ date: Date?, off: String?) -> some View {
        HStack {
            Circle().fill(off == nil && date != nil ? Lab.good : Lab.faint).frame(width: 6, height: 6)
            Text(L(name)).font(.subheadline).foregroundStyle(Lab.dim)
            Spacer()
            Text(off.map(L) ?? date.map { $0.formatted(.relative(presentation: .named)) } ?? L("never"))
                .font(Lab.mono(13)).foregroundStyle(Lab.text)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var dataCheck: some View {
        Button { showDataCheck = true } label: {
            linkCard("stethoscope", "Data check", "See what's arriving from Health and WHOOP, metric by metric, with the WHOOP sync log.")
        }
        .buttonStyle(PressScale())
        .sheet(isPresented: $showDataCheck) { DataCheckView().environment(store) }
    }

    private var trust: some View {
        Button { showTrust = true } label: {
            linkCard("checkmark.shield.fill", "Who to trust", "Metric by metric: which tracker to believe, why they differ, and how often yours agree.", pro: !Unlock.shared.isPro)
        }
        .buttonStyle(PressScale())
        .sheet(isPresented: $showTrust) { TrustScreen().environment(store).presentationBackground(Lab.bg) }
    }

    /// Typing WHOOP numbers in by hand: the morning pop-up and the daily reminder notification.
    private var whoopByHand: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("WHOOP by hand")
                LogWhoopCard()
                Toggle("Ask me for WHOOP numbers each morning", isOn: $askWhoop).tint(Lab.accent)
                    .font(.body).foregroundStyle(Lab.text)
                    .onChange(of: askWhoop) { _, on in WhoopPrompt.askEnabled = on }
                Text("After 6 am, the first time you open Pulse Lab without a WHOOP recovery for today, the Log WHOOP sheet pops up once.")
                    .font(.footnote).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                Toggle("Daily reminder", isOn: $whoopReminder).tint(Lab.accent)
                    .font(.body).foregroundStyle(Lab.text)
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
                if whoopReminder || briefing {
                    DatePicker("Remind me at", selection: $whoopTime, displayedComponents: .hourAndMinute)
                        .tint(Lab.accent)
                        .font(.body).foregroundStyle(Lab.text)
                        .onChange(of: whoopTime) { _, t in
                            WhoopPrompt.reminderTime = t
                            let logged = store.hasWhoopRecoveryToday
                            Task { await WhoopPrompt.reschedule(loggedToday: logged) }
                        }
                }
                Text("“Log today's WHOOP — 20 seconds”, skipped on days you've already logged. Tap it to open the sheet.")
                    .font(.footnote).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if whoopDenied {
                    Text("Notifications are off for Pulse Lab. Turn them on in Settings → Notifications → Pulse Lab.")
                        .font(.footnote).foregroundStyle(Lab.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The morning notification with the briefing. Same notification as the WHOOP reminder, never a second one.
    private var morningBriefing: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag(String(localized: "Morning briefing"))
                Toggle(String(localized: "Morning briefing notification"), isOn: $briefing).tint(Lab.accent)
                    .font(.body).foregroundStyle(Lab.text)
                    .onChange(of: briefing) { _, on in
                        let logged = store.hasWhoopRecoveryToday
                        Task {
                            if on {
                                let ok = await MorningBriefing.enable(loggedToday: logged)
                                if !ok { briefing = false; whoopDenied = true }
                            } else {
                                MorningBriefing.enabled = false
                                await WhoopPrompt.reschedule(loggedToday: logged)
                            }
                        }
                    }
                Text(String(localized: "One notification each morning at the reminder time below: recovery, sleep vs your week, HRV and resting HR vs your baseline, and one takeaway. If today's WHOOP numbers are missing, it asks you to log them instead, so you never get two."))
                    .font(.footnote).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// iCloud: the Stack and hand-typed WHOOP numbers on every device signed in to your account.
    private var iCloud: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag(String(localized: "iCloud"))
                Toggle(String(localized: "Sync my Stack and logged WHOOP numbers"), isOn: $cloud).tint(Lab.accent)
                    .font(.body).foregroundStyle(Lab.text)
                    .onChange(of: cloud) { _, on in CloudSync.userEnabled = on }
                Text(CloudSync.signedIn
                     ? String(localized: "Uses your private iCloud. Health and WHOOP data aren't uploaded; each device reads those itself. Changes apply the next time Pulse Lab opens.")
                     : String(localized: "Sign in to iCloud in the Settings app to sync."))
                    .font(.footnote).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Sunday 6 pm local: "WHOOP vs Watch this week" with one line of stats. Off by default.
    private var weeklySummary: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Weekly summary")
                Toggle("Sunday 6 pm notification", isOn: $weekly).tint(Lab.accent)
                    .font(.body).foregroundStyle(Lab.text)
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
                    .font(.footnote).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if notifyDenied {
                    Text("Notifications are off for Pulse Lab. Turn them on in Settings → Notifications → Pulse Lab.")
                        .font(.footnote).foregroundStyle(Lab.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var units: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Units")
                Toggle("Miles & pounds", isOn: $imperial).tint(Lab.accent)
                Toggle("Fahrenheit", isOn: $fahrenheit).tint(Lab.accent)
            }
            .font(.body)
            .foregroundStyle(Lab.text)
        }
    }

    private var export: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: 10) {
                SectionTag("Export")
                Text("Every day from both trackers as a spreadsheet (CSV).").font(.footnote).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Share PulseLab.csv", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(LabPrimaryButton())
                } else {
                    Button { if Unlock.shared.gate("CSV export") { exportURL = store.exportFile() } } label: {
                        Label("Build export", systemImage: Unlock.shared.isPro ? "tablecells" : "lock.fill")
                    }
                    .buttonStyle(LabSecondaryButton())
                }
            }
        }
    }

    private var about: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                FamilyAboutHeader(name: "Pulse Lab", tagline: String(localized: "Apple Watch and WHOOP, side by side."), tint: Lab.accent)
                    .foregroundStyle(Lab.text)
                FamilyAboutLinks(privacy: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/pulselab/PRIVACY.md"),
                                 terms: FamilyAboutLinks.standardTerms,
                                 support: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/pulselab/SUPPORT.md"),
                                 tint: Lab.accent)
                    .font(.body)
                    .foregroundStyle(Lab.text)
                Text("Pulse Lab is independent and not affiliated with Apple or WHOOP. Your data stays on this iPhone.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, Lab.S.xs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
