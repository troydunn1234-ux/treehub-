import SwiftUI
import UIKit

/// The remote: a sculpted glass controller — swipe pad, OK disc, nav cluster, media keys and volume / mute rockers.
struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @State private var playing = true
    @State private var bump = false
    @State private var sheet: TVSheet?

    var body: some View {
        GeometryReader { geo in
            // Size the pad to whatever room is left, so nothing ends up under the tab bar.
            let pad = max(160, min(geo.size.width - 92, geo.size.height - 360 - (store.reachable ? 0 : 48), 290))
            VStack(spacing: Look.S.m) {
                if !store.reachable {
                    Button {
                        guard !store.reconnecting else { return }
                        Task { await store.reconnect(userInitiated: true) }
                    } label: {
                        Label(store.reconnecting ? "Searching for your TV…" : "Can't reach your TV — tap to retry", systemImage: "wifi.exclamationmark")
                            .font(Look.font(13, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Look.S.l).frame(minHeight: 36)
                            .frame(maxWidth: .infinity)
                            .glassCapsule(tint: .orange, glow: .orange, strength: 2)
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityLabel("Can't reach your TV. Is it on and on the same Wi-Fi? Tap to search again.")
                }

                VStack(spacing: Look.S.m) {
                    topRow
                    Spacer(minLength: 0)
                    TouchPad(size: pad) { key, heavy in send(key, heavy: heavy) }
                    Spacer(minLength: 0)
                    navCluster
                    controlDeck
                }
                .padding(.horizontal, 14)
                .padding(.top, Look.S.l)
                .padding(.bottom, Look.S.l)
                .background(RemoteBody())
            }
            .padding(.horizontal, 14)
            .padding(.top, Look.S.xs)
            .padding(.bottom, Look.S.s)
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.reachable)
        }
        .tvSheets($sheet, store: store)
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(spacing: Look.S.s) {
            Button { send(.powerToggle, heavy: true) } label: {
                Image(systemName: "power")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(RadialGradient(colors: [Look.red, Color(red: 0.55, green: 0.05, blue: 0.15)],
                                                             center: .topLeading, startRadius: 2, endRadius: 60)))
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)).padding(2))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: Look.red.opacity(0.6), radius: 12)
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel("Power")

            Spacer(minLength: 0)

            TVSwitcherPill(action: { sheet = .switcher }, subtitle: store.nowPlaying.map { "▶︎ \($0)" })
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.nowPlaying)

            Spacer(minLength: 0)

            KeyButton(symbol: "rectangle.on.rectangle", label: "Input", size: 48) { send(.inputNext) }
        }
    }

    /// Back / Home / Menu as one segmented glass bar.
    private var navCluster: some View {
        HStack(spacing: 0) {
            segment("arrow.uturn.backward", "Back") { send(.back) }
            divider
            segment("house.fill", "Home") { send(.home) }
            divider
            segment("line.3.horizontal", "Menu") { send(.menu) }
        }
        .frame(height: 54)
        .glassCapsule()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 24)
    }

    private func segment(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                Text(label).font(Look.font(14, .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    /// Volume rocker · media keys · mute/CC rocker.
    private var controlDeck: some View {
        HStack(alignment: .center, spacing: Look.S.s) {
            VStack(spacing: 0) {
                HoldButton(symbol: "plus", label: "Volume up") { volume(up: true) }
                Text("VOL").font(Look.font(10, .black)).tracking(1.8).foregroundStyle(Look.dim)
                    .frame(height: 16)
                    .accessibilityHidden(true)
                HoldButton(symbol: "minus", label: "Volume down") { volume(up: false) }
            }
            .frame(width: 58)
            .glassCapsule()
            .overlay {
                Capsule().strokeBorder(Look.accent, lineWidth: 2).opacity(bump ? 1 : 0)
                    .shadow(color: Look.magenta, radius: bump ? 10 : 0)
                    .animation(.easeOut(duration: 0.25), value: bump)
            }

            VStack(spacing: Look.S.m) {
                HStack(spacing: 6) {
                    KeyButton(symbol: "backward.fill", label: "Rewind", size: 46) { send(.seekBack) }
                    Button {
                        send(playing ? .pause : .play, heavy: true)
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Look.accent))
                            .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)).padding(2))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                            .shadow(color: Look.magenta.opacity(0.6), radius: 14)
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    KeyButton(symbol: "forward.fill", label: "Fast forward", size: 46) { send(.seekForward) }
                }
                HStack(spacing: Look.S.s) {
                    SmallKey(title: "Info") { send(.info) }
                    SmallKey(title: "Exit") { send(.exit) }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                KeyButton(symbol: "speaker.slash.fill", label: "Mute", size: 54, plain: true) { send(.muteToggle) }
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 26, height: 1)
                    .padding(.vertical, Look.S.xs)
                KeyButton(symbol: "captions.bubble.fill", label: "Closed captions", size: 54, plain: true) { send(.ccToggle) }
            }
            .padding(.vertical, 3)
            .frame(width: 58)
            .glassCapsule()
        }
    }

    // MARK: Actions

    private func send(_ key: VizioClient.Key, heavy: Bool = false) {
        UIImpactFeedbackGenerator(style: heavy ? .medium : .light).impactOccurred()
        store.press(key)
    }

    private func volume(up: Bool) {
        send(up ? .volumeUp : .volumeDown)
        bump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { bump = false }
    }
}

