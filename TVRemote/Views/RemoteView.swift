import SwiftUI
import UIKit

/// The remote, laid out like a real one: Power and Input up top with the TV (and whether it's connected) between
/// them, your apps, the swipe pad with its OK disc, Back / Home / Menu / Search / Keyboard, then volume, play and mute.
/// Every key clicks on touch-down (a crisp haptic and a little key travel), and the remote glows softly in the color
/// of the app that's on the TV.
struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playing = true
    @State private var bump = false
    @State private var sheet: TVSheet?
    /// Goes up with every key sent: the status light under the TV name blinks like a remote's LED.
    @State private var sent = 0
    /// Goes up with every Power press: the power-on moment.
    @State private var powerTick = 0

    /// The color of the app that's on the TV (the brand violet when nothing is on).
    private var tint: Color { store.nowPlaying.flatMap { StreamingApp(name: $0).colors.first } ?? Look.violet }

    /// Everything but the pad: outer padding 12, slab padding 28, top row 52, apps 44, nav bar 52, deck 124,
    /// six gaps of 10, and a little slack.
    private static let fixedHeight: CGFloat = 12 + 28 + 52 + 44 + 52 + 124 + 60 + 23

    var body: some View {
        GeometryReader { geo in
            let offline = !store.reachable
            // Size the pad to whatever room is left, so nothing ends up under the tab bar.
            let pad = max(150, min(geo.size.width - 92, geo.size.height - Self.fixedHeight - (offline ? 54 : 0), 290))
            VStack(spacing: 10) {
                if offline {
                    offlineBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(spacing: 10) {
                    topRow
                    quickLaunch
                    Spacer(minLength: 0)
                    TouchPad(size: pad, tint: tint, powerTick: powerTick) { key in send(key) }
                    Spacer(minLength: 0)
                    navCluster
                    controlDeck
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(RemoteBody(tint: tint, glowKey: store.nowPlaying ?? ""))
            }
            .padding(.horizontal, 14)
            .padding(.top, Look.S.xs)
            .padding(.bottom, Look.S.s)
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.reachable)
        }
        .sensoryFeedback(.success, trigger: store.reachable) { old, new in !old && new }
        .tvSheets($sheet, store: store)
    }

    // MARK: Status

    /// The TV can't be reached: say so plainly, with one tap to look for it again.
    private var offlineBar: some View {
        let name = store.tv?.name ?? "your TV"
        let searching = store.reconnecting
        return Button {
            guard !store.reconnecting else { return }
            Task { await store.reconnect(userInitiated: true) }
        } label: {
            HStack(spacing: Look.S.s) {
                Group {
                    if searching {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(width: 22)
                Text(searching ? "Looking for \(name)…" : "Can't reach \(name)")
                    .font(Look.font(14, .bold))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Look.S.s)
                if !searching {
                    // Black on orange: readable (AA) where white on orange isn't.
                    Text("Retry")
                        .font(Look.font(14, .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Color.orange, in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, Look.S.l).padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .glassCapsule(tint: .orange, glow: .orange, strength: 1.6)
            .animation(.snappy, value: searching)
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.97, feel: searching ? nil : .impact(weight: .light)))
        .accessibilityLabel(searching ? "Looking for \(name) on your Wi-Fi" : "Can't reach \(name). Retry")
        .accessibilityHint(searching ? Text("") : Text("Is it on and on the same Wi-Fi? Searches for it again."))
    }

    // MARK: Rows

    /// Power on the left, Input on the right, the TV and its status light in between: the top of a real remote.
    private var topRow: some View {
        HStack(spacing: Look.S.s) {
            powerKey
            Spacer(minLength: 0)
            TVSwitcherPill(action: { sheet = .switcher }, showsStatus: true, blink: sent)
            Spacer(minLength: 0)
            KeyButton(text: "INPUT", label: "Input", size: 52) { send(.inputNext) }
                .accessibilityHint("Switches the TV to its next input")
        }
    }

    private var powerKey: some View {
        Button {
            powerTick += 1
            send(.powerToggle)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : powerTick)
                .frame(width: 52, height: 52)
                .background(Circle().fill(RadialGradient(colors: [Look.red, Color(red: 0.55, green: 0.05, blue: 0.15)],
                                                         center: .topLeading, startRadius: 2, endRadius: 60)))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)).padding(2))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Look.red.opacity(0.5), radius: 10)
                // The power-on moment: a ring swells out of the key (the pad's "screen" lights up too).
                .background { if !reduceMotion { PulseRing(trigger: powerTick, color: Look.red) } }
                .contentShape(Circle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.86, feel: .impact(weight: .heavy)))
        .accessibilityLabel("Power")
    }

    /// One tap to open a favorite app (Netflix, YouTube, Hulu, Prime Video, Disney+ by default) on the TV.
    /// Calm glass chips with each app's color dot; the app that's on the TV lights up in its color and is
    /// scrolled into view.
    private var quickLaunch: some View {
        let apps = Array(store.favoriteApps.prefix(6))
        return ScrollViewReader { proxy in
            quickLaunchRow(apps)
                .onAppear { DispatchQueue.main.async { reveal(proxy, in: apps, animated: false) } }
                .onChange(of: store.nowPlaying) { _, _ in reveal(proxy, in: apps, animated: true) }
        }
        .frame(height: 44)
    }

    /// Bring the app that's on the TV into view (it may be the 5th or 6th chip, past the screen's edge).
    private func reveal(_ proxy: ScrollViewProxy, in apps: [StreamingApp], animated: Bool) {
        guard let now = store.nowPlaying, apps.contains(where: { $0.name == now }) else { return }
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(now, anchor: .center) }
        } else {
            proxy.scrollTo(now, anchor: .center)
        }
    }

    private func quickLaunchRow(_ apps: [StreamingApp]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(apps) { app in
                    let on = store.nowPlaying == app.name
                    let c = app.colors.first ?? Look.violet
                    Button {
                        Task { await store.launch(app) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(c).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                            Text(app.name)
                                .font(Look.font(13, .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(c.opacity(on ? 0.45 : 0.14)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.85 : 0.14), lineWidth: on ? 1.5 : 1))
                        .shadow(color: on ? c.opacity(0.6) : .clear, radius: 10)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RemoteKeyStyle(scale: 0.93, feel: .selection))
                    .accessibilityLabel(on ? "\(app.name), on the TV now" : "Open \(app.name) on the TV")
                    .id(app.name)
                }
            }
            .padding(.horizontal, 2)
            .animation(.easeInOut(duration: 0.35), value: store.nowPlaying)
        }
        .frame(height: 44)
    }

    /// Back · Home · Menu · Search · Keyboard as one glass bar, each key with a plain label.
    private var navCluster: some View {
        HStack(spacing: 0) {
            segment("arrow.uturn.backward", "Back") { send(.back) }
            divider
            segment("house.fill", "Home") { send(.home) }
            divider
            segment("line.3.horizontal", "Menu") { send(.menu) }
            divider
            // searchOnTV plays its own tap.
            segment("magnifyingglass", "Search", feel: nil) {
                sent += 1
                store.searchOnTV()
            }
            divider
            segment("keyboard", "Keyboard", spoken: "Type on TV") { store.openKeyboard() }
                .accessibilityHint("Type on your TV with your phone's keyboard")
        }
        .frame(height: 52)
        .glassCapsule()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 24)
    }

    private func segment(_ symbol: String, _ label: String, spoken: String? = nil,
                         feel: SensoryFeedback? = .impact(flexibility: .rigid, intensity: 0.6),
                         _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                Text(label).font(Look.font(10, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.88, feel: feel))
        .accessibilityLabel(spoken ?? label)
    }

    /// Volume rocker · play keys with Info / Exit / Sleep · Mute and CC.
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
                    KeyButton(symbol: "backward.fill", label: "Rewind", size: 50) { send(.seekBack) }
                    playKey
                    KeyButton(symbol: "forward.fill", label: "Fast forward", size: 50) { send(.seekForward) }
                }
                HStack(spacing: 6) {
                    SmallKey(title: "Info", width: 58) { send(.info) }
                    SmallKey(title: "Exit", width: 58) { send(.exit) }
                    // Sleep timer: SLEEP, or the countdown while it runs (TVRemote/Views/SleepTimerViews.swift).
                    SleepTimerKey(width: 58)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                KeyButton(symbol: "speaker.slash.fill", label: "Mute", size: 54, plain: true) { send(.muteToggle) }
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 26, height: 1)
                    .padding(.vertical, Look.S.xs)
                KeyButton(text: "CC", label: "Closed captions", size: 54, plain: true) { send(.ccToggle) }
            }
            .padding(.vertical, 3)
            .frame(width: 58)
            .glassCapsule()
        }
    }

    private var playKey: some View {
        Button {
            send(playing ? .pause : .play)
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
                .shadow(color: Look.magenta.opacity(0.45), radius: 12)
                .contentShape(Circle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.88, feel: .impact(flexibility: .solid, intensity: 0.85)))
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    // MARK: Actions

    /// Haptics come from the keys themselves (on touch-down) and from the pad's swipes, so this only sends.
    private func send(_ key: RemoteKey) {
        sent += 1
        store.press(key)
    }

    private func volume(up: Bool) {
        send(up ? .volumeUp : .volumeDown)
        bump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { bump = false }
    }
}

