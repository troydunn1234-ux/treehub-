import Foundation
import Network
import Security

/// Samsung Tizen TVs (2016+). Info over HTTP on 8001, remote keys over a WebSocket on
/// 8002 (TLS, self-signed, pinned on first use) with a token the TV hands out after the
/// user picks "Allow". Older sets without token auth fall back to plain ws:// on 8001.
final class SamsungController: NSObject, TVController, URLSessionDelegate, @unchecked Sendable {
    let brand: TVBrand = .samsung

    private static let remoteName = Data("Couch Remote".utf8).base64EncodedString()

    /// Catalog name → Tizen app id.
    static let knownApps: [String: String] = [
        "Netflix": "3201907018807", "YouTube": "111299001912", "Prime Video": "3201910019365",
        "Disney+": "3201901017640", "Hulu": "3201601007625", "HBO Max": "3202301029760",
        "Peacock": "3202006020991", "Paramount+": "3201710015037", "Apple TV+": "3201807016597",
        "Apple TV": "3201807016597", "Plex": "3201512006963", "Tubi": "3201504001965",
        "Pluto TV": "3201808016802", "YouTube TV": "3201707014489", "Spotify": "3201606009684",
        "Sling TV": "3201508004855",
    ]

    // MARK: State (guarded by lock)

    private let lock = NSLock()
    private var sockets: [String: URLSessionWebSocketTask] = [:]
    private var playing: [String: Bool] = [:]
    private var installed: [String: [String: String]] = [:]   // tv.id → name → appId
    private var pairingTasks: [String: URLSessionWebSocketTask] = [:]
    private var keyboardWatchers: [String: [UUID: AsyncStream<Bool>.Continuation]] = [:]   // tv.id → listeners

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private lazy var probeSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.6
        cfg.timeoutIntervalForResource = 1.2
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    // MARK: Keys and storage

    private func tokenKey(_ tv: DiscoveredTV) -> String { "tv.samsung.\(tv.serial ?? tv.host)" }
    func didMove(from old: DiscoveredTV, to new: DiscoveredTV) async {
        let a = tokenKey(old), b = tokenKey(new)
        if a != b, let t = Keychain.get(a) { Keychain.set(t, for: b); Keychain.delete(a) }
    }
    private static let noToken = "-"   // TV accepted us without handing out a token
    private func macKey(_ tv: DiscoveredTV) -> String { "tv.samsung.mac.\(tv.serial ?? tv.host)" }
    private static func pinKey(_ host: String) -> String { "samsungCertPin.\(host)" }

