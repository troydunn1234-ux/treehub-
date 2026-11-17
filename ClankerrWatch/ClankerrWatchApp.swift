import SwiftUI
import Observation
import WatchConnectivity
import WatchKit
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
struct ClankerrWatchApp: App {
    @State private var link = RemoteLink.shared
    var body: some Scene {
        WindowGroup {
            ClankerrWatchRoot()
                .environment(link)
                .onAppear { link.activate() }
                // couchremote://remote from the complication: the app is already the remote, just refresh.
                .onOpenURL { url in
                    guard url.scheme == "couchremote" else { return }
                    link.activate()
                    link.refresh()
                }
        }
    }
}

/// The watch face complication reads the TV name from the App Group (shared with the watch app only;
/// App Group defaults don't sync from the iPhone, so the watch writes it itself whenever the phone updates it).
enum WatchWidgetBridge {
    static let appGroup = "group.com.troydunn.clicker"
    static func write(tvName: String) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        if d.string(forKey: "tvName") == tvName { return }
        d.set(tvName, forKey: "tvName")
        d.set(Date().timeIntervalSince1970, forKey: "updatedAt")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
    /// When the phone's sleep timer turns the TV off (nil = no timer).
    var sleepEnd: Date?

    init() {}
    init(_ d: [String: Any]) {
        paired = d["paired"] as? Bool ?? false
        tv = d["tv"] as? String ?? ""
        now = d["now"] as? String ?? ""
        reachable = d["reachable"] as? Bool ?? true
        let se = d["sleepEnd"] as? Double ?? 0
        sleepEnd = se > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: se) : nil
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

    /// Start the phone's sleep timer (minutes), or 0 to turn it off.
    func sleep(minutes: Int) {
        WKInterfaceDevice.current().play(minutes > 0 ? .start : .stop)
        if Self.demo { state.sleepEnd = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil; return }
        send(["sleep": minutes], wantReply: true)
    }

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
        WatchWidgetBridge.write(tvName: state.tv)
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
            if link.state.paired || RemoteLink.demo {
                TabView {
                    PadPage().containerBackground(CW.bg.gradient, for: .tabView)
                    PowerPage().containerBackground(CW.bg.gradient, for: .tabView)
                    AppsPage().containerBackground(CW.bg.gradient, for: .tabView)
                    SleepPage().containerBackground(CW.bg.gradient, for: .tabView)
                }
                .tabViewStyle(.verticalPage)
            } else {
                // Nothing to control yet: say what to do instead of showing a remote that can't reach a TV.
                WatchSetupView().containerBackground(CW.bg.gradient, for: .navigation)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: link.state.paired)
        .alert("Couch Remote", isPresented: Binding(get: { link.error != nil }, set: { if !$0 { link.error = nil } })) {
            Button("OK", role: .cancel) { link.error = nil }
        } message: { Text(link.error ?? "") }
    }
}

/// Shown until the iPhone says a TV is paired: what to do next, and a way to check again.
struct WatchSetupView: View {
    @Environment(RemoteLink.self) private var link
    @State private var tries = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: link.phoneReachable ? "tv.badge.wifi" : "iphone.slash")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(CW.accent)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .symbolEffect(.bounce, value: tries)
                    .accessibilityHidden(true)
                Text(link.phoneReachable ? "Pair your TV on iPhone" : "Can't reach your iPhone")
                    .font(CW.font(16, .heavy))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(link.phoneReachable
                     ? "Open Couch Remote on your iPhone and pick your TV. The remote shows up here."
                     : "Keep your iPhone nearby with Couch Remote on it, then try again.")
                    .font(CW.font(12, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    tries += 1
                    WKInterfaceDevice.current().play(.click)
                    link.activate()
                    link.refresh()
                } label: {
                    Text("Try Again").font(CW.font(15, .heavy)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .tint(CW.violet)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Couch Remote")
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
                Circle().fill(link.phoneReachable && link.state.reachable ? Color.green : Color.orange).frame(width: 6, height: 6)
                    .accessibilityLabel(link.phoneReachable ? (link.state.reachable ? "Connected" : "TV not answering") : "iPhone not reachable")
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

/// Power, volume and input as big buttons (the crown on the pad page does volume too).
struct PowerPage: View {
    @Environment(RemoteLink.self) private var link
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { link.press("power", haptic: .start) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RadialGradient(colors: [Color(red: 1, green: 0.3, blue: 0.38), Color(red: 0.55, green: 0.05, blue: 0.15)],
                                                   center: .topLeading, startRadius: 2, endRadius: 70),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Power")
                VStack(spacing: 6) {
                    big("plus", "volUp", "Volume up", haptic: .directionUp, h: 23)
                    big("minus", "volDown", "Volume down", haptic: .directionDown, h: 23)
                }
            }
            HStack(spacing: 6) {
                big("speaker.slash.fill", "mute", "Mute")
                big("rectangle.on.rectangle", "input", "Input")
                big("line.3.horizontal", "menu", "Menu")
            }
        }
        .navigationTitle("Power")
    }

    private func big(_ symbol: String, _ cmd: String, _ label: String, haptic: WKHapticType = .click, h: CGFloat = 36) -> some View {
        Button { link.press(cmd, haptic: haptic) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: h)
                .background(Color.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(CW.accent, lineWidth: 1).opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The phone's sleep timer: countdown, and quick lengths to start or change it.
struct SleepPage: View {
    @Environment(RemoteLink.self) private var link
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let end = link.state.sleepEnd, end > Date() {
                    VStack(spacing: 2) {
                        Text("TV OFF IN").font(CW.font(11, .heavy)).foregroundStyle(.secondary)
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
                            .foregroundStyle(CW.accent)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    Button { link.sleep(minutes: 0) } label: {
                        Text("Turn Off Timer").font(CW.font(13, .heavy)).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .tint(.red)
                } else {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(CW.accent)
                    Text("Turn the TV off after").font(CW.font(12, .semibold)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach([15, 30, 60, 90], id: \.self) { m in
                        Button { link.sleep(minutes: m) } label: {
                            Text(m < 60 ? "\(m) min" : (m == 60 ? "1 hr" : "1.5 hr"))
                                .font(CW.font(14, .heavy)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(Color.white.opacity(0.1), in: Capsule())
                                .overlay(Capsule().stroke(CW.accent, lineWidth: 1).opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sleep timer \(m) minutes")
                    }
                }
                Text("Your iPhone does the turning off, so keep it on the same Wi-Fi as the TV.")
                    .font(CW.font(10, .medium)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Sleep")
    }
}

/// Your favorite apps as glowing tiles; tap to open on the TV.
struct AppsPage: View {
    @Environment(RemoteLink.self) private var link
    var body: some View {
        ScrollView {
            if link.state.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(CW.accent)
                        .accessibilityHidden(true)
                    Text("No apps yet").font(CW.font(15, .heavy))
                    Text("Add apps to your wall in Couch Remote on your iPhone and they show up here.")
                        .font(CW.font(12, .medium)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
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