/// The physical controller's body: a tall glass slab with a lit rim, glowing inside in the color of what's on.
private struct RemoteBody: View {
    var tint: Color = Look.violet
    /// What the glow is for (the app's name): the glow cross-fades when it changes.
    var glowKey = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.09), Look.bgDeep.opacity(0.55), Color.white.opacity(0.03)],
                                      startPoint: .top, endPoint: .bottom))
            ZStack {
                shape.fill(RadialGradient(colors: [tint.opacity(0.20), .clear], center: .init(x: 0.5, y: 0.40), startRadius: 0, endRadius: 270))
                    .id(glowKey)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.9), value: glowKey)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center), lineWidth: 3)
                .blur(radius: 2)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), Look.violet.opacity(0.45)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .shadow(color: Look.violet.opacity(0.16), radius: 30)
    }
}

// MARK: - Power-on moment

/// One ring that swells out of a key and fades.
private struct PulseRing: View {
    let trigger: Int
    var color: Color = Look.red

    private struct Wave {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .keyframeAnimator(initialValue: Wave(), trigger: trigger) { ring, w in
                ring.scaleEffect(w.scale).opacity(w.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(1)
                    CubicKeyframe(1.9, duration: 0.55)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0.9)
                    CubicKeyframe(0, duration: 0.55)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The pad's well lights up like an old TV warming up: a bright line opens into a soft glow, then fades.
/// Reduce Motion: just a gentle glow that fades in and out.
private struct PowerFlash: View {
    let trigger: Int
    let size: CGFloat
    var tint: Color = Look.violet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Warmup {
        var width: CGFloat = 0.04
        var height: CGFloat = 0.02
        var opacity: Double = 0
    }

