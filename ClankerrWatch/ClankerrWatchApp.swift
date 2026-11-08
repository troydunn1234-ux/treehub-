import SwiftUI
import Observation
import WatchConnectivity
import WatchKit

@main
struct ClankerrWatchApp: App {
    @State private var link = RemoteLink.shared
    var body: some Scene {
        WindowGroup {
            ClankerrWatchRoot()
                .environment(link)
                .onAppear { link.activate() }
        }
    }
}

enum CW {
    static let bg = Color(red: 0.035, green: 0.03, blue: 0.075)
    static let magenta = Color(red: 1.0, green: 0.24, blue: 0.62)
    static let violet = Color(red: 0.55, green: 0.33, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
    static let accent = LinearGradient(colors: [magenta, violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func color(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

struct RemoteState: Equatable {
    struct TVApp: Identifiable, Equatable { var id: String { name }; var name: String; var c1: Int; var c2: Int }
    var paired = false
    var tv = ""
    var now = ""
    var reachable = true
    var apps: [TVApp] = []

    init() {}
    init(_ d: [String: Any]) {
        paired = d["paired"] as? Bool ?? false
        tv = d["tv"] as? String ?? ""
        now = d["now"] as? String ?? ""
        reachable = d["reachable"] as? Bool ?? true
        apps = (d["apps"] as? [[String: Any]] ?? []).map {
            TVApp(name: $0["name"] as? String ?? "", c1: $0["c1"] as? Int ?? 0x8A3BFF, c2: $0["c2"] as? Int ?? 0x1E0B4A)
        }
    }
}

@MainActor
@Observable
final class RemoteLink: NSObject {
    static let shared = RemoteLink()
    private(set) var state = RemoteState()
    private(set) var phoneReachable = false
    var error: String?

    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    func activate() {
        if Self.demo {
            var s = RemoteState(); s.paired = true; s.tv = "Living Room TV"; s.now = "HBO Max"
            s.apps = [.init(name: "Netflix", c1: 0xE50914, c2: 0x3B0306), .init(name: "YouTube", c1: 0xFF2D2D, c2: 0x5A0A0A),
                      .init(name: "HBO Max", c1: 0x8A3BFF, c2: 0x1E0B4A), .init(name: "Hulu", c1: 0x1CE783, c2: 0x0B3B26),
                      .init(name: "Disney+", c1: 0x3D7BFF, c2: 0x0B1546), .init(name: "Prime Video", c1: 0x1FA8FF, c2: 0x0A2A55)]
            state = s; phoneReachable = true
            return
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func press(_ key: String, haptic: WKHapticType = .click) {
        WKInterfaceDevice.current().play(haptic)
        send(["key": key], wantReply: false)
    }

    func launch(_ app: RemoteState.TVApp) {
        WKInterfaceDevice.current().play(.start)
        state.now = app.name
        send(["launch": app.name], wantReply: true)
    }

    func refresh() { send([:], wantReply: true, quiet: true) }

    private func send(_ msg: [String: Any], wantReply: Bool, quiet: Bool = false) {
        if Self.demo { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else {
            if !quiet { error = "Can't reach your iPhone. Keep it nearby." ; WKInterfaceDevice.current().play(.failure) }
            return
        }
        if wantReply {
            s.sendMessage(msg, replyHandler: { reply in Task { @MainActor in self.apply(reply) } },
                          errorHandler: { _ in Task { @MainActor in if !quiet { self.error = "Your iPhone didn't answer." } } })
        } else {
            s.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        }
    }

    fileprivate func apply(_ d: [String: Any]) {
        guard d["paired"] != nil else { return }
        state = RemoteState(d)
    }

    fileprivate func setReachable(_ r: Bool) { phoneReachable = r }
}

extension RemoteLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let reach = session.isReachable
        Task { @MainActor in
            self.setReachable(reach)
            if !ctx.isEmpty { self.apply(ctx) }
            if reach { self.refresh() }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reach = session.isReachable
        Task { @MainActor in self.setReachable(reach); if reach { self.refresh() } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}

struct ClankerrWatchRoot: View {
    @Environment(RemoteLink.self) private var link
    var body: some View {
        NavigationStack {
            TabView {
                PadPage().containerBackground(CW.bg.gradient, for: .tabView)
                AppsPage().containerBackground(CW.bg.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
        }
        .alert("Couch Remote", isPresented: Binding(get: { link.error != nil }, set: { if !$0 { link.error = nil } })) {
            Button("OK", role: .cancel) { link.error = nil }
        } message: { Text(link.error ?? "") }
    }
}

/// Swipe to move, tap for OK, turn the Digital Crown for volume.
struct PadPage: View {
    @Environment(RemoteLink.self) private var link
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crown = 0.0
    @State private var crownAnchor = 0.0
    @State private var flash: String?
    @State private var glow: CGPoint?

    var body: some View {
        VStack(spacing: 6) {
            pad
            HStack(spacing: 6) {
                key("arrow.uturn.backward", "back", "Back")
                key("house.fill", "home", "Home")
                key("playpause.fill", "playPause", "Play or pause", haptic: .start)
                key("speaker.slash.fill", "mute", "Mute")
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: -10_000, through: 10_000, by: 1, sensitivity: .medium,
                              isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, v in
            // Every 3 crown steps is one volume click.
            let steps = Int((v - crownAnchor) / 3)
            guard steps != 0 else { return }
            crownAnchor += Double(steps) * 3
            for _ in 0..<min(abs(steps), 4) { link.press(steps > 0 ? "volUp" : "volDown", haptic: .directionUp) }
            show(steps > 0 ? "VOL +" : "VOL −")
        }
        .navigationTitle {
            HStack(spacing: 4) {
                Circle().fill(link.state.reachable ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(link.state.now.isEmpty ? (link.state.tv.isEmpty ? "Couch Remote" : link.state.tv) : link.state.now)
                    .font(CW.font(14, .heavy)).lineLimit(1)
            }
        }
    }

    private var pad: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(CW.accent, lineWidth: 1.5)
                    .opacity(0.8)
                if let g = glow {
                    Circle().fill(CW.accent).frame(width: 46, height: 46).blur(radius: 14).position(g).opacity(0.8)
                }
                Text(flash ?? "OK")
                    .font(CW.font(flash == nil ? 15 : 17, .black))
                    .foregroundStyle(flash == nil ? Color.white.opacity(0.35) : .white)
                    .contentTransition(.opacity)
                ForEach(["chevron.up", "chevron.down", "chevron.left", "chevron.right"], id: \.self) { s in
                    Image(systemName: s).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.3))
                        .position(arrowPos(s, geo.size))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in glow = v.location }
                    .onEnded { v in
                        glow = nil
                        let dx = v.translation.width, dy = v.translation.height
                        if max(abs(dx), abs(dy)) < 12 {
                            link.press("ok", haptic: .click); show("OK")
                        } else if abs(dx) > abs(dy) {
                            link.press(dx > 0 ? "right" : "left", haptic: .directionUp); show(dx > 0 ? "→" : "←")
                        } else {
                            link.press(dy > 0 ? "down" : "up", haptic: dy > 0 ? .directionDown : .directionUp); show(dy > 0 ? "↓" : "↑")
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Touch pad. Swipe to move, tap for OK.")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }

    private func arrowPos(_ s: String, _ size: CGSize) -> CGPoint {
        switch s {
        case "chevron.up": return CGPoint(x: size.width / 2, y: 10)
        case "chevron.down": return CGPoint(x: size.width / 2, y: size.height - 10)
        case "chevron.left": return CGPoint(x: 10, y: size.height / 2)
        default: return CGPoint(x: size.width - 10, y: size.height / 2)
        }
    }

    private func show(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { flash = text }
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if flash == text { withAnimation(.easeOut(duration: 0.2)) { flash = nil } }
        }
    }

    private func key(_ symbol: String, _ cmd: String, _ label: String, haptic: WKHapticType = .click) -> some View {
        Button { link.press(cmd, haptic: haptic) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Your favorite apps as glowing tiles; tap to open on the TV.
struct AppsPage: View {
    @Environment(RemoteLink.self) private var link
    var body: some View {
        ScrollView {
            if link.state.apps.isEmpty {
                Text("Pair your TV in Couch Remote on your iPhone and your apps show up here.")
                    .font(CW.font(13, .medium)).foregroundStyle(.secondary).padding(.top, 8)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(link.state.apps) { app in
                    Button { link.launch(app) } label: {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [CW.color(app.c1), CW.color(app.c2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(String(app.name.prefix(1)))
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.14))
                                .offset(x: 34, y: -6)
                            Text(app.name).font(CW.font(12, .heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7).padding(7)
                        }
                        .frame(height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            if link.state.now == app.name {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CW.accent, lineWidth: 2.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(app.name) on the TV")
                }
            }
        }
        .navigationTitle("Apps")
    }
}
