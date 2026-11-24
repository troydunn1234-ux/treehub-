import SwiftUI

@main
struct ClickerApp: App {
    @State private var store = TVStore.shared
    @State private var pc = PCClient.shared
    @State private var scenes = SceneStore.shared

    init() {
        let s = TVStore.shared
        // Apple Watch remote: presses from the watch go to the TV through this phone.
        ClankerrWatchBridge.shared.attach(s)
        // Watch complication: keep the current TV name in the App Group.
        WidgetBridge.shared.attach(s)
        // Scenes (macros) drive the TV and the PC.
        SceneStore.shared.attach(store: s, pc: PCClient.shared)
        // Sleep timer: notification buttons and the background refresh must be set up before launch finishes.
        SleepTimer.shared.attach()
        // Siri phrases that name an app ("Open Netflix on the TV with Couch Remote") need the app list.
        CouchRemoteShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(pc)
                .environment(scenes)
                .preferredColorScheme(.dark)
                .tint(Look.cyan)
                .onOpenURL { url in
                    // couchremote://remote (Watch complication, Shortcuts) just opens the app.
                    if url.host == "scene", let name = url.pathComponents.dropFirst().first,
                       let scene = SceneStore.shared.scenes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        Task { await SceneStore.shared.run(scene) }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-pc") ? 2
        : (ProcessInfo.processInfo.arguments.contains("-remote") ? 1 : 0)
    @State private var forward = true
    @State private var bounces = [0, 0, 0]
    @State private var confirmForget = false
    @State private var showAbout = false
    /// Set once the About sheet has actually appeared (used by the "-demo -open about" launch).
    @State private var aboutShown = false
    @Namespace private var tabNS

    /// Tabs slide in from the side you're heading toward.
    private var tabTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(x: forward ? 36 : -36).combined(with: .opacity),
                           removal: .offset(x: forward ? -36 : 36).combined(with: .opacity))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            // The room glows softly in the color of the app that's on the TV (Apps and Remote tabs).
            AmbientGlow(app: store.isPaired && tab != 2 ? store.nowPlaying : nil)
            Group {
                if tab == 2 {
                    PCView().transition(tabTransition)
                } else if store.isPaired {
                    Group {
                        if tab == 0 { AppsView().transition(tabTransition) } else { RemoteView().transition(tabTransition) }
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
                HStack(spacing: Look.S.m) {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(ok ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.orange), in: Circle())
                        .symbolEffect(.bounce, value: t)
                    Text(t).font(Look.text(.subheadline, .bold)).foregroundStyle(.white).lineLimit(3)
                }
                .padding(.leading, Look.S.s).padding(.trailing, Look.S.l).padding(.vertical, Look.S.s)
                .glassCapsule(glow: ok ? Look.magenta : .orange, material: true)
                .padding(.horizontal, 20)
                .padding(.bottom, store.isPaired ? 104 : 40)
                .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
            if store.typing && store.isPaired && tab != 2 {
                // Tap outside to close; the bar rides up on top of the phone keyboard.
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { store.closeKeyboard() }
                    .transition(.opacity)
                KeyboardBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.typing)
        .onChange(of: tab) { _, _ in if store.typing { store.closeKeyboard() } }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.isPaired)
        .task(id: phase) {
            // Keep "now playing" fresh while the app is open.
            guard phase == .active else { return }
            store.watchKeyboard()   // sockets may have dropped while the app was in the background
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .sheet(isPresented: $showAbout) { AboutView().onAppear { aboutShown = true } }
        .task { await openDemoSheet() }
        .paywallHost(spec: CouchRemotePro.spec)
        .onboarding(CouchRemoteOnboard.spec)
        .confirmationDialog("Forget \(store.tv?.name ?? "this TV")?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { store.forgetTV() }
        } message: { Text("You'll need to pair it again to use it.") }
    }

    /// "-demo -open about / moreapps" (simulator QA screenshots). Asked for once launch has settled, and asked
    /// again if it didn't appear: UIKit drops a presentation requested while a cold start still shows the launch
    /// screen and never retries it (same approach as the shared paywall host). Normal launches return right away.
    @MainActor private func openDemoSheet() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo"), let i = args.firstIndex(of: "-open"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "about":
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if aboutShown || Task.isCancelled { return }
                showAbout = false
                try? await Task.sleep(nanoseconds: 200_000_000)
                showAbout = true
            }
        case "moreapps":
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            MoreAppsSheet.present()
        default:
            break
        }
    }

    private var topBar: some View {
        HStack(spacing: Look.S.s) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Look.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Look.magenta.opacity(0.6), radius: 6)
                .accessibilityHidden(true)
            Text("COUCH REMOTE").font(Look.font(14, .black)).tracking(3.5)
                .foregroundStyle(Look.accentH)
            Spacer()
            Menu {
                Button { store.press(.powerToggle) } label: { Label("Power", systemImage: "power") }
                Button { store.press(.inputNext) } label: { Label("Switch input", systemImage: "rectangle.on.rectangle") }
                Divider()
                Button { showAbout = true } label: { Label("About Couch Remote", systemImage: "info.circle") }
                if store.inAppDemo {
                    Button(role: .destructive) { store.endDemo() } label: { Label("Exit demo", systemImage: "xmark.circle") }
                } else {
                    Button(role: .destructive) { confirmForget = true } label: { Label("Forget \(store.tv?.name ?? "this TV")", systemImage: "tv.slash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).glassCircle()
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, Look.S.xs)
    }

    private var tabBar: some View {
        HStack(spacing: Look.S.xs) {
            tabButton(0, "Apps", "square.grid.2x2.fill")
            tabButton(1, "Remote", "appletvremote.gen4.fill")
            tabButton(2, "PC", "desktopcomputer")
        }
        .padding(6)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.10), Look.bgDeep.opacity(0.5)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), Look.violet.opacity(0.5)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
        .shadow(color: Look.violet.opacity(0.25), radius: 24)
        .padding(.bottom, 12)
    }

    private func tabButton(_ i: Int, _ title: String, _ symbol: String) -> some View {
        let on = tab == i
        return Button {
            guard tab != i else { return }
            forward = i > tab
            bounces[i] += 1
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { tab = i }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .symbolEffect(.bounce, value: bounces[i])
                Text(title).font(Look.font(15, .heavy))
            }
            .foregroundStyle(on ? .white : Look.dim)
            .padding(.horizontal, on ? 20 : 15).frame(height: 52)
            .background {
                if on {
                    ShiftingPill()
                        .matchedGeometryEffect(id: "tab", in: tabNS)
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)).padding(1.5))
                        .shadow(color: Look.magenta.opacity(0.55), radius: 12, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showCompat = false
    private var license: String {
        (Bundle.main.url(forResource: "pyvizio-LICENSE", withExtension: "txt")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }
    private static let repo = "https://github.com/troydunn1234-ux/treehub-"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Look.S.xl) {
                    header

                    card {
                        row("Which TVs work?", "VIZIO, Roku, Samsung, LG, Google TV", "tv.and.mediabox.fill") { showCompat = true }
                    }

                    MoreAppsGate {
                        MoreAppsRow(tint: Look.cyan)
                            .foregroundStyle(.white)
                            .padding(Look.S.m)
                            .frame(minHeight: 44)
                            .glass(Look.R.card, tint: Look.cyan)
                    }

                    card {
                        link("Privacy policy", "No account, no tracking, no servers", "hand.raised.fill", "\(Self.repo)/blob/main/store/clicker/PRIVACY.md")
                        divider
                        link("Help & support", "Pairing, Wi-Fi and TV tips", "questionmark.circle.fill", "\(Self.repo)/blob/main/store/clicker/SUPPORT.md")
                        divider
                        link("Contact", "Questions or ideas? Open an issue", "envelope.fill", "\(Self.repo)/issues")
                        divider
                        link("Terms of use", "Standard App Store licence", "doc.text.fill", "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                    }

                    VStack(alignment: .leading, spacing: Look.S.l) {
                        section("Works with", "VIZIO SmartCast, Roku TVs and players, Samsung (Tizen), LG (webOS), and Google TV / Android TV, on the same Wi-Fi as your phone.")
                        section("Privacy", "Couch Remote talks only to your TV (and your PC, if you use it), directly over your Wi-Fi. It has no account, no tracking and no servers. Pairing keys stay in your phone's Keychain.")
                        section("Not affiliated", "Couch Remote is an independent app. It is not made, endorsed or supported by VIZIO, Roku, Samsung, LG or Google. Those names, and the names of the streaming services shown, are trademarks of their owners and are used only to identify which TVs work and what opens on your TV.")
                        section("Open source", "The VIZIO app list comes from pyvizio, used under the MIT License:")
                        Text(license).font(.system(.caption2, design: .monospaced)).foregroundStyle(Look.dim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Look.S.xl)
            }
            .background(AuroraBackground())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCompat) { CompatibilityView() }
    }

    private var header: some View {
        HStack(spacing: Look.S.l) {
            AppIconTile(size: 72)
            VStack(alignment: .leading, spacing: Look.S.xs) {
                Text("Couch Remote").font(Look.text(.title, .black)).foregroundStyle(Look.accentH)
                Text(version).font(Look.text(.subheadline, .semibold)).foregroundStyle(Look.dim).monospacedDigit()
                Text("Every TV. One remote.").font(Look.text(.footnote, .medium)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, Look.S.m)
            .glass(Look.R.card, tint: Look.cyan)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 44)
    }

    private func rowLabel(_ title: String, _ detail: String, _ symbol: String, external: Bool) -> some View {
        HStack(spacing: Look.S.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Look.cyan)
                .frame(width: 32, height: 32)
                .background(Look.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Look.text(.body, .semibold)).foregroundStyle(.white)
                Text(detail).font(Look.text(.caption, .medium)).foregroundStyle(Look.dim)
            }
            Spacer(minLength: Look.S.s)
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Look.dim)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Look.S.m)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, detail, symbol, external: false) }
            .buttonStyle(SquishStyle(scale: 0.98))
    }

    private func link(_ title: String, _ detail: String, _ symbol: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: { rowLabel(title, detail, symbol, external: true) }
            .buttonStyle(SquishStyle(scale: 0.98))
            .accessibilityHint("Opens in Safari")
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Look.text(.headline, .heavy)).foregroundStyle(.white)
            Text(body).font(Look.text(.subheadline, .medium)).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
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


/// Couch Remote Pro: what the one-time unlock contains.
enum CouchRemotePro {
    static let spec = PaywallSpec(
        appName: "Couch Remote",
        headline: "Every screen in the house.",
        tagline: "Add all your TVs, type searches from your phone and drive your PC from the couch. One payment, no subscription.",
        tint: Look.cyan, tint2: Look.magenta,
        features: [
            .init(icon: "tv.and.mediabox", title: "Unlimited TVs", detail: "Vizio, Roku, Samsung, LG and Google TV — save every set and switch rooms with one tap."),
            .init(icon: "keyboard", title: "Type on your TV", detail: "Search Netflix or YouTube with your phone's keyboard instead of pecking at an on-screen grid."),
            .init(icon: "desktopcomputer", title: "PC remote", detail: "Trackpad, media keys, volume, sleep and lock for your Windows PC over Wi-Fi or Tailscale."),
        ],
        freeNote: "The full remote and app launcher for one TV stays free. Bought Couch Remote when it was a paid app? Pro is already yours — tap Restore.",
        privacyURL: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/clicker/PRIVACY.md")
    )
}