    // MARK: Trust on first use (TLS on 8002)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let host = challenge.protectionSpace.host
        guard Self.isPrivate(host) else { completionHandler(.performDefaultHandling, nil); return }
        let der = SecCertificateCopyData(leaf) as Data
        let key = Self.pinKey(host)
        if let pinned = UserDefaults.standard.data(forKey: key) {
            guard pinned == der else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        } else {
            UserDefaults.standard.set(der, forKey: key)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    // MARK: Discovery

    func discover() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            let task = Task {
                guard let prefix = Self.wifiPrefix() else { continuation.finish(); return }
                await withTaskGroup(of: DiscoveredTV?.self) { group in
                    var next = 1
                    func add() -> Bool {
                        guard next <= 254 else { return false }
                        let host = "\(prefix).\(next)"; next += 1
                        group.addTask { [weak self] in await self?.info(host: host, quick: true) }
                        return true
                    }
                    for _ in 0..<32 { if !add() { break } }
                    while let r = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let tv = r { continuation.yield(tv) }
                        _ = add()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func probe(host: String) async -> DiscoveredTV? { await info(host: host, quick: false) }

    private func info(host: String, quick: Bool) async -> DiscoveredTV? {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return nil }
        let req = URLRequest(url: url, timeoutInterval: quick ? 0.6 : 2)
        guard let result = try? await (quick ? probeSession : session).data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let device = obj["device"] as? [String: Any] else { return nil }
        let typeText = ((device["type"] as? String) ?? "") + ((obj["type"] as? String) ?? "")
        if !typeText.isEmpty, !typeText.lowercased().contains("tv") { return nil }
        var name = (device["name"] as? String) ?? (obj["name"] as? String) ?? "Samsung TV"
        if name.hasPrefix("[TV] ") { name.removeFirst(5) }
        let model = (device["modelName"] as? String) ?? "Samsung TV"
        let mac = (device["wifiMac"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let serial = mac ?? (device["duid"] as? String) ?? (device["id"] as? String)
        let tv = DiscoveredTV(brand: .samsung, host: host, port: 8002, name: name, model: model, serial: serial)
        if let mac { UserDefaults.standard.set(mac, forKey: macKey(tv)) }
        return tv
    }

    // MARK: Pairing

    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws {
        drop(tv)
        // The TV shows "Allow?" now; wait for the user (or a refusal).
        let (task, token) = try await openChannel(tv, token: nil, timeout: 30, pairing: true)
        Keychain.set(token ?? Self.noToken, for: tokenKey(tv))
        keep(task, for: tv)
    }

    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws { throw TVControlError.unsupported }

    func cancelPairing(_ tv: DiscoveredTV) async {
        let t = locked { pairingTasks.removeValue(forKey: tv.id) }
        t?.cancel(with: .goingAway, reason: nil)
    }

    func isPaired(_ tv: DiscoveredTV) -> Bool { Keychain.get(tokenKey(tv)) != nil }

    func forget(_ tv: DiscoveredTV) {
        drop(tv)
        Keychain.delete(tokenKey(tv))
        UserDefaults.standard.removeObject(forKey: Self.pinKey(tv.host))
        _ = locked { installed.removeValue(forKey: tv.id) }
    }

    // MARK: Channel

    /// Opens the remote-control channel and waits for "ms.channel.connect".
    /// Tries wss://8002 first, then ws://8001 for older TVs.
    private func openChannel(_ tv: DiscoveredTV, token: String?, timeout: TimeInterval, pairing: Bool) async throws
        -> (URLSessionWebSocketTask, String?) {
        var lastError: Error = TVControlError.unreachable
        for (scheme, port) in [("wss", 8002), ("ws", 8001)] {
            var s = "\(scheme)://\(tv.host):\(port)/api/v2/channels/samsung.remote.control?name=\(Self.remoteName)"
            if scheme == "wss", let token, token != Self.noToken { s += "&token=\(token)" }
            guard let url = URL(string: s) else { continue }
            let task = session.webSocketTask(with: url)
            task.maximumMessageSize = 1 << 20
            if pairing { locked { pairingTasks[tv.id] = task } }
            task.resume()
            do {
                let tok = try await Self.withTimeout(timeout) { try await Self.awaitConnect(task) }
                if pairing { _ = locked { pairingTasks.removeValue(forKey: tv.id) } }
                return (task, tok)
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                if pairing { _ = locked { pairingTasks.removeValue(forKey: tv.id) } }
                switch error as? TVControlError {
                case .pairingRejected?: throw TVControlError.pairingRejected
                case .pairingTimedOut? where pairing: throw TVControlError.pairingTimedOut
                default: lastError = error
                }
            }
        }
        if pairing, (lastError as? TVControlError) == nil { throw TVControlError.unreachable }
        throw lastError
    }

    private static func awaitConnect(_ task: URLSessionWebSocketTask) async throws -> String? {
        while true {
            let msg: URLSessionWebSocketTask.Message
            do { msg = try await task.receive() } catch { throw TVControlError.unreachable }
            guard let obj = parse(msg), let event = obj["event"] as? String else { continue }
            switch event {
            case "ms.channel.connect":
                let data = obj["data"] as? [String: Any]
                return data?["token"] as? String
            case "ms.channel.unauthorized": throw TVControlError.pairingRejected
            case "ms.channel.timeOut": throw TVControlError.pairingTimedOut
            default: continue
            }
        }
    }

    private func keep(_ task: URLSessionWebSocketTask, for tv: DiscoveredTV) {
        let old = locked { () -> URLSessionWebSocketTask? in
            let o = sockets[tv.id]; sockets[tv.id] = task; return o
        }
        if let old, old !== task { old.cancel(with: .goingAway, reason: nil) }
        drain(task, id: tv.id)
    }

    /// Reads and discards incoming messages so the socket stays healthy; forgets it on failure.
    private func drain(_ task: URLSessionWebSocketTask, id: String) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                // The TV announces its on-screen keyboard opening / closing on this channel.
                if let obj = Self.parse(msg), let event = obj["event"] as? String {
                    if event == "ms.remote.imeStart" { self.notifyKeyboard(id, true) }
                    if event == "ms.remote.imeEnd" || event == "ms.remote.imeDone" { self.notifyKeyboard(id, false) }
                }
                self.drain(task, id: id)
            case .failure:
                self.locked { if self.sockets[id] === task { self.sockets[id] = nil } }
            }
        }
    }

    private func drop(_ tv: DiscoveredTV) {
        let t = locked { sockets.removeValue(forKey: tv.id) }
        t?.cancel(with: .goingAway, reason: nil)
    }

    private func channel(_ tv: DiscoveredTV) async throws -> URLSessionWebSocketTask {
        if let t = locked({ sockets[tv.id] }), t.state == .running { return t }
        guard let token = Keychain.get(tokenKey(tv)) else { throw TVControlError.notPaired }
        do {
            let (task, newToken) = try await openChannel(tv, token: token, timeout: 4, pairing: false)
            if let newToken, newToken != token { Keychain.set(newToken, for: tokenKey(tv)) }
            keep(task, for: tv)
            return task
        } catch TVControlError.pairingRejected {
            throw TVControlError.notPaired
        } catch TVControlError.pairingTimedOut {
            // A paired TV answers right away; waiting on a prompt means the token is gone.
            throw TVControlError.notPaired
        }
    }

    private func send(_ tv: DiscoveredTV, _ payload: [String: Any]) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { throw TVControlError.other("Couldn't build the command.") }
        for attempt in 0..<2 {
            let task = try await channel(tv)
            do { try await task.send(.string(text)); return } catch {
                drop(tv)
                if attempt == 1 { throw TVControlError.unreachable }
            }
        }
    }

