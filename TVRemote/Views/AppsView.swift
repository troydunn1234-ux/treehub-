import SwiftUI

/// Your streaming apps as poster tiles. Tap one and it opens on the TV.
struct AppsView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var sheet: TVSheet? = (ProcessInfo.processInfo.arguments.contains("-demo") && ProcessInfo.processInfo.arguments.contains("-switcher")) ? .switcher : nil
    @State private var launching: String?
    @State private var appeared = false
    @State private var beam: Beam?

    struct Beam: Identifiable, Equatable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let color: Color
    }

    private let cols = [GridItem(.flexible(), spacing: Look.S.m), GridItem(.flexible(), spacing: Look.S.m)]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: Look.S.xl) {
                    header
                    Group {
                        if let now = store.nowPlaying {
                            NowPlayingHero(name: now, app: store.catalog.first { $0.name == now }, tvName: store.tv?.name ?? "your TV",
                                           onPlayPause: { play in store.press(play ? .play : .pause) },
                                           onHome: { store.press(.home) },
                                           onMute: { store.press(.muteToggle) })
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            IdleHero()
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.nowPlaying)

                    VStack(alignment: .leading, spacing: Look.S.m) {
                        SectionHeader("Quick actions")
                        HStack(spacing: Look.S.s) {
                            action("Power", "power", tint: Look.red) { store.press(.powerToggle) }
                            action("Input", "rectangle.on.rectangle", tint: Look.cyan) { store.press(.inputNext) }
                            action("Home", "house.fill", tint: Look.violet) { store.press(.home) }
                            action("Mute", "speaker.slash.fill", tint: Look.magenta) { store.press(.muteToggle) }
                        }
                    }

                    VStack(alignment: .leading, spacing: Look.S.m) {
                        SectionHeader(title: "Your apps") {
                            Button { editing = true } label: {
                                Text("Edit").font(Look.font(13, .heavy)).foregroundStyle(Look.cyan)
                                    .padding(.horizontal, Look.S.m).frame(minHeight: 32)
                                    .background(Look.cyan.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(SquishStyle())
                            .accessibilityLabel("Edit your apps")
                        }
                        LazyVGrid(columns: cols, spacing: Look.S.m) {
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
                                .offset(y: appeared || reduceMotion ? 0 : 28)
                                .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.035), value: appeared)
                                .contextMenu {
                                    Button(role: .destructive) { store.toggleFavorite(app) } label: { Label("Remove from my apps", systemImage: "minus.circle") }
                                }
                            }
                            Button { editing = true } label: {
                                VStack(spacing: Look.S.s) {
                                    Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                                        .frame(width: 48, height: 48)
                                        .glassCircle()
                                    Text("Add apps").font(Look.font(14, .heavy)).foregroundStyle(Look.dim)
                                }
                                .frame(maxWidth: .infinity).frame(height: AppTile.height)
                                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 7])))
                            }
                            .buttonStyle(SquishStyle())
                            .accessibilityLabel("Add apps")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, Look.S.xs)
                .padding(.bottom, Look.S.xxl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh() }

            if let b = beam { BeamView(beam: b).id(b.id).allowsHitTesting(false) }
        }
        .coordinateSpace(name: "apps")
        .sheet(isPresented: $editing) { AppPicker().environment(store) }
        .tvSheets($sheet, store: store)
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
        default: return "Late night"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Look.S.l) {
            HStack(spacing: Look.S.s) {
                TVSwitcherPill(action: { sheet = .switcher })
                Spacer(minLength: Look.S.s)
                statusPill
            }
            VStack(alignment: .leading, spacing: 2) {
                (Text(greeting) + Text(".").foregroundColor(Look.magenta))
                    .font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("What are we watching?").font(Look.font(16, .semibold)).foregroundStyle(Look.dim)
            }
        }
        .padding(.top, Look.S.s)
    }

    private var statusPill: some View {
        Button {
            guard !store.reachable, !store.reconnecting else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await store.reconnect(userInitiated: true) }
        } label: {
            HStack(spacing: 4) {
                if store.reconnecting {
                    ProgressView().controlSize(.mini).tint(.white).frame(width: 16, height: 16)
                } else {
                    LiveDot(color: store.reachable ? Look.live : .orange, size: 7, pulsing: store.reachable)
                        .frame(width: 16, height: 16)
                }
                Text(store.reconnecting ? "Searching…" : store.reachable ? "Live" : "Offline · Retry")
                    .font(Look.font(12, .heavy)).foregroundStyle(Color.white.opacity(store.reachable ? 0.85 : 1))
            }
            .padding(.leading, Look.S.s).padding(.trailing, Look.S.m).frame(minHeight: 36)
            .glassCapsule(tint: store.reachable ? .white : .orange, glow: store.reachable ? nil : .orange, strength: store.reachable ? 1 : 2)
            .animation(.snappy, value: store.reconnecting)
        }
        .buttonStyle(SquishStyle())
        .disabled(store.reachable)
        .accessibilityLabel(store.reachable ? "Connected" : "TV offline. Tap to search for it again.")
    }

    private func action(_ title: String, _ symbol: String, tint: Color, run: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            run()
        } label: {
            VStack(spacing: Look.S.s) {
                Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.16), in: Circle())
                    .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                    .shadow(color: tint.opacity(0.45), radius: 8)
                Text(title).font(Look.font(12, .heavy)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity).frame(height: 84)
            .glass(20)
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