    var body: some View {
        let still = reduceMotion
        Ellipse()
            .fill(RadialGradient(colors: [.white.opacity(0.9), tint.opacity(0.5), .clear],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Warmup(), trigger: trigger) { glow, w in
                glow
                    .scaleEffect(x: still ? 1 : w.width, y: still ? 1 : w.height)
                    .opacity(still ? w.opacity * 0.45 : w.opacity * 0.8)
            } keyframes: { _ in
                KeyframeTrack(\.width) {
                    MoveKeyframe(0.04)
                    CubicKeyframe(1.0, duration: 0.16)
                }
                KeyframeTrack(\.height) {
                    MoveKeyframe(0.02)
                    LinearKeyframe(0.02, duration: 0.12)
                    CubicKeyframe(1.0, duration: 0.22)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(0.8, duration: 0.3)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Touch pad

private struct TrailDot { let p: CGPoint; let t: Date }
private struct Ripple { let p: CGPoint; let t: Date }

private struct TouchPad: View {
    let size: CGFloat
    var tint: Color = Look.violet
    var powerTick = 0
    let onKey: (RemoteKey) -> Void
    @State private var trail: [TrailDot] = []
    @State private var ripples: [Ripple] = []
    @State private var anchor: CGPoint?
    @State private var presses = 0
    @State private var flash: RemoteKey?
    @State private var flashTick = 0
    @State private var touching = false
    /// Swipe steps and taps on the pad, for their haptics (the pad's keys click on touch-down instead).
    @State private var steps = 0
    @State private var taps = 0
    /// The OK disc rocks a few points toward each move, like a real d-pad.
    @State private var rock: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The OK disc and the edge arrows scale with the pad so they never crowd each other.
    private var okSize: CGFloat { min(94, max(64, size * 0.36)) }
    private var edge: CGFloat { size / 2 - 28 }

    var body: some View {
        ZStack {
            surface
                .gesture(padGesture)
                .accessibilityElement()
                .accessibilityLabel("Touch pad. Swipe to move, tap to select.")
                .accessibilityAddTraits(.allowsDirectInteraction)

            edgeButton(.up, "chevron.up", x: 0, y: -edge)
            edgeButton(.down, "chevron.down", x: 0, y: edge)
            edgeButton(.left, "chevron.left", x: -edge, y: 0)
            edgeButton(.right, "chevron.right", x: edge, y: 0)

            Button { fireOK(at: CGPoint(x: size / 2, y: size / 2)) } label: {
                Text("OK")
                    .font(Look.display(okSize * 0.26)).tracking(1)
                    .foregroundStyle(.white)
                    .frame(width: okSize, height: okSize)
                    .background(
                        Circle().fill(RadialGradient(colors: [Look.violet, Look.magenta.opacity(0.9)],
                                                     center: .topLeading, startRadius: 4, endRadius: okSize * 1.15))
                    )
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)).padding(3))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .background(Circle().fill(Color.black.opacity(0.5)).padding(-8).blur(radius: 6))
                    .shadow(color: Look.magenta.opacity(0.55), radius: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(RemoteKeyStyle(scale: 0.9, feel: .impact(flexibility: .solid, intensity: 0.9)))
            .offset(rock)
            .accessibilityLabel("OK")
        }
        .frame(width: size, height: size)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.55), trigger: steps)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.9), trigger: taps)
    }

