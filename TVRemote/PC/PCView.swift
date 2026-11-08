import SwiftUI
import UIKit

/// Control your PC from the couch or bed: trackpad, keyboard, media, volume and apps.
struct PCView: View {
    @Environment(PCClient.self) private var pc

    var body: some View {
        Group {
            if pc.state == .connected { ConnectedPC() } else { PCPairing() }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: pc.state)
        .onAppear { if pc.state == .disconnected, pc.pc != nil, pc.hasToken { pc.connect() } }
    }
}

// MARK: - Pairing

private struct PCPairing: View {
    @Environment(PCClient.self) private var pc
    @State private var manualIP = ""
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Look.S.xl) {
                RadarView(scanning: pc.state != .needsCode,
                          icon: pc.state == .needsCode ? "lock.open.fill" : "desktopcomputer",
                          blips: pc.state == .needsCode ? 0 : pc.found.count,
                          diameter: 230)

                if pc.state == .needsCode { codeEntry } else { finder }

                if let e = pc.lastError {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(Look.font(14, .semibold)).foregroundStyle(.white)
                        .padding(Look.S.m).frame(maxWidth: .infinity)
                        .glass(18, tint: .orange, glow: .orange, strength: 1.5)
                }
            }
            .padding(.horizontal, Look.S.xl)
            .padding(.top, Look.S.xl)
            .padding(.bottom, Look.S.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { pc.startSearch() }
        .onDisappear { pc.stopSearch() }
    }

    private var finder: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("PC remote", color: Look.cyan)
                Text("Run your PC\nfrom bed.").font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Open Clankerr PC on your computer, on the same Wi-Fi as your phone.")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pc.state == .connecting {
                HStack(spacing: Look.S.s) {
                    ProgressView().tint(.white)
                    Text("Connecting to \(pc.pc?.name ?? "your PC")…").font(Look.font(14, .bold)).foregroundStyle(Look.dim)
                }
            }
            VStack(spacing: Look.S.s) {
                ForEach(pc.found, id: \.host) { p in
                    Button { pc.choose(p) } label: {
                        DeviceRow(icon: "desktopcomputer", title: p.name, subtitle: p.host)
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Connect to \(p.name)")
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: pc.found.count)
            if let saved = pc.pc, pc.state == .disconnected, !pc.found.contains(where: { $0.host == saved.host }) {
                Button("Reconnect to \(saved.name)") { pc.connect() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if pc.searching && pc.found.isEmpty {
                Text("Looking for PCs…").font(Look.font(13, .bold)).foregroundStyle(Look.dim)
            }
            HStack(spacing: Look.S.s) {
                TextField("", text: $manualIP, prompt: Text("PC's IP, like 192.168.1.20").foregroundStyle(Look.faint))
                    .keyboardType(.decimalPad).font(Look.font(15, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, Look.S.m).frame(height: 48)
                    .glass(14)
                Button("Connect") { pc.choose(host: manualIP) }
                    .font(Look.font(15, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, Look.S.l).frame(height: 48)
                    .background(Look.accentH, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(manualIP.isEmpty ? 0.4 : 1)
                    .disabled(manualIP.isEmpty)
            }
            VStack(spacing: Look.S.xs) {
                Text("Don't have the PC app yet?").font(Look.font(13, .semibold)).foregroundStyle(Look.dim)
                Link(destination: URL(string: "https://github.com/troydunn1234-ux/treehub-/releases/tag/pc-latest")!) {
                    Label("Get Clankerr PC for Windows", systemImage: "arrow.down.circle.fill")
                        .font(Look.font(14, .heavy)).foregroundStyle(Look.cyan)
                        .padding(.horizontal, Look.S.l).frame(minHeight: 44)
                        .glassCapsule(tint: Look.cyan)
                }
                .accessibilityLabel("Get the PC app: github.com/troydunn1234-ux/treehub-/releases/tag/pc-latest")
            }
            .padding(.top, Look.S.xs)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Almost there", color: Look.cyan)
                Text("Type the code\non your PC.").font(Look.display(34)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("A 6-digit code just popped up on \(pc.pc?.name ?? "your PC").")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            }
            ZStack {
                CodeBoxes(code: code, count: 6, boxWidth: 46, boxHeight: 62, focused: codeFocused)
                TextField("", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($codeFocused).opacity(0.02).frame(width: 320, height: 62)
                    .onChange(of: code) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(6))
                        if digits != v { code = digits }
                        if digits.count == 6 { pc.submitCode(digits); code = "" }
                    }
                    .accessibilityLabel("PC code")
            }
            .onTapGesture { codeFocused = true }
            Button("Cancel") { pc.disconnect() }
                .font(Look.font(14, .bold)).foregroundStyle(Look.dim).frame(minHeight: 44)
        }
        .onAppear { codeFocused = true }
    }
}

// MARK: - Connected

private struct ConnectedPC: View {
    @Environment(PCClient.self) private var pc
    @State private var typing = false
    @State private var typed = " "
    @State private var showApps = false
    @State private var confirm: String?
    @FocusState private var keyboardUp: Bool

    var body: some View {
        VStack(spacing: Look.S.m) {
            header
            Trackpad(
                onMove: { dx, dy in pc.move(dx: dx, dy: dy) },
                onClick: { b, d in UIImpactFeedbackGenerator(style: .light).impactOccurred(); pc.click(b, double: d) },
                onScroll: { dx, dy in pc.scroll(dx: dx, dy: dy) },
                onDrag: { down in UIImpactFeedbackGenerator(style: .medium).impactOccurred(); down ? pc.buttonDown() : pc.buttonUp() })
                .overlay(alignment: .bottom) {
                    CapsLabel("Drag · Tap · Two fingers to scroll", color: .white.opacity(0.22), size: 9)
                        .padding(.bottom, Look.S.m)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(maxHeight: .infinity)
            keysRow
            mediaDeck
            appsRow
        }
        .padding(.horizontal, 20)
        .padding(.bottom, Look.S.s)
        .overlay {
            // Hidden field that drives the iOS keyboard; every change is sent as typing.
            TextField("", text: $typed)
                .focused($keyboardUp)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .opacity(0.01).frame(width: 1, height: 1)
                .onChange(of: typed) { old, new in
                    if new.count < old.count { pc.key("backspace") }
                    else if new.count > old.count { pc.type(String(new.dropFirst(old.count))) }
                    if new.isEmpty || new.count > 40 { typed = " " }
                }
                .onSubmit { pc.key("enter"); keyboardUp = true }
        }
        .sheet(isPresented: $showApps) { AllPCApps().environment(pc) }
        .confirmationDialog(confirm == "sleep" ? "Put your PC to sleep?" : "Lock your PC?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(confirm == "sleep" ? "Sleep" : "Lock", role: .destructive) { if let c = confirm { pc.screen(c) } }
        }
    }

    private var header: some View {
        HStack(spacing: Look.S.m) {
            Image(systemName: "desktopcomputer").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Look.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: Look.violet.opacity(0.6), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    LiveDot(color: Look.live, size: 6).frame(width: 12, height: 12)
                    CapsLabel("Live · Controlling", color: Look.live.opacity(0.9), size: 10)
                }
                Text(pc.pc?.name ?? "Your PC").font(Look.display(24)).tracking(-0.5).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
            Menu {
                Button { confirm = "lock" } label: { Label("Lock PC", systemImage: "lock.fill") }
                Button { confirm = "sleep" } label: { Label("Sleep PC", systemImage: "moon.zzz.fill") }
                Button { pc.screen("display_off") } label: { Label("Turn off display", systemImage: "display") }
                Divider()
                Button(role: .destructive) { pc.forget() } label: { Label("Forget this PC", systemImage: "desktopcomputer.trianglebadge.exclamationmark") }
            } label: {
                Image(systemName: "power").font(.system(size: 17, weight: .black)).foregroundStyle(Look.red)
                    .frame(width: 44, height: 44)
                    .glassCircle(tint: Look.red, glow: Look.red)
            }
            .accessibilityLabel("PC power options")
        }
        .padding(.top, Look.S.xs)
    }

    private var keysRow: some View {
        HStack(spacing: Look.S.s) {
            keyButton("keyboard", "Keyboard", caption: "type", highlighted: keyboardUp) { keyboardUp.toggle() }
            keyButton("escape", "Esc", caption: "esc") { pc.key("esc") }
            keyButton("square.grid.2x2", "Windows key", caption: "win") { pc.key("win") }
            keyButton("rectangle.2.swap", "Switch window", caption: "alt-tab") { pc.key("alt_tab") }
            keyButton("return", "Enter", caption: "enter") { pc.key("enter") }
        }
    }

    private func keyButton(_ symbol: String, _ label: String, caption: String, highlighted: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                Text(caption.uppercased()).font(Look.font(8, .black)).tracking(0.8).opacity(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
        }
        .buttonStyle(KeycapStyle(lit: highlighted))
        .accessibilityLabel(label)
    }

    private var mediaDeck: some View {
        @Bindable var pc = pc
        return VStack(spacing: Look.S.m) {
            HStack(spacing: Look.S.s) {
                mediaButton("backward.fill", "Previous track") { pc.media("prev") }
                Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); pc.media("playpause") } label: {
                    Image(systemName: "playpause.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 70, height: 50).background(Look.accentH, in: Capsule())
                        .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)).padding(1.5))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: Look.magenta.opacity(0.5), radius: 12)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("Play or pause")
                mediaButton("forward.fill", "Next track") { pc.media("next") }
                Spacer(minLength: Look.S.xs)
                mediaButton("speaker.slash.fill", "Mute") { pc.media("mute") }
            }
            HStack(spacing: Look.S.m) {
                Image(systemName: "speaker.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Look.dim)
                Slider(value: $pc.volume, in: 0...100, step: 1, onEditingChanged: { editing in
                    if !editing { pc.setVolume(pc.volume) }
                })
                .tint(Look.magenta)
                .accessibilityLabel("PC volume")
                Text("\(Int(pc.volume))").font(Look.font(15, .black)).foregroundStyle(.white).monospacedDigit().frame(width: 32)
                    .contentTransition(.numericText())
            }
        }
        .padding(Look.S.m)
        .glass(24)
    }

    private func mediaButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 48, height: 48).glassCircle()
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
    }

    private var appsRow: some View {
        VStack(alignment: .leading, spacing: Look.S.s) {
            SectionHeader(title: "Apps") {
                Button { showApps = true } label: {
                    Text("All apps").font(Look.font(13, .heavy)).foregroundStyle(Look.cyan)
                        .padding(.horizontal, Look.S.m).frame(minHeight: 32)
                        .background(Look.cyan.opacity(0.12), in: Capsule())
                }
                .buttonStyle(SquishStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Look.S.m) {
                    ForEach(pc.apps.prefix(14)) { app in PCAppTile(app: app, size: 64) { pc.launch(app) } }
                }
                .padding(.vertical, Look.S.xs)
            }
            .scrollClipDisabled()
        }
    }
}