/// Cinematic "Now on TV" card: the app's colors, big type, live bars and quick controls.
private struct NowPlayingHero: View {
    let name: String
    let app: StreamingApp?
    let tvName: String
    let onPlayPause: (Bool) -> Void
    let onHome: () -> Void
    let onMute: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = true
    @State private var glow = false

    var body: some View {
        let colors = app?.colors ?? [Look.violet, Look.bg]
        let c0 = colors.first ?? Look.violet
        let c1 = colors.count > 1 ? colors[1] : Look.bg
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Look.S.s) {
                EqualizerBars(color: .white).frame(width: 18, height: 14)
                CapsLabel("Now on TV", color: .white.opacity(0.85), size: 11)
                Spacer()
                Text(tvName).font(Look.font(11, .bold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    .padding(.horizontal, Look.S.s).padding(.vertical, Look.S.xs)
                    .background(.black.opacity(0.25), in: Capsule())
            }
            Spacer(minLength: Look.S.m)
            Text(name).font(Look.display(40)).tracking(-1).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.55)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            Spacer(minLength: Look.S.m)
            HStack(spacing: Look.S.m) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    playing.toggle()
                    onPlayPause(playing)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 20, weight: .black)).foregroundStyle(c1)
                        .frame(width: 56, height: 56)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(playing ? "Pause" : "Play")
                control("house.fill", "Go to the TV home screen", onHome)
                control("speaker.slash.fill", "Mute", onMute)
                Spacer()
            }
        }
        .padding(Look.S.l + 2)
        .frame(height: 210)
        .background {
            ZStack {
                TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let shift = reduceMotion ? 0 : sin(t * 0.45)
                    LinearGradient(colors: [c0, c1, c0.opacity(0.8)],
                                   startPoint: UnitPoint(x: -0.3 + shift * 0.3, y: 0), endPoint: UnitPoint(x: 1.3 + shift * 0.3, y: 1))
                }
                // Giant watermark of the app name.
                Text(name.uppercased())
                    .font(.system(size: 120, weight: .black, design: .rounded)).tracking(-4)
                    .foregroundStyle(.white.opacity(0.08))
                    .lineLimit(1).fixedSize()
                    .offset(x: 40, y: -10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                RadialGradient(colors: [.white.opacity(0.30), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(c0)
                .blur(radius: 26).opacity(glow ? 0.65 : 0.35).scaleEffect(glow ? 1.0 : 0.94).offset(y: 10)
        }
        .onAppear {
            guard !reduceMotion else { glow = true; return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now on TV: \(name)")
    }

    private func control(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            run()
        } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
    }
}

/// Shown when nothing is playing.
private struct IdleHero: View {
    var body: some View {
        HStack(spacing: Look.S.l) {
            Image(systemName: "play.tv.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Look.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Look.magenta.opacity(0.5), radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing playing").font(Look.font(19, .heavy)).foregroundStyle(.white)
                Text("Tap an app below to start it on your TV.").font(Look.font(13, .semibold)).foregroundStyle(Look.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(Look.S.l)
        .glass(28, tint: Look.violet, glow: Look.violet)
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

    static let height: CGFloat = 150

    private var initial: String { String(app.name.prefix(1)).uppercased() }

    private var tileFace: some View {
        let c0 = app.colors.first ?? Look.violet
        let c1 = app.colors.count > 1 ? app.colors[1] : Look.bg
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Poster watermark: a giant initial bleeding off the top-right corner.
            Text(initial)
                .font(.system(size: 150, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .fixedSize()
                .offset(x: 24, y: -18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            // Light from the top-left, a diagonal sheen, and a dark floor for the title.
            RadialGradient(colors: [.white.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 150)
            LinearGradient(stops: [.init(color: .clear, location: 0.30), .init(color: .white.opacity(0.13), location: 0.42),
                                   .init(color: .clear, location: 0.54)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                if isPlaying {
                    HStack(spacing: 5) {
                        EqualizerBars(color: .white, bars: 3).frame(width: 10, height: 9)
                        Text("ON TV").font(Look.font(10, .black)).tracking(1.2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                Text(app.name).font(Look.display(21)).tracking(-0.4).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            }
            .padding(Look.S.l - 2)
            if flash { Color.white.opacity(0.55).transition(.opacity) }
            if launching {
                Color.black.opacity(0.3)
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(isPlaying ? 0.95 : 0.45), .white.opacity(isPlaying ? 0.55 : 0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: isPlaying ? 2 : 1))
        .background {
            if isPlaying {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(c0)
                    .blur(radius: 18)
                    .opacity(aura ? 0.8 : 0.35)
                    .scaleEffect(aura ? 1.05 : 0.98)
            }
        }
        .shadow(color: c0.opacity(0.35), radius: 12, y: 8)
        .rotation3DEffect(.degrees(Double(tilt.height) * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: tilt)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        .background(GeometryReader { g in
            Color.clear.onAppear { frame = g.frame(in: .named("apps")) }
                .onChange(of: g.frame(in: .named("apps"))) { _, f in frame = f }
        })
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Text(String(app.name.prefix(1))).font(Look.display(17)).foregroundStyle(.white.opacity(0.9)))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                                .frame(width: 40, height: 40)
                            Text(app.name).font(Look.font(16, .bold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: store.favorites.contains(app.name) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(store.favorites.contains(app.name) ? Look.cyan : Look.dim)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    .accessibilityLabel(store.favorites.contains(app.name) ? "\(app.name), in your apps" : "Add \(app.name)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .searchable(text: $query, prompt: "Search apps")
            .navigationTitle("My apps")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
