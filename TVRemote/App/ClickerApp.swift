import SwiftUI

@main
struct ClickerApp: App {
    @State private var store = TVStore()
    @State private var pc = PCClient()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(pc)
                .preferredColorScheme(.dark)
                .tint(Look.cyan)
        }
    }
}

struct RootView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-pc") ? 2
        : (ProcessInfo.processInfo.arguments.contains("-remote") ? 1 : 0)
    @State private var confirmForget = false
    @State private var showAbout = false
    @Namespace private var tabNS

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            Group {
                if tab == 2 {
                    PCView().transition(.opacity)
                } else if store.isPaired {
                    Group {
                        if tab == 0 { AppsView().transition(.opacity) } else { RemoteView().transition(.opacity) }
                    }
                    .safeAreaInset(edge: .top) { topBar }
                } else {
                    SetupView().transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
            tabBar
            if let t = store.toast {
                let ok = t.hasPrefix("Opening")
                HStack(spacing: 10) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ok ? Look.cyan : Color.orange)
                        .symbolEffect(.bounce, value: t)
                    Text(t).font(Look.font(15, .bold)).foregroundStyle(.white).lineLimit(2)
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(ok ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.orange.opacity(0.7)), lineWidth: 1.2))
                .shadow(color: (ok ? Look.magenta : Color.orange).opacity(0.4), radius: 16)
                .padding(.horizontal, 20)
                .padding(.bottom, store.isPaired ? 112 : 40)
                .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.isPaired)
        .task(id: phase) {
            // Keep "now playing" fresh while the app is open.
            guard phase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .confirmationDialog("Forget \(store.tv?.name ?? "this TV")?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { store.forgetTV() }
        } message: { Text("You'll pair again with a new code from the TV.") }
    }

    private var topBar: some View {
        HStack {
            Text("CLICKER").font(Look.font(13, .heavy)).tracking(3)
                .foregroundStyle(Look.accent)
            Spacer()
            Menu {
                Button { store.press(.powerToggle) } label: { Label("Power", systemImage: "power") }
                Button { store.press(.inputNext) } label: { Label("Switch input", systemImage: "rectangle.on.rectangle") }
                Divider()
                Button { showAbout = true } label: { Label("About Clicker", systemImage: "info.circle") }
                Button(role: .destructive) { confirmForget = true } label: { Label("Forget \(store.tv?.name ?? "this TV")", systemImage: "tv.slash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Look.card, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            tabButton(0, "Apps", "square.grid.2x2.fill")
            tabButton(1, "Remote", "appletvremote.gen4.fill")
            tabButton(2, "PC", "desktopcomputer")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Look.line))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.bottom, 16)
    }

    private func tabButton(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = i }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(title, systemImage: symbol)
                .font(Look.font(15, .bold))
                .foregroundStyle(tab == i ? .white : Look.dim)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .background {
                    if tab == i {
                        ShiftingPill()
                            .matchedGeometryEffect(id: "tab", in: tabNS)
                            .shadow(color: Look.magenta.opacity(0.6), radius: 12)
                    }
                }
        }
        .buttonStyle(SquishStyle())
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private var license: String {
        (Bundle.main.url(forResource: "pyvizio-LICENSE", withExtension: "txt")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Clicker").font(Look.font(32, .heavy)).foregroundStyle(Look.accent)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
                    section("Privacy", "Clicker talks only to your TV, directly over your Wi-Fi. It has no account, no tracking and no servers. The pairing code from your TV stays in your phone's Keychain.")
                    section("Not affiliated", "Clicker is an independent app. It is not made, endorsed or supported by VIZIO. VIZIO, SmartCast and the names of the streaming services shown are trademarks of their owners and are used only to identify what opens on your TV.")
                    section("Open source", "The list of TV apps comes from pyvizio, used under the MIT License:")
                    Text(license).font(.system(size: 11, design: .monospaced)).foregroundStyle(Look.dim)
                }
                .padding(22)
            }
            .background(Look.bg)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Look.font(17, .heavy)).foregroundStyle(.white)
            Text(body).font(Look.font(15, .medium)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// The selected tab's pill: the accent gradient slowly drifts around.
private struct ShiftingPill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Capsule().fill(LinearGradient(colors: [Look.magenta, Look.violet, Look.cyan],
                                          startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t * 0.6), y: 0.5 + 0.5 * sin(t * 0.6)),
                                          endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t * 0.6), y: 0.5 - 0.5 * sin(t * 0.6))))
        }
    }
}
