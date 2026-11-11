import Foundation
import Network
import UIKit

/// Talks to the Couch Remote PC companion (ws://<pc>:47815) on your home Wi-Fi.
@MainActor
@Observable
final class PCClient {
    enum State: Equatable { case disconnected, connecting, needsCode, connected }

    /// The one PC client the app, Scenes and Siri share.
    static let shared = PCClient()

    struct PC: Codable, Equatable, Hashable { var host: String; var name: String }
    struct PCApp: Codable, Identifiable, Hashable { var id: String; var name: String }

    static let port = 47815
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") || UserDefaults.standard.bool(forKey: "demoMode") }

    private(set) var state: State = .disconnected
    private(set) var pc: PC?
    private(set) var found: [PC] = []
    private(set) var apps: [PCApp] = []
    var volume: Double = 50
    private(set) var lastError: String?
    private(set) var searching = false

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var retry = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var pendingDX: Double = 0
    @ObservationIgnored private var pendingDY: Double = 0
    @ObservationIgnored private var lastMoveSent = Date.distantPast
    @ObservationIgnored private var moveFlush: Task<Void, Never>?
    @ObservationIgnored private var wantConnected = false

    init() {
        if Self.demo {
            pc = PC(host: "192.168.1.20", name: "Gaming PC")
            state = .connected
            volume = 42
            apps = ["Steam", "Discord", "Spotify", "Chrome", "Fortnite", "Minecraft", "VLC", "OBS Studio"]
                .map { PCApp(id: $0, name: $0) }
            return
        }
        if let d = UserDefaults.standard.data(forKey: "pc"), let p = try? JSONDecoder().decode(PC.self, from: d) { pc = p }
    }

    private var tokenKey: String? { pc.map { "pctoken.\($0.host)" } }
    var hasToken: Bool { tokenKey.flatMap { Keychain.get($0) } != nil }

    // MARK: Discovery

