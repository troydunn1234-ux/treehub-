import SwiftUI

@main
struct ClickerApp: App {
    @State private var store: TVStore
    @State private var pc = PCClient()

    init() {
        let s = TVStore()
        _store = State(initialValue: s)
        // Apple Watch remote: presses from the watch go to the TV through this phone.
        ClankerrWatchBridge.shared.attach(s)
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-pc") ? 2
        : (ProcessInfo.processInfo.arguments.contains("-remote") ? 1 : 0)
    @State private var forward = true
    @State private var bounces = [0, 0, 0]
    @State private var confirmForget = false
    @State private var showAbout = false
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
                    Text(t).font(Look.font(15, .bold)).foregroundStyle(.white).lineLimit(2)
                }
                .padding(.leading, Look.S.s).padding(.trailing, Look.S.l).padding(.vertical, Look.S.s)
                .glassCapsule(glow: ok ? Look.magenta : .orange, material: true)
                .padding(.horizontal, 20)
                .padding(.bottom, store.isPaired ? 104 : 40)
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
        HStack(spacing: Look.S.s) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Look.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Look.magenta.opacity(0.6), radius: 6)
                .accessibilityHidden(true)
            Text("CLANKERR").font(Look.font(14, .black)).tracking(3.5)
                .foregroundStyle(Look.accentH)
            Spacer()
            Menu {
                Button { store.press(.powerToggle) } label: { Label("Power", systemImage: "power") }
                Button { store.press(.inputNext) } label: { Label("Switch input", systemImage: "rectangle.on.rectangle") }
                Divider()
                Button { showAbout = true } label: { Label("About Clankerr", systemImage: "info.circle") }
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
    private var license: String {
        (Bundle.main.url(forResource: "pyvizio-LICENSE", withExtension: "txt")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Clankerr").font(Look.display(36)).tracking(-0.5).foregroundStyle(Look.accentH)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
                    section("Privacy", "Clankerr talks only to your TV, directly over your Wi-Fi. It has no account, no tracking and no servers. The pairing code from your TV stays in your phone's Keychain.")
                    section("Not affiliated", "Clankerr is an independent app. It is not made, endorsed or supported by VIZIO. VIZIO, SmartCast and the names of the streaming services shown are trademarks of their owners and are used only to identify what opens on your TV.")
                    section("Open source", "The list of TV apps comes from pyvizio, used under the MIT License:")
                    Text(license).font(.system(size: 11, design: .monospaced)).foregroundStyle(Look.dim)
                }
                .padding(22)
            }
            .background(AuroraBackground())
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
