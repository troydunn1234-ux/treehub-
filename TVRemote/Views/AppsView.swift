import SwiftUI

/// Your streaming apps as big glowing tiles. Tap one and it opens on the TV.
struct AppsView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var addingTV = false
    @State private var forgetting: VizioClient.TVInfo?
    @State private var launching: String?
    @State private var appeared = false
    @State private var beam: Beam?

    struct Beam: Identifiable, Equatable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let color: Color
    }

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let now = store.nowPlaying { NowPlayingCard(name: now, app: store.catalog.first { $0.name == now }) { store.press(.home) } }
                    quickChips
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(Array(store.favoriteApps.enumerated()), id: \.element.id) { i, app in
                            AppTile(app: app, isPlaying: store.nowPlaying == app.name, launching: launching == app.name) { frame in
                                fireBeam(from: frame, color: app.colors.first ?? Look.magenta)
                                Task {
                                    launching = app.name
                                    await store.launch(app)
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    launching = nil
                                }
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 24)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.04), value: appeared)
                            .contextMenu {
                                Button(role: .destructive) { store.toggleFavorite(app) } label: { Label("Remove from my apps", systemImage: "minus.circle") }
                            }
                        }
                        Button { editing = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 26, weight: .bold))
                                Text("Add apps").font(Look.font(14))
                            }
                            .foregroundStyle(Look.dim)
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Look.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
                        }
                        .buttonStyle(SquishStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh() }

            if let b = beam { BeamView(beam: b).id(b.id).allowsHitTesting(false) }
        }
        .coordinateSpace(name: "apps")
        .sheet(isPresented: $editing) { AppPicker().environment(store) }
        .sheet(isPresented: $addingTV) {
            ZStack {
                AuroraBackground()
                SetupView(onPaired: { addingTV = false })
            }
            .environment(store)
            .preferredColorScheme(.dark)
            .onDisappear { Task { await store.cancelPairing() } }
        }
        .confirmationDialog("Forget \(forgetting?.name ?? "this TV")?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { if let t = forgetting { withAnimation(.snappy) { store.forget(t) } } }
        } message: { Text("You'll pair it again with a code from the TV.") }
        .onAppear { appeared = true }
    }

    private func fireBeam(from frame: CGRect, color: Color) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else { return }
        beam = Beam(x: frame.midX, y: frame.minY, color: color)
        let id = beam?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if beam?.id == id { beam = nil } }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night vibes"
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting.uppercased()).font(Look.font(12, .heavy)).tracking(2).foregroundStyle(Look.accent)
                tvSwitcher
            }
            Spacer()
            Button {
                guard !store.reachable, !store.reconnecting else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await store.reconnect(userInitiated: true) }
            } label: {
                HStack(spacing: 6) {
                    if store.reconnecting {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Circle().fill(store.reachable ? Color.green : Color.orange).frame(width: 8, height: 8)
                            .shadow(color: store.reachable ? .green : .orange, radius: 4)
                    }
                    Text(store.reconnecting ? "Searching…" : store.reachable ? "Connected" : "Offline · Retry")
                        .font(Look.font(12, .bold)).foregroundStyle(store.reachable ? Look.dim : .white)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(store.reachable ? AnyShapeStyle(Look.card) : AnyShapeStyle(Color.orange.opacity(0.25)), in: Capsule())
                .animation(.snappy, value: store.reconnecting)
            }
            .buttonStyle(SquishStyle())
            .disabled(store.reachable)
            .accessibilityLabel(store.reachable ? "Connected" : "TV offline. Tap to search for it again.")
        }
        .padding(.top, 8)
    }

    /// Tap the TV name to switch TVs, add another, or forget one.
    private var tvSwitcher: some View {
        Menu {
            Section("Your TVs") {
                ForEach(store.tvs) { t in
                    Button { store.switchTo(t) } label: {
                        if t.id == store.tv?.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            }
            Button { addingTV = true } label: { Label("Add another TV", systemImage: "plus") }
            Menu {
                ForEach(store.tvs) { t in
                    Button(role: .destructive) { forgetting = t } label: { Text(t.name) }
                }
            } label: { Label("Forget a TV", systemImage: "tv.slash") }
        } label: {
            HStack(spacing: 6) {
                Text(store.tv?.name ?? "Your TV").font(Look.font(30, .heavy)).foregroundStyle(.white).lineLimit(1)
                    .contentTransition(.opacity)
                    .id(store.tv?.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Look.dim)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.tv?.id)
        }
        .accessibilityLabel("TV: \(store.tv?.name ?? "none"). Switch TVs")
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("Power", "power", tint: Color(red: 1, green: 0.35, blue: 0.4)) { store.press(.powerToggle) }
                chip("Input", "rectangle.on.rectangle", tint: Look.cyan) { store.press(.inputNext) }
                chip("Home", "house.fill", tint: Look.violet) { store.press(.home) }
                chip("Mute", "speaker.slash.fill", tint: Look.magenta) { store.press(.muteToggle) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, _ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                Text(title).font(Look.font(14, .bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Look.card, in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(title)
    }
}

/// Glowing streak that shoots from a tapped tile up to the top of the screen.
private struct BeamView: View {
    let beam: AppsView.Beam
    @State private var go = false
    var body: some View {
        GeometryReader { _ in
            Capsule()
                .fill(LinearGradient(colors: [beam.color.opacity(0), beam.color, .white], startPoint: .bottom, endPoint: .top))
                .frame(width: 6, height: go ? 220 : 40)
                .shadow(color: beam.color, radius: 12)
                .shadow(color: .white.opacity(0.6), radius: 4)
                .position(x: beam.x, y: go ? -120 : beam.y)
                .opacity(go ? 0 : 1)
        }
        .onAppear { withAnimation(.easeIn(duration: 0.7)) { go = true } }
    }
}

private struct NowPlayingCard: View {
    let name: String
    let app: StreamingApp?
    let home: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = app?.colors ?? [Look.violet, Look.bg]
        HStack(spacing: 12) {
            EqualizerBars(color: .white).frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("NOW ON TV").font(Look.font(10, .heavy)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
                Text(name).font(Look.font(18, .heavy)).foregroundStyle(.white)
            }
            Spacer()
            Button(action: home) {
                Image(systemName: "house.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel("Go to the TV home screen")
        }
        .padding(14)
        .background {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let shift = reduceMotion ? 0 : sin(t * 0.5)
                LinearGradient(colors: [colors[0].opacity(0.75), colors[1].opacity(0.85), colors[0].opacity(0.55)],
                               startPoint: UnitPoint(x: -0.2 + shift * 0.3, y: 0), endPoint: UnitPoint(x: 1.2 + shift * 0.3, y: 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
        .shadow(color: colors[0].opacity(0.45), radius: 16, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct AppTile: View {
    let app: StreamingApp
    let isPlaying: Bool
    let launching: Bool
    let action: (CGRect) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero
    @State private var pressed = false
    @State private var flash = false
    @State private var aura = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Button(action: tap) { tileFace }
            .buttonStyle(PressReader(pressed: $pressed))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !reduceMotion else { return }
                        // Tilt toward the finger: -1...1 from the tile's center.
                        let w = max(frame.width, 1), h = max(frame.height, 1)
                        tilt = CGSize(width: max(-1, min(1, (v.location.x - w / 2) / (w / 2))),
                                      height: max(-1, min(1, (v.location.y - h / 2) / (h / 2))))
                    }
                    .onEnded { _ in tilt = .zero }
            )
            .onChange(of: pressed) { _, p in if !p { tilt = .zero } }
            .onChange(of: isPlaying) { _, on in startAura(on) }
            .onAppear { startAura(isPlaying) }
            .accessibilityLabel("Open \(app.name) on the TV")
    }

    private var tileFace: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft inner glow from the top-left and a diagonal light streak.
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 140)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .white.opacity(0.14), location: 0.45),
                                   .init(color: .clear, location: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                if isPlaying {
                    Label("On TV", systemImage: "tv.fill").font(Look.font(10, .heavy))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                Text(app.name).font(Look.font(19, .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .padding(14)
            if flash { Color.white.opacity(0.55).transition(.opacity) }
            if launching {
                Color.black.opacity(0.25)
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(isPlaying ? 0.95 : 0.45), .white.opacity(isPlaying ? 0.6 : 0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: isPlaying ? 2 : 1))
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(app.colors.first ?? Look.magenta)
                    .blur(radius: 18)
                    .opacity(aura ? 0.75 : 0.3)
                    .scaleEffect(aura ? 1.06 : 0.98)
            }
        }
        .shadow(color: (app.colors.first ?? .clear).opacity(0.35), radius: 10, y: 6)
        .rotation3DEffect(.degrees(Double(tilt.height) * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: tilt)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        .background(GeometryReader { g in
            Color.clear.onAppear { frame = g.frame(in: .named("apps")) }
                .onChange(of: g.frame(in: .named("apps"))) { _, f in frame = f }
        })
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func tap() {
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeOut(duration: 0.35)) { flash = false } }
        action(frame)
    }

    private func startAura(_ on: Bool) {
        aura = false
        guard on, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { aura = true }
    }
}

/// Reports a button's pressed state without changing its look.
private struct PressReader: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, p in pressed = p }
    }
}

struct EqualizerBars: View {
    let color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4) { i in
                    Capsule().fill(color)
                        .frame(width: 4, height: 6 + 16 * abs(sin(t * (2.2 + Double(i) * 0.7) + Double(i))))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Pick which apps show up on the main screen.
struct AppPicker: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let apps = store.catalog.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                ForEach(apps) { app in
                    Button { store.toggleFavorite(app) } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Text(app.name).font(Look.font(16, .semibold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: store.favorites.contains(app.name) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(store.favorites.contains(app.name) ? Look.cyan : Look.dim)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Look.bg)
            .searchable(text: $query, prompt: "Search apps")
            .navigationTitle("My apps")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