/// A 3D keycap: a darker base with a lit face that sinks when pressed.
struct KeycapStyle: ButtonStyle {
    var lit = false
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let down = configuration.isPressed
        return ZStack {
            shape.fill(lit ? AnyShapeStyle(Color(red: 0.35, green: 0.12, blue: 0.45)) : AnyShapeStyle(Color.black.opacity(0.55)))
                .offset(y: 4)
            configuration.label
                .background {
                    ZStack {
                        shape.fill(lit ? AnyShapeStyle(Look.accent)
                                       : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)))
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                }
                .offset(y: down ? 3 : 0)
        }
        .padding(.bottom, 4)
        .shadow(color: lit ? Look.magenta.opacity(0.5) : .black.opacity(0.35), radius: lit ? 10 : 6, y: 4)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: down)
    }
}

struct PCAppTile: View {
    let app: PCClient.PCApp
    var size: CGFloat = 74
    let action: () -> Void

    private var colors: [Color] {
        var h: UInt32 = 2166136261
        for u in app.name.unicodeScalars { h = (h ^ u.value) &* 16777619 }
        let hue = Double(h % 360) / 360
        return [Color(hue: hue, saturation: 0.7, brightness: 0.95), Color(hue: hue, saturation: 0.85, brightness: 0.3)]
    }
    private var initials: String {
        let w = app.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return w.prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    var body: some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: size)
                    Text(initials)
                        .font(.system(size: size * 0.32, weight: .black, design: .rounded)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: (colors.first ?? .clear).opacity(0.4), radius: 10, y: 5)
                Text(app.name).font(Look.font(11, .bold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).frame(width: size + 14)
            }
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel("Open \(app.name) on the PC")
    }
}