/// The physical controller's body: a tall glass slab with a lit rim.
private struct RemoteBody: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.09), Look.bgDeep.opacity(0.55), Color.white.opacity(0.03)],
                                      startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(colors: [Look.violet.opacity(0.18), .clear], center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 260))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center), lineWidth: 3)
                .blur(radius: 2)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), Look.violet.opacity(0.45)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .shadow(color: Look.violet.opacity(0.18), radius: 30)
    }
}

// MARK: - Touch pad

private struct TrailDot { let p: CGPoint; let t: Date }
private struct Ripple { let p: CGPoint; let t: Date }
private struct Spark { let p: CGPoint; let v: CGVector; let t: Date }

private struct TouchPad: View {
    let size: CGFloat
    let onKey: (VizioClient.Key, Bool) -> Void
    @State private var trail: [TrailDot] = []
    @State private var ripples: [Ripple] = []
    @State private var anchor: CGPoint?
    @State private var presses = 0
    @State private var flash: VizioClient.Key?
    @State private var flashTick = 0
    @State private var touching = false
    @State private var sparks: [Spark] = []
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            surface
                .gesture(padGesture)
                .accessibilityElement()
                .accessibilityLabel("Touch pad. Swipe to move, tap to select.")
                .accessibilityAddTraits(.allowsDirectInteraction)

            edgeButton(.up, "chevron.up", x: 0, y: -(size / 2 - 32))
            edgeButton(.down, "chevron.down", x: 0, y: size / 2 - 32)
            edgeButton(.left, "chevron.left", x: -(size / 2 - 32), y: 0)
            edgeButton(.right, "chevron.right", x: size / 2 - 32, y: 0)