    // MARK: Keys

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws {
        if key == .powerOn { try await wake(tv); return }
        let code: String
        switch key {
        case .up: code = "KEY_UP"
        case .down: code = "KEY_DOWN"
        case .left: code = "KEY_LEFT"
        case .right: code = "KEY_RIGHT"
        case .ok: code = "KEY_ENTER"
        case .back: code = "KEY_RETURN"
        case .home: code = "KEY_HOME"
        case .menu: code = "KEY_MENU"
        case .info: code = "KEY_INFO"
        case .exit: code = "KEY_EXIT"
        case .play: code = "KEY_PLAY"; locked { playing[tv.id] = true }
        case .pause: code = "KEY_PAUSE"; locked { playing[tv.id] = false }
        case .playPause:
            let nowPlaying = locked { () -> Bool in
                let p = !(playing[tv.id] ?? true); playing[tv.id] = p; return p
            }
            code = nowPlaying ? "KEY_PLAY" : "KEY_PAUSE"
        case .seekForward: code = "KEY_FF"
        case .seekBack: code = "KEY_REWIND"
        case .volumeUp: code = "KEY_VOLUP"
        case .volumeDown: code = "KEY_VOLDOWN"
        case .muteToggle: code = "KEY_MUTE"
        case .powerToggle, .powerOff: code = "KEY_POWER"
        case .inputNext: code = "KEY_SOURCE"
        case .ccToggle: code = "KEY_CAPTION"
        case .powerOn: return
        }
        try await send(tv, ["method": "ms.remote.control",
                            "params": ["Cmd": "Click", "DataOfCmd": code, "Option": "false",
                                       "TypeOfRemote": "SendRemoteKey"]])
    }