    private var surface: some View {
        ZStack {
            // A dark recessed well with an inner shadow.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.10, green: 0.07, blue: 0.20), Look.bgDeep],
                                     center: .center, startRadius: 10, endRadius: size / 2)
                    .shadow(.inner(color: .black.opacity(0.85), radius: 14, x: 0, y: 8))
                    .shadow(.inner(color: Look.violet.opacity(0.35), radius: 6, x: 0, y: -3)))
            Circle()
                .strokeBorder(Look.accent, lineWidth: touching ? 3 : 2)
                .shadow(color: tint.opacity(touching ? 0.9 : 0.45), radius: touching ? 18 : 10)
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .padding(-7)

            // After Power, the well lights up like a TV screen coming on.
            PowerFlash(trigger: powerTick, size: size, tint: tint)
                .clipShape(Circle())

            TimelineView(.animation(minimumInterval: 1 / 60, paused: trail.isEmpty && ripples.isEmpty)) { tl in
                let now = tl.date
                Canvas { ctx, _ in
                    // A soft light that follows your finger.
                    for d in trail {
                        let age = now.timeIntervalSince(d.t)
                        guard age < 0.45 else { continue }
                        let k = 1 - age / 0.45
                        let r = CGFloat(4 + 13 * k)
                        ctx.fill(Path(ellipseIn: CGRect(x: d.p.x - r, y: d.p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Look.cyan.opacity(0.32 * k)))
                    }
                    // A ring that spreads from where you tapped OK.
                    for rp in ripples {
                        let age = now.timeIntervalSince(rp.t)
                        guard age < 0.6 else { continue }
                        let k = age / 0.6
                        let r = CGFloat(10 + 90 * k)
                        ctx.stroke(Path(ellipseIn: CGRect(x: rp.p.x - r, y: rp.p.y - r, width: r * 2, height: r * 2)),
                                   with: .color(Color.white.opacity(0.6 * (1 - k))), lineWidth: 2.5)
                    }
                }
            }
            .allowsHitTesting(false)

            // The rim lights up on the side you moved toward.
            if let f = flash {
                RimGlow(key: f, size: size)
                    .id(flashTick)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.22), value: flashTick)
        .animation(.easeOut(duration: 0.2), value: touching)
    }