            Button { fireOK(at: CGPoint(x: size / 2, y: size / 2)) } label: {
                Text("OK")
                    .font(Look.display(24)).tracking(1)
                    .foregroundStyle(.white)
                    .frame(width: 94, height: 94)
                    .background(
                        Circle().fill(RadialGradient(colors: [Look.violet, Look.magenta.opacity(0.9)],
                                                     center: .topLeading, startRadius: 4, endRadius: 110))
                    )
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)).padding(3))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .background(Circle().fill(Color.black.opacity(0.5)).padding(-8).blur(radius: 6))
                    .shadow(color: Look.magenta.opacity(breathe ? 0.85 : 0.5), radius: breathe ? 24 : 16)
                    .scaleEffect(breathe ? 1.03 : 1.0)
            }
            .buttonStyle(SquishStyle(scale: 0.9))
            .accessibilityLabel("OK")
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var surface: some View {
        ZStack {
            // Sculpted well: dark recessed disc with an inner shadow ring.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.10, green: 0.07, blue: 0.20), Look.bgDeep],
                                     center: .center, startRadius: 10, endRadius: size / 2)
                    .shadow(.inner(color: .black.opacity(0.85), radius: 14, x: 0, y: 8))
                    .shadow(.inner(color: Look.violet.opacity(0.35), radius: 6, x: 0, y: -3)))
            ForEach(1..<4, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: size * CGFloat(i) / 4 + 40, height: size * CGFloat(i) / 4 + 40)
            }
            // Tick marks around the rim.
            ForEach(0..<24, id: \.self) { i in
                Capsule().fill(Color.white.opacity(i % 6 == 0 ? 0 : 0.10))
                    .frame(width: 2, height: 6)
                    .offset(y: -(size / 2 - 12))
                    .rotationEffect(.degrees(Double(i) * 15))
            }
            Circle()
                .strokeBorder(Look.accent, lineWidth: touching ? 3 : 2)
                .shadow(color: Look.violet.opacity(touching ? 0.9 : 0.45), radius: touching ? 18 : 10)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .padding(-7)

            TimelineView(.animation(minimumInterval: 1 / 60, paused: trail.isEmpty && ripples.isEmpty && sparks.isEmpty)) { tl in
                let now = tl.date
                Canvas { ctx, _ in
                    for d in trail {
                        let age = now.timeIntervalSince(d.t)
                        guard age < 0.5 else { continue }
                        let k = 1 - age / 0.5
                        let r = CGFloat(4 + 14 * k)
                        ctx.fill(Path(ellipseIn: CGRect(x: d.p.x - r, y: d.p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Look.cyan.opacity(0.45 * k)))
                    }
                    for rp in ripples {
                        let age = now.timeIntervalSince(rp.t)
                        guard age < 0.6 else { continue }
                        let k = age / 0.6
                        let r = CGFloat(10 + 90 * k)
                        ctx.stroke(Path(ellipseIn: CGRect(x: rp.p.x - r, y: rp.p.y - r, width: r * 2, height: r * 2)),
                                   with: .color(Look.magenta.opacity(0.8 * (1 - k))), lineWidth: 3)
                    }
                    for sp in sparks {
                        let age = now.timeIntervalSince(sp.t)
                        guard age < 0.45 else { continue }
                        let k = age / 0.45
                        let x = sp.p.x + sp.v.dx * CGFloat(k)
                        let y = sp.p.y + sp.v.dy * CGFloat(k)
                        let r = CGFloat(3.5 * (1 - k) + 0.5)
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color((Int(sp.v.dx + sp.v.dy) % 2 == 0 ? Look.cyan : Look.magenta).opacity(1 - k)))
                    }
                }
            }
            .allowsHitTesting(false)

            if let f = flash {
                Image(systemName: arrowSymbol(f))
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(Look.accent)
                    .shadow(color: Look.cyan.opacity(0.8), radius: 12)
                    .offset(arrowOffset(f))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .id(flashTick)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: flashTick)
        .animation(.easeOut(duration: 0.2), value: touching)
    }

    private func edgeButton(_ key: VizioClient.Key, _ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        let lit = flash == key
        return Button { fire(key) } label: {
            Image(systemName: symbol)
                .font(Look.font(18, .heavy))
                .foregroundStyle(lit ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.85)))
                .shadow(color: Look.cyan.opacity(lit ? 0.9 : 0), radius: lit ? 10 : 0)
                .scaleEffect(lit ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: lit)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(scale: 0.85))
        .offset(x: x, y: y)
        .accessibilityLabel(label(for: key))
    }

    private var padGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if anchor == nil {
                    anchor = v.startLocation
                    presses = 0
                    touching = true
                }
                trail.append(TrailDot(p: v.location, t: Date()))
                if trail.count > 80 { trail.removeFirst(trail.count - 80) }
                guard let a = anchor else { return }
                let dx = v.location.x - a.x
                let dy = v.location.y - a.y
                let need: CGFloat = presses == 0 ? 30 : 60
                if max(abs(dx), abs(dy)) >= need {
                    let key: VizioClient.Key = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    fire(key, from: v.location)
                    anchor = v.location
                    presses += 1
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                if presses == 0 && moved < 14 { fireOK(at: v.location) }
                anchor = nil
                presses = 0
                touching = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let cut = Date().addingTimeInterval(-0.7)
                    trail.removeAll { $0.t < cut }
                    ripples.removeAll { $0.t < cut }
                }
            }
    }

    private func fire(_ key: VizioClient.Key, from point: CGPoint? = nil) {
        onKey(key, false)
        if !reduceMotion {
            // A short burst of sparks flying the way you swiped.
            let origin = point ?? CGPoint(x: size / 2, y: size / 2)
            let (ux, uy): (CGFloat, CGFloat) = {
                switch key {
                case .up: return (0, -1)
                case .down: return (0, 1)
                case .left: return (-1, 0)
                default: return (1, 0)
                }
            }()
            let now = Date()
            for i in 0..<10 {
                let spread = CGFloat.random(in: -0.45...0.45)
                let speed = CGFloat.random(in: 40...95)
                let vx = (ux - uy * spread) * speed
                let vy = (uy + ux * spread) * speed
                sparks.append(Spark(p: origin, v: CGVector(dx: vx + CGFloat(i % 2), dy: vy), t: now))
            }
            if sparks.count > 120 { sparks.removeFirst(sparks.count - 120) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let cut = Date().addingTimeInterval(-0.5)
                sparks.removeAll { $0.t < cut }
            }
        }
        flash = key
        flashTick += 1
        let tick = flashTick
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if flashTick == tick { withAnimation(.easeOut(duration: 0.2)) { flash = nil } }
        }
    }

    private func fireOK(at p: CGPoint) {
        ripples.append(Ripple(p: p, t: Date()))
        onKey(.ok, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let cut = Date().addingTimeInterval(-0.65)
            ripples.removeAll { $0.t < cut }
        }
    }

    private func arrowSymbol(_ k: VizioClient.Key) -> String {
        switch k {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        default: return "chevron.right"
        }
    }

    private func arrowOffset(_ k: VizioClient.Key) -> CGSize {
        let d = size * 0.22
        switch k {
        case .up: return CGSize(width: 0, height: -d)
        case .down: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: -d, height: 0)
        default: return CGSize(width: d, height: 0)
        }
    }

    private func label(for k: VizioClient.Key) -> String {
        switch k {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        default: return "Right"
        }
    }
}

