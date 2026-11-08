import SwiftUI

@main
struct ClickerApp: App {
    @State private var store = TVStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Look.cyan)
        }
    }
}

struct RootView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var confirmForget = false
    @Namespace private var tabNS

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground()
            if store.isPaired {
                Group {
                    if tab == 0 { AppsView().transition(.opacity) } else { RemoteView().transition(.opacity) }
                }
                .safeAreaInset(edge: .top) { topBar }
                tabBar
            } else {
                SetupView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if let t = store.toast {
                Text(t)
                    .font(Look.font(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Look.accent, lineWidth: 1.2))
                    .shadow(color: Look.magenta.opacity(0.4), radius: 14)
                    .padding(.bottom, store.isPaired ? 104 : 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                Button(role: .destructive) { confirmForget = true } label: { Label("Forget this TV", systemImage: "tv.slash") }
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
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Look.line))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.bottom, 18)
    }

    private func tabButton(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { tab = i }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(title, systemImage: symbol)
                .font(Look.font(15, .bold))
                .foregroundStyle(tab == i ? .white : Look.dim)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background {
                    if tab == i {
                        Capsule().fill(Look.accent).matchedGeometryEffect(id: "tab", in: tabNS)
                            .shadow(color: Look.magenta.opacity(0.6), radius: 10)
                    }
                }
        }
        .buttonStyle(SquishStyle())
    }
}
