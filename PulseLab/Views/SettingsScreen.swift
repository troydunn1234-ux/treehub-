import SwiftUI

struct SettingsScreen: View {
    @Environment(LabStore.self) private var store
    @AppStorage("unitsImperial") private var imperial = true
    @AppStorage("unitsF") private var fahrenheit = true
    @State private var exportURL: URL?
    @State private var showDataCheck = false
    @State private var showTrust = false
    @State private var weekly = Notify.enabled
    @State private var notifyDenied = false

    var body: some View {
        LabScroll(kicker: "Calibration", title: "Settings", showsStates: false) {
            health
            LabPanel(tint: Lab.whoop) {
                WhoopConnectView(accent: Lab.whoop)
            }
            sync
            trust
            dataCheck
            weeklySummary
            units
            export
            about
        }
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
                Text("Reads heart, HRV, sleep stages, breathing, SpO₂, wrist temp, energy, steps, workouts and more. Pulse Lab never writes to Health. Samples are split by source, so WHOOP data inside Health stays on WHOOP's side.")
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync now").font(Lab.display(16, .heavy)).foregroundStyle(Lab.text)
                    Text(store.lastPull.map { "Last pull " + $0.formatted(.relative(presentation: .named)) } ?? "Not synced yet")
                        .font(Lab.mono(10)).foregroundStyle(Lab.faint)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.title3.weight(.bold))
                        .foregroundStyle(Lab.bg).frame(width: 44, height: 44)
                        .background(Circle().fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .rotationEffect(.degrees(store.loading ? 360 : 0))
                        .animation(store.loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.loading)
                }
                .accessibilityLabel("Sync now")
            }
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