// MARK: - Buttons

/// Round glass key.
private struct KeyButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 48
    var plain = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .modifier(KeyFace(plain: plain))
                .contentShape(Circle())
        }
        .buttonStyle(SquishStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

private struct KeyFace: ViewModifier {
    let plain: Bool
    func body(content: Content) -> some View {
        if plain { content } else { content.glassCircle() }
    }
}

/// Small text key (Info, Exit).
private struct SmallKey: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Look.font(11, .black)).tracking(1.4).foregroundStyle(.white.opacity(0.85))
                .frame(width: 70, height: 36)
                .glassCapsule()
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(scale: 0.9))
        .accessibilityLabel(title)
    }
}

/// Fires once on touch-down, then repeats every 0.18 s while held.
private struct HoldButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var holding = false
    @State private var loop: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(holding ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.05)), in: Circle())
            .shadow(color: holding ? Look.magenta.opacity(0.6) : .clear, radius: 10)
            .frame(width: 58, height: 54)
            .contentShape(Rectangle())
            .scaleEffect(holding ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: holding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        action()
                        loop?.cancel()
                        loop = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            while !Task.isCancelled && holding {
                                action()
                                try? await Task.sleep(nanoseconds: 180_000_000)
                            }
                        }
                    }
                    .onEnded { _ in
                        holding = false
                        loop?.cancel()
                        loop = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

#Preview {
    RemoteView()
        .environment(TVStore())
        .preferredColorScheme(.dark)
}