    private func edgeButton(_ key: RemoteKey, _ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        let lit = flash == key
        return Button { fire(key, swiped: false) } label: {
            Image(systemName: symbol)
                .font(Look.font(18, .heavy))
                .foregroundStyle(lit ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.85)))
                .shadow(color: Look.cyan.opacity(lit ? 0.9 : 0), radius: lit ? 10 : 0)
                .scaleEffect(lit && !reduceMotion ? 1.25 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: lit)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.85, feel: .impact(flexibility: .rigid, intensity: 0.6)))
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
                    let key: RemoteKey = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    fire(key, swiped: true)
                    anchor = v.location
                    presses += 1
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                if presses == 0 && moved < 14 {
                    taps += 1
                    fireOK(at: v.location)
                }
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

    /// A move: send it, light the rim on that side, rock the OK disc that way; a swipe also clicks like a detent.
    private func fire(_ key: RemoteKey, swiped: Bool) {
        onKey(key)
        if swiped { steps += 1 }
        flash = key
        flashTick += 1
        let tick = flashTick
        if !reduceMotion {
            let d: CGFloat = 3
            let push: CGSize
            switch key {
            case .up: push = CGSize(width: 0, height: -d)
            case .down: push = CGSize(width: 0, height: d)
            case .left: push = CGSize(width: -d, height: 0)
            default: push = CGSize(width: d, height: 0)
            }
            withAnimation(.spring(response: 0.12, dampingFraction: 0.9)) { rock = push }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if flashTick == tick { withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { rock = .zero } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if flashTick == tick { withAnimation(.easeOut(duration: 0.25)) { flash = nil } }
        }
    }

    private func fireOK(at p: CGPoint) {
        ripples.append(Ripple(p: p, t: Date()))
        onKey(.ok)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let cut = Date().addingTimeInterval(-0.65)
            ripples.removeAll { $0.t < cut }
        }
    }

    private func label(for k: RemoteKey) -> String {
        switch k {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        default: return "Right"
        }
    }
}

/// A short bright arc on the pad's rim, on the side of the move.
private struct RimGlow: View {
    let key: RemoteKey
    let size: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.16)
            .stroke(Look.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: size - 6, height: size - 6)
            // Trim starts at 3 o'clock and runs clockwise: turn it so the arc is centered on the move's side.
            .rotationEffect(.degrees(angle - 0.08 * 360))
            .shadow(color: Look.cyan.opacity(0.9), radius: 8)
            .shadow(color: Look.violet.opacity(0.6), radius: 16)
            .accessibilityHidden(true)
    }

    private var angle: Double {
        switch key {
        case .right: return 0
        case .down: return 90
        case .left: return 180
        default: return 270
        }
    }
}

// MARK: - Buttons

/// Round glass key: a symbol, or a short printed label like a real remote's ("INPUT", "CC").
private struct KeyButton: View {
    var symbol: String? = nil
    var text: String? = nil
    let label: String
    var size: CGFloat = 48
    var plain = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let text {
                    Text(text).font(Look.font(text.count > 2 ? size * 0.2 : size * 0.26, .black)).tracking(0.8)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Image(systemName: symbol ?? "circle").font(.system(size: size * 0.34, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .modifier(KeyFace(plain: plain))
            .contentShape(Circle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.88))
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
    var width: CGFloat = 70
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased()).font(Look.font(11, .black)).tracking(1.4).foregroundStyle(.white.opacity(0.85))
                .frame(width: width, height: 36)
                .glassCapsule()
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RemoteKeyStyle(scale: 0.9))
        .accessibilityLabel(title)
    }
}

/// Fires once on touch-down, then repeats every 0.18 s while held; each step clicks.
private struct HoldButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var holding = false
    @State private var loop: Task<Void, Never>?
    @State private var clicks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func step() {
        clicks += 1
        action()
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(holding ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.05)), in: Circle())
            .shadow(color: holding ? Look.magenta.opacity(0.6) : .clear, radius: 10)
            .frame(width: 58, height: 54)
            .contentShape(Rectangle())
            .scaleEffect(holding ? (reduceMotion ? 0.97 : 0.9) : 1)
            .offset(y: holding && !reduceMotion ? 1.5 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.25, dampingFraction: 0.6), value: holding)
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.65), trigger: clicks)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        step()
                        loop?.cancel()
                        loop = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            while !Task.isCancelled && holding {
                                step()
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
            .accessibilityAction { step() }
    }
}

#Preview {
    RemoteView()
        .environment(TVStore())
        .preferredColorScheme(.dark)
}
