import SwiftUI
import UIKit

/// The remote: a big swipe pad, edge chevrons, OK disc, nav pills, media controls and a hold-to-repeat volume rocker.
struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @State private var playing = true
    @State private var volTick = 0
    @State private var volUp = true
    @State private var bump = false

    var body: some View {
        GeometryReader { geo in
            // Size the pad to whatever room is left, so nothing ends up under the tab bar.
            let pad = min(geo.size.width - 64, max(190, geo.size.height - 372), 300)
            VStack(spacing: 16) {
                if !store.reachable {
                    Label("Can't reach your TV — is it on and on the same Wi-Fi?", systemImage: "wifi.exclamationmark")
                        .font(Look.font(13, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.28), in: Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.6), lineWidth: 1))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                topRow

                Spacer(minLength: 0)

                TouchPad(size: pad) { key, heavy in send(key, heavy: heavy) }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    PillButton(symbol: "arrow.uturn.backward", label: "Back") { send(.back) }
                    PillButton(symbol: "house.fill", label: "Home") { send(.home) }
                    PillButton(symbol: "line.3.horizontal", label: "Menu") { send(.menu) }
                }

                controlDeck
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.reachable)
        }
    }

    /// Volume on the left, play/pause in the middle, mute on the right: one tidy row.
    private var controlDeck: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    HoldButton(symbol: "minus", label: "Volume down") { volume(up: false) }
                    Rectangle().fill(Look.line).frame(width: 1, height: 26)
                    HoldButton(symbol: "plus", label: "Volume up") { volume(up: true) }
                }
                .background(Look.card, in: Capsule())
                .overlay(Capsule().stroke(Look.line, lineWidth: 1))
                .overlay(alignment: .center) {
                    Capsule().stroke(Look.accent, lineWidth: bump ? 2 : 0).opacity(bump ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: bump)
                }
                Text("VOLUME").font(Look.font(9, .heavy)).tracking(1.5).foregroundStyle(Look.dim)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                RoundButton(symbol: "backward.fill", label: "Rewind", size: 44) { send(.seekBack) }
                Button {
                    send(playing ? .pause : .play, heavy: true)
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(Look.font(22, .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Look.accent))
                        .shadow(color: Look.magenta.opacity(0.55), radius: 12)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(playing ? "Pause" : "Play")
                RoundButton(symbol: "forward.fill", label: "Fast forward", size: 44) { send(.seekForward) }
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                RoundButton(symbol: "speaker.slash.fill", label: "Mute", size: 52) { send(.muteToggle) }
                Text("MUTE").font(Look.font(9, .heavy)).tracking(1.5).foregroundStyle(Look.dim)
            }
        }
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(spacing: 12) {
            Button { send(.powerToggle, heavy: true) } label: {
                Image(systemName: "power")
                    .font(Look.font(20, .heavy))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.4))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.red.opacity(0.12)))
                    .overlay(Circle().stroke(Color.red.opacity(0.85), lineWidth: 2))
                    .shadow(color: .red.opacity(0.7), radius: 10)
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel("Power")

            Spacer(minLength: 0)

            if let now = store.nowPlaying {
                HStack(spacing: 6) {
                    Circle().fill(Look.cyan).frame(width: 7, height: 7).shadow(color: Look.cyan, radius: 4)
                    Text(now).font(Look.font(13, .bold)).foregroundStyle(.white).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Look.card, in: Capsule())
                .overlay(Capsule().stroke(Look.line, lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Now playing: \(now)")
            }

            Spacer(minLength: 0)

            RoundButton(symbol: "arrow.left.arrow.right.square", label: "Input") { send(.inputNext) }
            RoundButton(symbol: "captions.bubble", label: "Closed captions") { send(.ccToggle) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.nowPlaying)
    }

    // MARK: Actions

    private func send(_ key: VizioClient.Key, heavy: Bool = false) {
        UIImpactFeedbackGenerator(style: heavy ? .medium : .light).impactOccurred()
        store.press(key)
    }

    private func volume(up: Bool) {
        volUp = up
        volTick += 1
        send(up ? .volumeUp : .volumeDown)
        bump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { bump = false }
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

            edgeButton(.up, "chevron.up", x: 0, y: -(size / 2 - 28))
            edgeButton(.down, "chevron.down", x: 0, y: size / 2 - 28)
            edgeButton(.left, "chevron.left", x: -(size / 2 - 28), y: 0)
            edgeButton(.right, "chevron.right", x: size / 2 - 28, y: 0)

            Button { fireOK(at: CGPoint(x: size / 2, y: size / 2)) } label: {
                Text("OK")
                    .font(Look.font(22, .black))
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 92)
                    .background(
                        Circle().fill(RadialGradient(colors: [Look.violet, Look.magenta.opacity(0.85)],
                                                     center: .topLeading, startRadius: 4, endRadius: 110))
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
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
            Circle()
                .fill(RadialGradient(colors: [Look.violet.opacity(0.20), Look.bg.opacity(0.65)],
                                     center: .center, startRadius: 10, endRadius: size / 2))
            ForEach(1..<4, id: \.self) { i in
                Circle()
                    .stroke(Look.line, lineWidth: 1)
                    .frame(width: size * CGFloat(i) / 4 + 40, height: size * CGFloat(i) / 4 + 40)
            }
            Circle()
                .stroke(Look.accent, lineWidth: touching ? 3 : 2)
                .shadow(color: Look.violet.opacity(touching ? 0.9 : 0.4), radius: touching ? 16 : 8)

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
                .frame(width: 44, height: 44)
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

private struct RoundButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Look.font(size * 0.36, .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Look.card))
                .overlay(Circle().stroke(Look.line, lineWidth: 1))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
    }
}

private struct PillButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(Look.font(15, .bold))
                Text(label).font(Look.font(14, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Look.card, in: Capsule())
            .overlay(Capsule().stroke(Look.line, lineWidth: 1))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
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
            .font(Look.font(22, .black))
            .foregroundStyle(.white)
            .frame(width: 58, height: 52)
            .contentShape(Rectangle())
            .background(holding ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.clear), in: Capsule())
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
