import SwiftUI

/// Sheets shared by the Apps and Remote screens.
enum TVSheet: String, Identifiable {
    case switcher, addTV
    var id: String { rawValue }
}

/// Tappable pill that shows the active TV and opens the switcher.
struct TVSwitcherPill: View {
    @Environment(TVStore.self) private var store
    let action: () -> Void
    var subtitle: String? = nil

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: Look.S.s) {
                Image(systemName: "tv.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Look.accent, in: Circle())
                    .shadow(color: Look.violet.opacity(0.6), radius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.tv?.name ?? "Your TV").font(Look.font(15, .heavy)).foregroundStyle(.white).lineLimit(1)
                        .contentTransition(.opacity)
                    if let subtitle {
                        Text(subtitle).font(Look.font(11, .semibold)).foregroundStyle(Look.dim).lineLimit(1)
                    }
                }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(Look.dim)
                    .padding(.trailing, Look.S.xs)
            }
            .padding(.leading, 5).padding(.trailing, Look.S.m).padding(.vertical, 5)
            .frame(minHeight: 44)
            .glassCapsule()
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.tv?.id)
        }
        .buttonStyle(SquishStyle(scale: 0.95))
        .accessibilityLabel("TV: \(store.tv?.name ?? "none"). Switch TVs")
    }
}

/// The TV switcher: your TVs with live status, switch with a tap, add or forget one.
struct TVSwitcherSheet: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onAdd: () -> Void
    @State private var forgetting: DiscoveredTV?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Look.S.l) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Look.S.xs) {
                            CapsLabel("Switch TV", color: Look.cyan)
                            Text("Your TVs").font(Look.display(32)).tracking(-0.5).foregroundStyle(.white)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).glassCircle()
                        }
                        .buttonStyle(SquishStyle())
                        .accessibilityLabel("Close")
                    }
                    .padding(.bottom, Look.S.xs)

                    ForEach(store.tvs) { t in row(t) }

                    Button(action: onAdd) {
                        HStack(spacing: Look.S.m) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundStyle(Look.cyan)
                                .frame(width: 48, height: 48)
                                .background(Look.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add another TV").font(Look.font(16, .heavy)).foregroundStyle(.white)
                                Text("Pair a TV on this Wi-Fi").font(Look.font(12, .semibold)).foregroundStyle(Look.dim)
                            }
                            Spacer()
                        }
                        .padding(Look.S.m)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                }
                .padding(Look.S.xl)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .preferredColorScheme(.dark)
        .onChange(of: store.tvs.count) { _, n in if n == 0 { dismiss() } }
        .confirmationDialog("Forget \(forgetting?.name ?? "this TV")?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { if let t = forgetting { withAnimation(.snappy) { store.forget(t) } } }
        } message: { Text("You'll need to pair it again to use it.") }
    }

    private func row(_ t: DiscoveredTV) -> some View {
        let active = t.id == store.tv?.id
        let statusColor: Color = active ? (store.reachable ? Look.live : .orange) : Look.faint
        let status = active ? (store.reconnecting ? "Searching…" : store.reachable ? "Connected" : "Offline") : "Saved"
        return HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if !active { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.switchTo(t) } }
                dismiss()
            } label: {
                HStack(spacing: Look.S.m) {
                    Image(systemName: "tv.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(active ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.08)),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: active ? Look.violet.opacity(0.6) : .clear, radius: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(Look.font(17, .heavy)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 6) {
                            LiveDot(color: statusColor, size: 6, pulsing: active && store.reachable)
                                .frame(width: 10, height: 10)
                            Text("\(status) · \(t.brand.shortName) · \(t.model)").font(Look.font(12, .semibold)).foregroundStyle(Look.dim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Look.S.s)
                    if active {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Look.accent, in: Circle())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SquishStyle(scale: 0.97))
            .accessibilityLabel("\(t.name), \(t.brand.displayName), \(status)\(active ? ", current TV" : ". Switch to this TV")")

            Menu {
                Button(role: .destructive) { forgetting = t } label: { Label("Forget \(t.name)", systemImage: "tv.slash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Look.dim)
                    .frame(width: 40, height: 48).contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(t.name)")
        }
        .padding(Look.S.m)
        .padding(.trailing, -Look.S.xs)
        .glass(22, tint: active ? Look.violet : .white, glow: active ? Look.violet : nil)
    }
}

extension View {
    /// Presents the TV switcher / add-TV sheets driven by one binding.
    func tvSheets(_ sheet: Binding<TVSheet?>, store: TVStore) -> some View {
        self.sheet(item: sheet) { kind in
            switch kind {
            case .switcher:
                TVSwitcherSheet(onAdd: { sheet.wrappedValue = .addTV })
                    .environment(store)
            case .addTV:
                ZStack {
                    AuroraBackground()
                    SetupView(onPaired: { sheet.wrappedValue = nil })
                }
                .environment(store)
                .preferredColorScheme(.dark)
                .onDisappear { Task { await store.cancelPairing() } }
            }
        }
    }
}