    func startSearch() {
        guard !Self.demo, browser == nil else { return }
        searching = true
        let b = NWBrowser(for: .bonjour(type: "_clankerr._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                var name = "PC"
                if case let .service(n, _, _, _) = r.endpoint { name = n }
                Task { @MainActor in self?.resolve(r.endpoint, name: name) }
            }
        }
        b.start(queue: .main)
        browser = b
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            self.searching = false
        }
    }

    func stopSearch() { browser?.cancel(); browser = nil; searching = false }

    private func resolve(_ endpoint: NWEndpoint, name: String) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] st in
            if case .ready = st {
                if case let .hostPort(host, _)? = conn.currentPath?.remoteEndpoint {
                    var h = "\(host)"
                    if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
                    Task { @MainActor in
                        guard let self else { return }
                        if !self.found.contains(where: { $0.host == h }) { self.found.append(PC(host: h, name: name)) }
                    }
                }
                conn.cancel()
            }
        }
        conn.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { conn.cancel() }
    }

    // MARK: Connection

    func choose(_ p: PC) {
        guard Unlock.shared.gate("PC remote") else { return }
        pc = p
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "pc") }
        connect()
    }

    func choose(host: String) {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return }
        choose(PC(host: h, name: h))
    }

    func connect() {
        guard !Self.demo, let pc else { return }
        wantConnected = true
        reconnectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        guard let url = URL(string: "ws://\(pc.host):\(Self.port)") else { return }
        state = .connecting
        lastError = nil
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        receive(on: t)
        if let key = tokenKey, let token = Keychain.get(key) {
            send(["t": "hello", "token": token])
        } else {
            send(["t": "hello"])   // asks the PC to show a pairing code
        }
    }

    func disconnect() {
        wantConnected = false
        reconnectTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    func forget() {
        if let key = tokenKey { Keychain.delete(key) }
        disconnect()
        pc = nil
        apps = []
        UserDefaults.standard.removeObject(forKey: "pc")
    }

    func submitCode(_ code: String) {
        send(["t": "pair", "code": code, "device": UIDevice.current.name])
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let msg):
                    if case let .string(s) = msg { self.handle(s) }
                    self.receive(on: t)
                case .failure:
                    self.dropped()
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = obj["t"] as? String else { return }
        switch t {
        case "needcode":
            if let key = tokenKey { Keychain.delete(key) }
            state = .needsCode
            if let n = obj["name"] as? String, var p = pc, p.name == p.host { p.name = n; pc = p }
        case "badcode":
            lastError = "That code didn't match. Check the code on your PC."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "paired":
            if let token = obj["token"] as? String, let key = tokenKey { Keychain.set(token, for: key) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "info":
            state = .connected
            retry = 0
            if let n = obj["name"] as? String, var p = pc {
                p.name = n; pc = p
                if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "pc") }
            }
            if let v = obj["volume"] as? Double { volume = v } else if let v = obj["volume"] as? Int { volume = Double(v) }
            send(["t": "apps"])
        case "volume":
            if let v = obj["volume"] as? Double { volume = v } else if let v = obj["volume"] as? Int { volume = Double(v) }
        case "apps":
            if let list = obj["apps"] as? [[String: Any]] {
                apps = list.compactMap { a in
                    guard let id = a["id"] as? String, let n = a["name"] as? String else { return nil }
                    return PCApp(id: id, name: n)
                }
            }
        case "launched":
            if (obj["ok"] as? Bool) == false { lastError = "The PC couldn't open that." }
        default: break
        }
    }

    private func dropped() {
        task = nil
        guard wantConnected, state != .needsCode else {
            if state != .needsCode { state = .disconnected }
            return
        }
        state = .connecting
        retry += 1
        if retry > 6 { state = .disconnected; lastError = "Can't reach your PC. Is the PC app (Clankerr PC) running?"; return }
        let delay = min(10.0, pow(1.8, Double(retry)))
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled { self.connect() }
        }
    }

    // MARK: Commands

    private func send(_ obj: [String: Any]) {
        guard !Self.demo, let task, let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    /// Mouse moves are summed and sent at most every 16 ms.
    func move(dx: Double, dy: Double) {
        pendingDX += dx; pendingDY += dy
        let since = Date().timeIntervalSince(lastMoveSent)
        if since >= 0.016 { flushMove() } else if moveFlush == nil {
            moveFlush = Task {
                try? await Task.sleep(nanoseconds: UInt64((0.016 - since) * 1_000_000_000))
                self.moveFlush = nil
                self.flushMove()
            }
        }
    }

    private func flushMove() {
        guard pendingDX != 0 || pendingDY != 0 else { return }
        send(["t": "move", "dx": pendingDX, "dy": pendingDY])
        pendingDX = 0; pendingDY = 0
        lastMoveSent = Date()
    }

    func click(_ button: String = "left", double: Bool = false) { flushMove(); send(["t": "click", "button": button, "double": double]) }
    func buttonDown(_ button: String = "left") { flushMove(); send(["t": "down", "button": button]) }
    func buttonUp(_ button: String = "left") { flushMove(); send(["t": "up", "button": button]) }
    func scroll(dx: Double, dy: Double) { send(["t": "scroll", "dx": dx, "dy": dy]) }
    func type(_ s: String) { send(["t": "text", "s": s]) }
    func key(_ k: String, mods: [String] = []) { send(["t": "key", "k": k, "mods": mods]) }
    func media(_ a: String) { send(["t": "media", "a": a]) }
    func setVolume(_ v: Double) { volume = v; send(["t": "volume", "set": Int(v.rounded())]) }
    func launch(_ app: PCApp) { send(["t": "launch", "id": app.id]) }
    func screen(_ action: String) { send(["t": "screen", "action": action]) }

    /// A PC is saved (paired) on this phone.
    var isPaired: Bool { pc != nil && (hasToken || Self.demo) }

    /// Scenes: put the PC to sleep (no confirmation; the scene is the confirmation).
    func sleep() {
        guard isPaired else { return }
        if state != .connected { connect() }
        screen("sleep")
    }

    /// Scenes: wake the PC's display. Reconnects first if the socket dropped while the phone was idle.
    func wake() {
        guard isPaired else { return }
        if state != .connected { connect() }
        screen("wake")
    }
}