    /// Wake-on-LAN: magic packet to the subnet broadcast and straight to the TV's address.
    private func wake(_ tv: DiscoveredTV) async throws {
        let macString = UserDefaults.standard.string(forKey: macKey(tv)) ?? tv.serial ?? ""
        let bytes = macString.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { throw TVControlError.unsupported }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        var targets = [tv.host]
        let parts = tv.host.split(separator: ".")
        if parts.count == 4 { targets.insert(parts.prefix(3).joined(separator: ".") + ".255", at: 0) }
        for target in targets {
            for _ in 0..<3 { Self.sendUDP(packet, to: target, port: 9) }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private static func sendUDP(_ data: Data, to host: String, port: UInt16) {
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: params)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
            case .failed, .waiting:
                conn.cancel()
            default: break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { conn.cancel() }
    }

    // MARK: Apps

    func launch(_ tv: DiscoveredTV, appName: String) async throws {
        let known = locked { installed[tv.id]?[appName] }
        guard let appID = known ?? Self.knownApps[appName] else { throw TVControlError.appUnavailable }
        if let url = URL(string: "http://\(tv.host):8001/api/v2/applications/\(appID)") {
            var req = URLRequest(url: url, timeoutInterval: 3)
            req.httpMethod = "POST"
            if let result = try? await session.data(for: req),
               let code = (result.1 as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) { return }
        }
        try await send(tv, ["method": "ms.channel.emit",
                            "params": ["event": "ed.apps.launch", "to": "host",
                                       "data": ["appId": appID, "action_type": "DEEP_LINK"]]])
    }

    func availableApps(_ tv: DiscoveredTV) async -> [String] {
        let fallback = Self.knownApps.keys.filter { $0 != "Apple TV" }.sorted()
        guard let token = Keychain.get(tokenKey(tv)) else { return fallback }
        // A separate short-lived channel so the reply isn't swallowed by the main socket's drain loop.
        guard let opened = try? await openChannel(tv, token: token, timeout: 2, pairing: false) else { return fallback }
        let task = opened.0
        defer { task.cancel(with: .goingAway, reason: nil) }
        let req: [String: Any] = ["method": "ms.channel.emit",
                                  "params": ["event": "ed.installedApp.get", "to": "host"]]
        guard let data = try? JSONSerialization.data(withJSONObject: req),
              let text = String(data: data, encoding: .utf8),
              (try? await task.send(.string(text))) != nil else { return fallback }
        // (appId, name) pairs; plain strings so the result is Sendable.
        let list: [[String]]? = try? await Self.withTimeout(2) { () async throws -> [[String]] in
            while true {
                let msg = try await task.receive()
                guard let obj = Self.parse(msg), (obj["event"] as? String) == "ed.installedApp.get" else { continue }
                let inner = obj["data"] as? [String: Any]
                let apps = (inner?["data"] as? [[String: Any]]) ?? []
                return apps.compactMap { app -> [String]? in
                    guard let id = app["appId"] as? String else { return nil }
                    return [id, (app["name"] as? String) ?? id]
                }
            }
        }
        guard let list, !list.isEmpty else { return fallback }
        var map: [String: String] = [:]
        let byID = Dictionary(Self.knownApps.map { ($0.value, $0.key) }, uniquingKeysWith: { a, b in a.count <= b.count ? a : b })
        for pair in list where pair.count == 2 {
            map[byID[pair[0]] ?? pair[1]] = pair[0]
        }
        locked { installed[tv.id] = map }
        return map.keys.sorted()
    }

    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying? { nil }

    func sendText(_ tv: DiscoveredTV, _ text: String) async throws {
        let b64 = Data(text.utf8).base64EncodedString()
        try await send(tv, ["method": "ms.remote.control",
                            "params": ["Cmd": b64, "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"]])
    }

    /// SendInputString replaces what's in the TV's text box, so the phone sends the whole field each time.
    var textMode: TVTextMode { .replace }

    func submitText(_ tv: DiscoveredTV) async throws {
        try await send(tv, ["method": "ms.remote.control", "params": ["TypeOfRemote": "SendInputEnd"]])
    }

    func keyboardEvents(_ tv: DiscoveredTV) -> AsyncStream<Bool> {
        AsyncStream { cont in
            let token = UUID()
            locked { keyboardWatchers[tv.id, default: [:]][token] = cont }
            cont.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.locked { self.keyboardWatchers[tv.id]?[token] = nil }
            }
            // Make sure the channel is open so the TV's IME events reach us.
            Task { [weak self] in _ = try? await self?.channel(tv) }
        }
    }

    private func notifyKeyboard(_ id: String, _ open: Bool) {
        let conts = locked { Array((keyboardWatchers[id] ?? [:]).values) }
        conts.forEach { $0.yield(open) }
    }

    // MARK: Helpers

    private static func parse(_ msg: URLSessionWebSocketTask.Message) -> [String: Any]? {
        let data: Data
        switch msg {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TVControlError.pairingTimedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TVControlError.pairingTimedOut }
            return first
        }
    }

    private static func isPrivate(_ host: String) -> Bool {
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return host.hasSuffix(".local") }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254)
    }

    /// "192.168.1" for a phone at 192.168.1.23 on Wi-Fi.
    private static func wifiPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var result: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" || (result == nil && name.hasPrefix("en")) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                let parts = ip.split(separator: ".")
                if parts.count == 4 && isPrivate(ip) {
                    result = parts.prefix(3).joined(separator: ".")
                    if name == "en0" { break }
                }
            }
        }
        return result
    }
}