private struct AllPCApps: View {
    @Environment(PCClient.self) private var pc
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                let list = pc.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 14)], spacing: 18) {
                    ForEach(list) { app in PCAppTile(app: app, size: 70) { pc.launch(app); dismiss() } }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .searchable(text: $query, prompt: "Search your PC's apps")
            .navigationTitle("PC apps")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Trackpad

/// Multitouch trackpad: 1-finger move, tap = click, double tap = double click,
/// 2-finger tap = right click, 2-finger drag = scroll, long-press then drag = drag.
private struct Trackpad: UIViewRepresentable {
    let onMove: (Double, Double) -> Void
    let onClick: (String, Bool) -> Void
    let onScroll: (Double, Double) -> Void
    let onDrag: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TrackpadSurface {
        let v = TrackpadSurface()
        let c = context.coordinator
        v.isMultipleTouchEnabled = true
        v.isAccessibilityElement = true
        v.accessibilityLabel = "Trackpad. Drag to move the mouse, tap to click, two-finger tap to right-click, two-finger drag to scroll."
        v.accessibilityTraits = .allowsDirectInteraction

        let pan1 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan1(_:)))
        pan1.minimumNumberOfTouches = 1; pan1.maximumNumberOfTouches = 1
        let pan2 = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan2(_:)))
        pan2.minimumNumberOfTouches = 2; pan2.maximumNumberOfTouches = 2
        let dbl = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: dbl)
        let tap2 = UITapGestureRecognizer(target: c, action: #selector(Coordinator.twoFingerTap(_:)))
        tap2.numberOfTouchesRequired = 2
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        pan1.require(toFail: hold)
        [pan1, pan2, dbl, tap, tap2, hold].forEach { g in g.delegate = c; v.addGestureRecognizer(g) }
        c.surface = v
        return v
    }

    func updateUIView(_ uiView: TrackpadSurface, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: Trackpad
        weak var surface: TrackpadSurface?
        private var dragging = false
        private var lastHold: CGPoint = .zero
        init(_ p: Trackpad) { parent = p }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Long-press keeps tracking its own movement for drag; nothing else runs alongside.
            false
        }

        @objc func pan1(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            let speed = 1.6
            parent.onMove(Double(t.x) * speed, Double(t.y) * speed)
            surface?.glow(at: g.location(in: g.view), active: g.state == .began || g.state == .changed)
        }

        @objc func pan2(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            guard abs(t.x) > 6 || abs(t.y) > 6 else { return }
            g.setTranslation(.zero, in: g.view)
            // Natural scrolling: fingers up = content up.
            parent.onScroll(Double(-t.x) / 18, Double(t.y) / 18)
            surface?.glow(at: g.location(in: g.view), active: g.state == .began || g.state == .changed)
        }

        @objc func tap(_ g: UITapGestureRecognizer) { surface?.ripple(at: g.location(in: g.view)); parent.onClick("left", false) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) { surface?.ripple(at: g.location(in: g.view)); parent.onClick("left", true) }
        @objc func twoFingerTap(_ g: UITapGestureRecognizer) { surface?.ripple(at: g.location(in: g.view)); parent.onClick("right", false) }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                dragging = true; lastHold = p
                parent.onDrag(true)
                surface?.ripple(at: p)
            case .changed:
                parent.onMove(Double(p.x - lastHold.x) * 1.6, Double(p.y - lastHold.y) * 1.6)
                lastHold = p
                surface?.glow(at: p, active: true)
            default:
                if dragging { parent.onDrag(false) }
                dragging = false
                surface?.glow(at: p, active: false)
            }
        }
    }
}

