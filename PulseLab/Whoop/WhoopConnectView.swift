import SwiftUI
import UIKit

/// Setup card for connecting WHOOP. Plain SwiftUI; pass the app's accent color.
@MainActor
struct WhoopConnectView: View {
    var accent: Color = .red
    var client: WhoopClient = .shared

    @State private var hasID = WhoopAuth.shared.clientID?.isEmpty == false
    @State private var hasSecret = WhoopAuth.shared.clientSecret?.isEmpty == false
    @State private var note: String?
    @State private var connecting = false
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("WHOOP", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                statusPill
            }

            if client.isConnected {
                connectedBody
            } else {
                setupBody
            }

            if let msg = note ?? client.lastError {
                Text(msg).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .tint(accent)
    }

    private var statusPill: some View {
        let on = client.isConnected
        return Text(on ? (client.isDemo ? "Demo" : "Connected") : "Not connected")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15)))
            .foregroundStyle(on ? Color.green : Color.secondary)
    }

    // MARK: connected

    private var connectedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = client.profile?.name, !name.isEmpty {
                Text("Signed in as \(name)").font(.subheadline)
            }
            Text(syncLine).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await client.sync() }
                } label: {
                    if client.isSyncing { ProgressView() } else { Label("Sync now", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(client.isSyncing || client.isDemo)
                Spacer()
                Button("Disconnect", role: .destructive) { client.disconnect() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var syncLine: String {
        guard let d = client.lastSync else { return "Not synced yet" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return "Last synced \(f.localizedString(for: d, relativeTo: Date())) · \(client.recoveries.count) recoveries · \(client.sleeps.count) sleeps · \(client.workouts.count) workouts"
    }

    // MARK: setup

    @State private var showOwnKeys = false

    @ViewBuilder private var setupBody: some View {
        if WhoopAuth.isConfigured {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in with your WHOOP account to pull recovery, strain, sleep stages, HRV, resting HR, SpO₂, skin temperature and workouts, all of your history.")
                    .font(.subheadline).foregroundStyle(.secondary)
                connectButton(enabled: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHOOP connection not set up yet")
                    .font(.subheadline.weight(.semibold))
                Text("This build doesn't include WHOOP app keys yet. They're added to the next build automatically once they're set up. Until then WHOOP data that WHOOP saves into Apple Health still shows up.")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup(isExpanded: $showOwnKeys) {
                    ownKeysBody.padding(.top, 8)
                } label: {
                    Text("Use my own WHOOP developer keys").font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func connectButton(enabled: Bool) -> some View {
        Button {
            connecting = true; note = nil
            Task {
                await client.connect()
                connecting = false
            }
        } label: {
            HStack {
                Spacer()
                if connecting { ProgressView() } else { Label("Connect WHOOP", systemImage: "link") }
                Spacer()
            }
            .font(.headline)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled || connecting)
    }

    private var ownKeysBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHOOP shares your data through its free developer access. One-time setup, about 3 minutes:")
                .font(.subheadline).foregroundStyle(.secondary)

            step(1, "Open the WHOOP developer dashboard and sign in with your WHOOP account.") {
                Button { openURL(WhoopAuth.dashboardURL) } label: {
                    Label("Open WHOOP dashboard", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            step(2, "Create an app (any name, e.g. Pulse Lab). Tick all the read scopes, and add this Redirect URI:") {
                HStack {
                    Text(WhoopAuth.redirectURI).font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = WhoopAuth.redirectURI
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.bordered)
                }
            }

            step(3, "Copy the Client ID and Client Secret from that app and paste them here.") {
                HStack {
                    pasteButton(title: "Client ID", done: hasID) { value in
                        WhoopAuth.shared.clientID = value; hasID = true
                    }
                    pasteButton(title: "Client Secret", done: hasSecret) { value in
                        WhoopAuth.shared.clientSecret = value; hasSecret = true
                    }
                }
            }

            connectButton(enabled: hasID && hasSecret)

            if hasID || hasSecret {
                Button("Clear pasted ID and secret") {
                    WhoopAuth.shared.forgetCredentials()
                    hasID = false; hasSecret = false
                }
                .font(.footnote)
            }
        }
    }

    private func step<Content: View>(_ n: Int, _ text: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.weight(.heavy))
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent.opacity(0.25)))
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.subheadline)
                content()
            }
        }
    }

    private func pasteButton(title: String, done: Bool, save: @escaping (String) -> Void) -> some View {
        Button {
            let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard raw.count >= 8, !raw.contains(" ") else {
                note = "Copy your \(title) from the WHOOP dashboard first, then tap Paste."
                return
            }
            save(raw)
            note = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            Label(done ? "\(title) ✓" : "Paste \(title)", systemImage: done ? "checkmark.circle.fill" : "doc.on.clipboard")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
