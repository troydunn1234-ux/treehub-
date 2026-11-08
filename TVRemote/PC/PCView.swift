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
    @State private var spin = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Look.line, lineWidth: 1).frame(width: 180, height: 180)
                    Circle().stroke(Look.line, lineWidth: 1).frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(AngularGradient(colors: [Look.cyan.opacity(0), Look.cyan], center: .center), lineWidth: 90)
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .opacity(pc.state == .needsCode ? 0 : 0.6)
                    Circle().fill(Look.accent).frame(width: 84, height: 84).shadow(color: Look.violet.opacity(0.7), radius: 20)
                    Image(systemName: pc.state == .needsCode ? "lock.open.fill" : "desktopcomputer")
                        .font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                }
                .frame(height: 200)
                .onAppear { withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true } }

                if pc.state == .needsCode { codeEntry } else { finder }

                if let e = pc.lastError {
                    Text(e).font(Look.font(14, .semibold)).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .onAppear { pc.startSearch() }
        .onDisappear { pc.stopSearch() }
    }

    private var finder: some View {
        VStack(spacing: 14) {
            Text("Control your PC").font(Look.font(28, .heavy)).foregroundStyle(.white)
            Text("Run Clankerr PC on your computer, on the same Wi-Fi as your phone.")
                .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            if pc.state == .connecting {
                HStack(spacing: 8) { ProgressView().tint(.white); Text("Connecting to \(pc.pc?.name ?? "your PC")…").font(Look.font(14, .semibold)).foregroundStyle(Look.dim) }
            }
            ForEach(pc.found, id: \.host) { p in
                Button { pc.choose(p) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer").font(.system(size: 20, weight: .bold)).foregroundStyle(Look.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(Look.font(17, .heavy)).foregroundStyle(.white)
                            Text(p.host).font(Look.font(12, .medium)).foregroundStyle(Look.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Look.dim)
                    }
                    .padding(16)
                    .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Look.line))
                }
                .buttonStyle(SquishStyle(scale: 0.97))
                .transition(.scale.combined(with: .opacity))
            }
            if let saved = pc.pc, pc.state == .disconnected, !pc.found.contains(where: { $0.host == saved.host }) {
                Button("Reconnect to \(saved.name)") { pc.connect() }
                    .font(Look.font(15, .bold)).foregroundStyle(Look.cyan)
            }
            if pc.searching && pc.found.isEmpty {
                Text("Looking for PCs…").font(Look.font(13, .semibold)).foregroundStyle(Look.dim)
            }
            HStack {
                TextField("", text: $manualIP, prompt: Text("PC's IP address, like 192.168.1.20").foregroundStyle(Look.dim))
                    .keyboardType(.decimalPad).font(Look.font(15, .medium)).foregroundStyle(.white)
                Button("Connect") { pc.choose(host: manualIP) }
                    .font(Look.font(15, .bold)).foregroundStyle(Look.cyan).disabled(manualIP.isEmpty)
            }
            .padding(14)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(spacing: 4) {
                Text("Don't have the PC app yet?").font(Look.font(13, .semibold)).foregroundStyle(Look.dim)
                Link("Get the PC app: github.com/troydunn1234-ux/treehub-/releases/tag/pc-latest",
                     destination: URL(string: "https://github.com/troydunn1234-ux/treehub-/releases/tag/pc-latest")!)
                    .font(Look.font(13, .bold)).foregroundStyle(Look.cyan).multilineTextAlignment(.center)
            }
            .padding(.top, 6)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 16) {
            Text("Enter the code on your PC").font(Look.font(26, .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text("A 6-digit code just popped up on \(pc.pc?.name ?? "your PC").")
                .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                        Text(ch)
                            .font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 46, height: 60)
                            .background(Look.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(i == code.count ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Look.line), lineWidth: i == code.count ? 2 : 1))
                    }
                }
                TextField("", text: $code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($codeFocused).opacity(0.02).frame(width: 320, height: 60)
                    .onChange(of: code) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(6))
                        if digits != v { code = digits }
                        if digits.count == 6 { pc.submitCode(digits); code = "" }
                    }
            }
            .onTapGesture { codeFocused = true }
            Button("Cancel") { pc.disconnect() }.font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
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
        VStack(spacing: 14) {
            header
            Trackpad(
                onMove: { dx, dy in pc.move(dx: dx, dy: dy) },
                onClick: { b, d in UIImpactFeedbackGenerator(style: .light).impactOccurred(); pc.click(b, double: d) },
                onScroll: { dx, dy in pc.scroll(dx: dx, dy: dy) },
                onDrag: { down in UIImpactFeedbackGenerator(style: .medium).impactOccurred(); down ? pc.buttonDown() : pc.buttonUp() })
                .frame(maxHeight: .infinity)
            keysRow
            mediaDeck
            appsRow
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
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
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("CONTROLLING").font(Look.font(11, .heavy)).tracking(2).foregroundStyle(Look.dim)
                Text(pc.pc?.name ?? "Your PC").font(Look.font(24, .heavy)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
            Menu {
                Button { confirm = "lock" } label: { Label("Lock PC", systemImage: "lock.fill") }
                Button { confirm = "sleep" } label: { Label("Sleep PC", systemImage: "moon.zzz.fill") }
                Button { pc.screen("display_off") } label: { Label("Turn off display", systemImage: "display") }
                Divider()
                Button(role: .destructive) { pc.forget() } label: { Label("Forget this PC", systemImage: "desktopcomputer.trianglebadge.exclamationmark") }
            } label: {
                Image(systemName: "power").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Look.card, in: Circle())
            }
            .accessibilityLabel("PC power options")
        }
    }

    private var keysRow: some View {
        HStack(spacing: 8) {
            keyButton("keyboard", "Keyboard", highlighted: keyboardUp) { keyboardUp.toggle() }
            keyButton("escape", "Esc") { pc.key("esc") }
            keyButton("square.grid.2x2", "Windows key") { pc.key("win") }
            keyButton("rectangle.2.swap", "Switch window") { pc.key("alt_tab") }
            keyButton("return", "Enter") { pc.key("enter") }
        }
    }

    private func keyButton(_ symbol: String, _ label: String, highlighted: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(highlighted ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Look.card), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Look.line))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
    }

    private var mediaDeck: some View {
        @Bindable var pc = pc
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                mediaButton("backward.fill", "Previous track") { pc.media("prev") }
                Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); pc.media("playpause") } label: {
                    Image(systemName: "playpause.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 58, height: 50).background(Look.accent, in: Capsule())
                        .shadow(color: Look.magenta.opacity(0.5), radius: 10)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("Play or pause")
                mediaButton("forward.fill", "Next track") { pc.media("next") }
                Spacer(minLength: 4)
                mediaButton("speaker.slash.fill", "Mute") { pc.media("mute") }
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(Look.dim)
                Slider(value: $pc.volume, in: 0...100, step: 1, onEditingChanged: { editing in
                    if !editing { pc.setVolume(pc.volume) }
                })
                .tint(Look.magenta)
                .accessibilityLabel("PC volume")
                Text("\(Int(pc.volume))").font(Look.font(14, .heavy)).foregroundStyle(.white).monospacedDigit().frame(width: 30)
            }
        }
        .padding(12)
        .background(Look.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Look.line))
    }

    private func mediaButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 44).background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(label)
    }

    private var appsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APPS").font(Look.font(11, .heavy)).tracking(2).foregroundStyle(Look.dim)
                Spacer()
                Button("All apps") { showApps = true }.font(Look.font(13, .bold)).foregroundStyle(Look.cyan)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pc.apps.prefix(14)) { app in PCAppTile(app: app, size: 74) { pc.launch(app) } }
                }
            }
        }
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
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
                    .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: 8, y: 4)
                Text(app.name).font(Look.font(11, .bold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).frame(width: size + 8)
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
            .background(Look.bg)
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

/// The trackpad's look: rounded glass with a faint grid, a glow under your finger, ripples on clicks.
final class TrackpadSurface: UIView {
    private let glowLayer = CAGradientLayer()
    private let border = CAShapeLayer()
    private let grid = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.05)
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous
        clipsToBounds = true
        grid.strokeColor = UIColor.white.withAlphaComponent(0.05).cgColor
        grid.lineWidth = 1
        layer.addSublayer(grid)
        glowLayer.type = .radial
        glowLayer.colors = [UIColor(red: 1, green: 0.24, blue: 0.62, alpha: 0.55).cgColor, UIColor.clear.cgColor]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        glowLayer.opacity = 0
        layer.addSublayer(glowLayer)
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor(red: 0.55, green: 0.33, blue: 1, alpha: 0.55).cgColor
        border.lineWidth = 1.5
        layer.addSublayer(border)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 28).cgPath
        let p = UIBezierPath()
        let step: CGFloat = 28
        var x = step
        while x < bounds.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: bounds.height)); x += step }
        var y = step
        while y < bounds.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: bounds.width, y: y)); y += step }
        grid.path = p.cgPath
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