/// The trackpad's look: a glass slab with a dotted grid, lit rim, a glow under your finger and ripples on clicks.
final class TrackpadSurface: UIView {
    private let fill = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let grid = CAShapeLayer()
    private let radius: CGFloat = 32

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        fill.colors = [UIColor(red: 0.16, green: 0.11, blue: 0.30, alpha: 0.75).cgColor,
                       UIColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 0.85).cgColor]
        fill.startPoint = CGPoint(x: 0.2, y: 0); fill.endPoint = CGPoint(x: 0.8, y: 1)
        layer.addSublayer(fill)

        grid.fillColor = UIColor.white.withAlphaComponent(0.09).cgColor
        layer.addSublayer(grid)

        sheen.colors = [UIColor.white.withAlphaComponent(0.10).cgColor, UIColor.clear.cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 0); sheen.endPoint = CGPoint(x: 0.5, y: 0.35)
        layer.addSublayer(sheen)

        glowLayer.type = .radial
        glowLayer.colors = [UIColor(red: 1, green: 0.24, blue: 0.62, alpha: 0.6).cgColor,
                            UIColor(red: 0.55, green: 0.33, blue: 1, alpha: 0.25).cgColor, UIColor.clear.cgColor]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        glowLayer.opacity = 0
        layer.addSublayer(glowLayer)

        // Gradient rim: magenta → violet → cyan, masked to a thin stroke.
        rim.colors = [UIColor.white.withAlphaComponent(0.45).cgColor,
                      UIColor(red: 0.55, green: 0.33, blue: 1, alpha: 0.6).cgColor,
                      UIColor(red: 0.25, green: 0.88, blue: 1, alpha: 0.5).cgColor]
        rim.startPoint = CGPoint(x: 0, y: 0); rim.endPoint = CGPoint(x: 1, y: 1)
        rimMask.fillColor = UIColor.clear.cgColor
        rimMask.strokeColor = UIColor.black.cgColor
        rimMask.lineWidth = 1.5
        rim.mask = rimMask
        layer.addSublayer(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        sheen.frame = bounds
        rim.frame = bounds
        rimMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: radius).cgPath
        // A dotted grid like a precision trackpad.
        let p = UIBezierPath()
        let step: CGFloat = 22
        var y = step
        while y < bounds.height {
            var x = step
            while x < bounds.width {
                p.append(UIBezierPath(ovalIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)))
                x += step
            }
            y += step
        }
        grid.path = p.cgPath
        CATransaction.commit()
    }

    func glow(at p: CGPoint, active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!active || glowLayer.opacity > 0)
        glowLayer.position = p
        CATransaction.commit()
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = glowLayer.presentation()?.opacity ?? glowLayer.opacity
        glowLayer.opacity = active ? 1 : 0
        a.toValue = glowLayer.opacity
        a.duration = active ? 0.12 : 0.35
        glowLayer.add(a, forKey: "fade")
    }

    func ripple(at p: CGPoint) {
        let r = CAShapeLayer()
        r.path = UIBezierPath(ovalIn: CGRect(x: -20, y: -20, width: 40, height: 40)).cgPath
        r.position = p
        r.fillColor = UIColor.clear.cgColor
        r.strokeColor = UIColor(red: 0.25, green: 0.88, blue: 1, alpha: 0.9).cgColor
        r.lineWidth = 2.5
        layer.addSublayer(r)
        let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 0.3; scale.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
        let g = CAAnimationGroup(); g.animations = [scale, fade]; g.duration = 0.45
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        r.opacity = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { r.removeFromSuperlayer() }
        r.add(g, forKey: "ripple")
        CATransaction.commit()
    }
}
