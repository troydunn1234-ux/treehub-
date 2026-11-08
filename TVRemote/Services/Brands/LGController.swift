import Foundation
import Security

/// LG webOS TVs (2014+), driven over LG's local "SSAP" WebSocket API:
/// ws://<ip>:3000 on older firmware, wss://<ip>:3001 (self-signed certificate) on newer.
/// The first connection shows an "Allow this device?" prompt on the TV; the TV then hands us a
/// client key that we keep in the Keychain so later connections are silent.
/// Arrow / OK / Back / Home keys go through the TV's separate "pointer input" socket.
final class LGController: NSObject, TVController, URLSessionDelegate, @unchecked Sendable {
    let brand: TVBrand = .lg

    private let lock = NSLock()
    private var session: URLSession!
    private var probeSession: URLSession!
    private var conns: [String: LGConnection] = [:]
    private var connecting: [String: Task<LGConnection, Error>] = [:]
    private var launchPoints: [String: [(title: String, id: String)]] = [:]
    private var playing: [String: Bool] = [:]

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        let pcfg = URLSessionConfiguration.ephemeral
        pcfg.timeoutIntervalForRequest = 0.7
        pcfg.timeoutIntervalForResource = 1.2
        pcfg.waitsForConnectivity = false
        probeSession = URLSession(configuration: pcfg, delegate: self, delegateQueue: nil)
    }

    // MARK: - Keys / storage

    private func key(_ tv: DiscoveredTV) -> String { "tv.lg.\(tv.serial ?? tv.host)" }
    private func macKey(_ tv: DiscoveredTV) -> String { "tv.lg.mac.\(tv.serial ?? tv.host)" }
    private static func pinKey(_ host: String) -> String { "lgCertPin.\(host)" }

    // MARK: - TLS: trust on first use, private addresses only

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
        let k = Self.pinKey(host)
        if let pinned = UserDefaults.standard.data(forKey: k) {
            if pinned != der { completionHandler(.cancelAuthenticationChallenge, nil); return }
        } else {
            UserDefaults.standard.set(der, forKey: k)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    static func isPrivate(_ host: String) -> Bool {
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return host.hasSuffix(".local") }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254)
    }

    // MARK: - Discovery

    func discover() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            let task = Task {
                guard let prefix = Self.wifiPrefix() else { continuation.finish(); return }
                let hosts = (1...254).map { "\(prefix)\($0)" }
                await withTaskGroup(of: DiscoveredTV?.self) { group in
                    var it = hosts.makeIterator()
                    for _ in 0..<48 {
                        guard let h = it.next() else { break }
                        group.addTask { await self.probe(host: h) }
                    }
                    while let result = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let tv = result { continuation.yield(tv) }
                        if let h = it.next() { group.addTask { await self.probe(host: h) } }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func probe(host: String) async -> DiscoveredTV? {
        for (scheme, port) in [("http", 3000), ("https", 3001)] {
            guard let url = URL(string: "\(scheme)://\(host):\(port)/") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 0.7)
            req.httpMethod = "GET"
            guard let (data, resp) = try? await probeSession.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  String(decoding: data, as: UTF8.self).lowercased().contains("hello") else { continue }
            var tv = DiscoveredTV(brand: .lg, host: host, port: port, name: "LG TV (\(host))", model: "webOS", serial: nil)
            if let saved = UserDefaults.standard.string(forKey: "tv.lg.name.\(host)") { tv.name = saved }
            if let model = UserDefaults.standard.string(forKey: "tv.lg.model.\(host)") { tv.model = model }
            return tv
        }
        return nil
    }

    static func wifiPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let parts = String(cString: host).split(separator: ".")
            guard parts.count == 4 else { continue }
            return parts.prefix(3).joined(separator: ".") + "."
        }
        return nil
    }

    // MARK: - Pairing

    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws {
        await closeConnection(tv)
        let conn = try await open(tv, allowPrompt: true)
        lock.withLock { conns[key(tv)] = conn }
        await fetchDeviceDetails(tv, conn)
    }

    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws {
        // LG pairs with an Allow prompt on the TV, not a PIN: nothing to do.
    }

    func cancelPairing(_ tv: DiscoveredTV) async {
        if !isPaired(tv) { await closeConnection(tv) }
    }

    func isPaired(_ tv: DiscoveredTV) -> Bool { Keychain.get(key(tv)) != nil }

    func forget(_ tv: DiscoveredTV) {
        Keychain.delete(key(tv))
        UserDefaults.standard.removeObject(forKey: macKey(tv))
        UserDefaults.standard.removeObject(forKey: Self.pinKey(tv.host))
        let c: LGConnection? = lock.withLock {
            launchPoints[key(tv)] = nil
            return conns.removeValue(forKey: key(tv))
        }
        c?.close()
    }

    /// After pairing: remember the TV's name, model and MAC (for Wake-on-LAN).
    private func fetchDeviceDetails(_ tv: DiscoveredTV, _ conn: LGConnection) async {
        if let info = try? await conn.request("ssap://system/getSystemInfo", timeout: 3) {
            if let model = info["modelName"] as? String { UserDefaults.standard.set(model, forKey: "tv.lg.model.\(tv.host)") }
        }
        if let sw = try? await conn.request("ssap://com.webos.service.update/getCurrentSWInformation", timeout: 3),
           let name = sw["product_name"] as? String, !name.isEmpty {
            UserDefaults.standard.set("LG \(name)", forKey: "tv.lg.name.\(tv.host)")
        }
        if let net = try? await conn.request("ssap://com.webos.service.connectionmanager/getinfo", timeout: 3) {
            let wired = (net["wiredInfo"] as? [String: Any])?["macAddress"] as? String
            let wifi = (net["wifiInfo"] as? [String: Any])?["macAddress"] as? String
            if let mac = wired ?? wifi, mac.count >= 12 { UserDefaults.standard.set(mac, forKey: macKey(tv)) }
        }
    }

    // MARK: - Connection management

    private func connection(_ tv: DiscoveredTV) async throws -> LGConnection {
        let k = key(tv)
        enum Next { case ready(LGConnection), wait(Task<LGConnection, Error>) }
        let next: Next = lock.withLock {
            if let c = conns[k], c.isAlive { return .ready(c) }
            if let t = connecting[k] { return .wait(t) }
            let t = Task { try await self.open(tv, allowPrompt: false) }
            connecting[k] = t
            return .wait(t)
        }
        switch next {
        case .ready(let c): return c
        case .wait(let t):
            do {
                let c = try await t.value
                lock.withLock { conns[k] = c; connecting[k] = nil }
                return c
            } catch {
                lock.withLock { connecting[k] = nil }
                throw error
            }
        }
    }

    private func closeConnection(_ tv: DiscoveredTV) async {
        let c: LGConnection? = lock.withLock { conns.removeValue(forKey: key(tv)) }
        c?.close()
    }

    /// Opens a socket (preferring the port we found the TV on) and registers.
    private func open(_ tv: DiscoveredTV, allowPrompt: Bool) async throws -> LGConnection {
        let clientKey = Keychain.get(key(tv))
        if clientKey == nil && !allowPrompt { throw TVControlError.notPaired }
        let endpoints = tv.port == 3001
            ? ["wss://\(tv.host):3001", "ws://\(tv.host):3000"]
            : ["ws://\(tv.host):3000", "wss://\(tv.host):3001"]
        var lastError: Error = TVControlError.unreachable
        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            let conn = LGConnection(task: session.webSocketTask(with: url), session: session)
            conn.start()
            do {
                let newKey = try await conn.register(clientKey: clientKey, manifest: Self.manifest,
                                                     timeout: allowPrompt ? 30 : 5)
                if let newKey, newKey != clientKey { Keychain.set(newKey, for: key(tv)) }
                return conn
            } catch let e as TVControlError {
                conn.close()
                switch e {
                case .pairingRejected, .pairingTimedOut: throw e
                case .notPaired:
                    // Stored key no longer accepted (TV reset): drop it.
                    Keychain.delete(key(tv)); throw e
                default: lastError = e
                }
            } catch {
                conn.close(); lastError = error
            }
        }
        throw lastError
    }

    private func request(_ tv: DiscoveredTV, _ uri: String, _ payload: [String: Any]? = nil) async throws -> [String: Any] {
        let conn = try await connection(tv)
        do {
            return try await conn.request(uri, payload: payload)
        } catch TVControlError.unreachable {
            // Socket may have gone stale (TV slept); reconnect once.
            await closeConnection(tv)
            return try await connection(tv).request(uri, payload: payload)
        }
    }

    // MARK: - Remote keys

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws {
        switch key {
        case .up: try await button(tv, "UP")
        case .down: try await button(tv, "DOWN")
        case .left: try await button(tv, "LEFT")
        case .right: try await button(tv, "RIGHT")
        case .ok: try await button(tv, "ENTER")
        case .back: try await button(tv, "BACK")
        case .home: try await button(tv, "HOME")
        case .menu: try await button(tv, "MENU")
        case .info: try await button(tv, "INFO")
        case .exit: try await button(tv, "EXIT")
        case .play: _ = try await request(tv, "ssap://media.controls/play"); setPlaying(tv, true)
        case .pause: _ = try await request(tv, "ssap://media.controls/pause"); setPlaying(tv, false)
        case .playPause:
            let isPlaying = lock.withLock { playing[self.key(tv)] ?? true }
            _ = try await request(tv, isPlaying ? "ssap://media.controls/pause" : "ssap://media.controls/play")
            setPlaying(tv, !isPlaying)
        case .seekForward: _ = try await request(tv, "ssap://media.controls/fastForward")
        case .seekBack: _ = try await request(tv, "ssap://media.controls/rewind")
        case .volumeUp: _ = try await request(tv, "ssap://audio/volumeUp")
        case .volumeDown: _ = try await request(tv, "ssap://audio/volumeDown")
        case .muteToggle:
            let muted = await currentMute(tv)
            _ = try await request(tv, "ssap://audio/setMute", ["mute": !muted])
        case .powerOff:
            _ = try await request(tv, "ssap://system/turnOff")
        case .powerOn:
            wake(tv)
        case .powerToggle:
            do { _ = try await request(tv, "ssap://system/turnOff") }
            catch TVControlError.unreachable { wake(tv) }
        case .inputNext: try await nextInput(tv)
        case .ccToggle: return
        }
    }

    private func setPlaying(_ tv: DiscoveredTV, _ v: Bool) { lock.withLock { playing[key(tv)] = v } }

    private func currentMute(_ tv: DiscoveredTV) async -> Bool {
        if let s = try? await request(tv, "ssap://audio/getStatus") {
            if let m = s["mute"] as? Bool { return m }
            if let m = s["muteStatus"] as? Bool { return m }
        }
        if let v = try? await request(tv, "ssap://audio/getVolume") {
            if let m = (v["volumeStatus"] as? [String: Any])?["muteStatus"] as? Bool { return m }
            if let m = v["muted"] as? Bool { return m }
        }
        return false
    }

    private func button(_ tv: DiscoveredTV, _ name: String) async throws {
        let conn = try await connection(tv)
        do {
            try await pointer(tv, conn).send(name)
        } catch {
            // Pointer sockets expire when the TV changes apps; get a fresh one and retry once.
            conn.dropPointer()
            try await pointer(tv, conn).send(name)
        }
    }

    private func pointer(_ tv: DiscoveredTV, _ conn: LGConnection) async throws -> LGPointer {
        if let p = conn.pointer { return p }
        let r = try await conn.request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = r["socketPath"] as? String, let url = URL(string: path) else { throw TVControlError.unsupported }
        let p = LGPointer(task: session.webSocketTask(with: url))
        p.start()
        conn.pointer = p
        return p
    }

    private func nextInput(_ tv: DiscoveredTV) async throws {
        let list = try await request(tv, "ssap://tv/getExternalInputList")
        let devices = (list["devices"] as? [[String: Any]] ?? []).compactMap { d -> (id: String, app: String?, connected: Bool)? in
            guard let id = d["id"] as? String else { return nil }
            return (id, d["appId"] as? String, (d["connected"] as? Bool) ?? true)
        }
        guard !devices.isEmpty else { throw TVControlError.unsupported }
        let connected = devices.filter { $0.connected }
        let candidates = connected.isEmpty ? devices : connected
        let fg = (try? await request(tv, "ssap://com.webos.applicationManager/getForegroundAppInfo"))?["appId"] as? String
        let idx = candidates.firstIndex { $0.app == fg || (fg?.lowercased().contains($0.id.lowercased()) ?? false) }
        let next = candidates[((idx ?? -1) + 1) % candidates.count]
        _ = try await request(tv, "ssap://tv/switchInput", ["inputId": next.id])
    }

    // MARK: - Wake on LAN

    private func wake(_ tv: DiscoveredTV) {
        guard let mac = UserDefaults.standard.string(forKey: macKey(tv)) else { return }
        Self.sendMagicPacket(mac: mac, host: tv.host)
    }

    private static func sendMagicPacket(mac: String, host: String) {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += bytes }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var targets = [host]
        if let p = wifiPrefix() { targets.append(p + "255") }
        targets.append("255.255.255.255")
        for t in targets {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(9).bigEndian
            guard inet_pton(AF_INET, t, &addr.sin_addr) == 1 else { continue }
            _ = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Apps

    /// Catalog name → known webOS app ids (first installed one wins).
    private static let knownApps: [String: [String]] = [
        "Netflix": ["netflix"],
        "YouTube": ["youtube.leanback.v4"],
        "YouTube TV": ["youtube.leanback.ytv.v1"],
        "Prime Video": ["amazon", "lovefilm.de"],
        "Disney+": ["com.disney.disneyplus-prod"],
        "Hulu": ["hulu"],
        "HBO Max": ["com.wbd.max", "com.hbo.hbomax"],
        "Max": ["com.wbd.max", "com.hbo.hbomax"],
        "Peacock": ["com.peacocktv.peacocklgtv", "peacock"],
        "Paramount+": ["com.cbs-ott.2", "cbs-all-access"],
        "Apple TV+": ["com.apple.appletv"],
        "Apple TV": ["com.apple.appletv"],
        "Plex": ["cdp-30"],
        "Tubi": ["tubitv"],
        "Pluto TV": ["com.pluto.plutotv", "pluto.tv"],
        "Spotify": ["spotify-beehive"],
        "Twitch": ["twitch"],
        "Crunchyroll": ["crunchyroll"],
        "Vudu": ["vudu"],
        "fuboTV": ["com.fubotv.app"],
        "Sling TV": ["com.movenetworks.app.sling-tv-sling-production"],
        "Live TV": ["com.webos.app.livetv"],
    ]

    private func points(_ tv: DiscoveredTV, refresh: Bool = false) async -> [(title: String, id: String)] {
        if !refresh, let cached = lock.withLock({ launchPoints[key(tv)] }) { return cached }
        guard let r = try? await request(tv, "ssap://com.webos.applicationManager/listLaunchPoints"),
              let list = r["launchPoints"] as? [[String: Any]] else { return [] }
        let pts = list.compactMap { p -> (title: String, id: String)? in
            guard let t = p["title"] as? String, let id = p["id"] as? String else { return nil }
            return (t, id)
        }
        lock.withLock { launchPoints[key(tv)] = pts }
        return pts
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func launch(_ tv: DiscoveredTV, appName: String) async throws {
        let pts = await points(tv)
        let installed = Set(pts.map(\.id))
        var id: String?
        if let ids = Self.knownApps[appName] {
            id = ids.first { installed.contains($0) } ?? (pts.isEmpty ? ids.first : nil)
        }
        if id == nil {
            let want = Self.norm(appName)
            id = pts.first { Self.norm($0.title) == want }?.id
                ?? pts.first { Self.norm($0.title).hasPrefix(want) || want.hasPrefix(Self.norm($0.title)) }?.id
        }
        guard let appID = id else { throw TVControlError.appUnavailable }
        do {
            _ = try await request(tv, "ssap://system.launcher/launch", ["id": appID])
        } catch TVControlError.other(_) {
            throw TVControlError.appUnavailable
        }
        setPlaying(tv, true)
    }

    func availableApps(_ tv: DiscoveredTV) async -> [String] {
        let pts = await points(tv, refresh: true)
        guard !pts.isEmpty else { return Array(Self.knownApps.keys).sorted() }
        let installed = Set(pts.map(\.id))
        var names = Self.knownApps.compactMap { name, ids in ids.contains(where: installed.contains) ? name : nil }
        let covered = Set(Self.knownApps.values.flatMap { $0 })
        names += pts.filter { !covered.contains($0.id) }.map(\.title)
        return Array(Set(names)).sorted()
    }

    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying? {
        guard let r = try? await request(tv, "ssap://com.webos.applicationManager/getForegroundAppInfo"),
              let appID = r["appId"] as? String, !appID.isEmpty else { return nil }
        if let name = Self.knownApps.first(where: { $0.value.contains(appID) })?.key {
            return TVNowPlaying(appName: name, appID: appID)
        }
        let title = await points(tv).first { $0.id == appID }?.title
        return TVNowPlaying(appName: title, appID: appID)
    }

    func sendText(_ tv: DiscoveredTV, _ text: String) async throws {
        _ = try await request(tv, "ssap://com.webos.service.ime/insertText", ["text": text, "replace": 0])
    }

    // MARK: - Pairing manifest (the widely used LG remote-app manifest)

    private static let manifest: [String: Any] = [
        "manifestVersion": 1,
        "appVersion": "1.1",
        "signed": [
            "created": "20140509",
            "appId": "com.lge.test",
            "vendorId": "com.lge",
            "localizedAppNames": ["": "LG Remote App", "ko-KR": "리모컨 앱", "zxx-XX": "ЛГ Rэмotэ AПП"],
            "localizedVendorNames": ["": "LG Electronics"],
            "permissions": ["TEST_SECURE", "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "READ_INSTALLED_APPS",
                            "READ_LGE_SDX", "READ_NOTIFICATIONS", "SEARCH", "WRITE_SETTINGS", "WRITE_NOTIFICATION_ALERT",
                            "CONTROL_POWER", "READ_CURRENT_CHANNEL", "READ_RUNNING_APPS", "READ_UPDATE_INFO",
                            "UPDATE_FROM_REMOTE_APP", "READ_LGE_TV_INPUT_EVENTS", "READ_TV_CURRENT_TIME"],
            "serial": "2f930e2d2cfe083771f68e4fe7bb07",
        ] as [String: Any],
        "permissions": ["LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE", "TEST_OPEN", "TEST_PROTECTED", "CONTROL_AUDIO",
                        "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK", "CONTROL_INPUT_MEDIA_RECORDING",
                        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "CONTROL_POWER", "READ_APP_STATUS",
                        "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE", "READ_RUNNING_APPS",
                        "READ_TV_CHANNEL_LIST", "WRITE_NOTIFICATION_TOAST", "READ_POWER_STATE", "READ_COUNTRY_INFO",
                        "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "READ_INSTALLED_APPS",
                        "READ_TV_CURRENT_TIME"],
        "signatures": [[
            "signatureVersion": 1,
            "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw==",
        ] as [String: Any]],
    ]
}

// MARK: - One SSAP socket

/// A JSON reply passed across continuations.
private struct LGReply: @unchecked Sendable { let obj: [String: Any] }

private final class LGConnection: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<LGReply, Error>] = [:]
    private var counter = 0
    private var alive = true
    private var _pointer: LGPointer?

    init(task: URLSessionWebSocketTask, session: URLSession) { self.task = task }

    var isAlive: Bool { lock.withLock { alive } }

    var pointer: LGPointer? {
        get { lock.withLock { _pointer } }
        set { lock.withLock { _pointer = newValue } }
    }

    func dropPointer() {
        let p: LGPointer? = lock.withLock { let p = _pointer; _pointer = nil; return p }
        p?.close()
    }

    func start() {
        task.resume()
        receive()
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.failAll(TVControlError.unreachable)
            case .success(let msg):
                var data: Data?
                switch msg {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: data = nil
                }
                if let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    self.handle(obj)
                }
                self.receive()
            }
        }
    }

    private func handle(_ obj: [String: Any]) {
        guard let id = obj["id"] as? String else { return }
        let type = obj["type"] as? String ?? ""
        let payload = obj["payload"] as? [String: Any] ?? [:]
        // The first answer to "register" only says the Allow prompt is showing; keep waiting.
        if type == "response", payload["pairingType"] != nil { return }
        guard let cont = take(id) else { return }
        switch type {
        case "error":
            let msg = (obj["error"] as? String ?? "").lowercased()
            if id.hasPrefix("register") {
                cont.resume(throwing: msg.contains("cancel") || msg.contains("reject") || msg.contains("denied")
                            ? TVControlError.pairingRejected : TVControlError.notPaired)
            } else if msg.contains("401") || msg.contains("permission") {
                cont.resume(throwing: TVControlError.notPaired)
            } else {
                cont.resume(throwing: TVControlError.other(obj["error"] as? String ?? "The TV refused that."))
            }
        default:
            if payload["returnValue"] as? Bool == false {
                let text = payload["errorText"] as? String ?? "The TV refused that."
                cont.resume(throwing: TVControlError.other(text))
            } else {
                cont.resume(returning: LGReply(obj: payload))
            }
        }
    }

    private func take(_ id: String) -> CheckedContinuation<LGReply, Error>? {
        lock.withLock { pending.removeValue(forKey: id) }
    }

    private func failAll(_ error: Error) {
        let all: [CheckedContinuation<LGReply, Error>] = lock.withLock {
            alive = false
            let a = Array(pending.values); pending.removeAll(); return a
        }
        all.forEach { $0.resume(throwing: error) }
    }

    private func nextID(_ prefix: String) -> String {
        lock.withLock { counter += 1; return "\(prefix)_\(counter)" }
    }

    private func send(_ message: [String: Any], id: String, timeout: TimeInterval, timeoutError: TVControlError) async throws -> [String: Any] {
        guard isAlive else { throw TVControlError.unreachable }
        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(decoding: data, as: UTF8.self)
        let reply: LGReply = try await withCheckedThrowingContinuation { cont in
            lock.withLock { pending[id] = cont }
            task.send(.string(text)) { [weak self] err in
                if err != nil, let c = self?.take(id) { c.resume(throwing: TVControlError.unreachable) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                if let c = self?.take(id) { c.resume(throwing: timeoutError) }
            }
        }
        return reply.obj
    }

    /// Returns the client key the TV issued (or confirmed).
    func register(clientKey: String?, manifest: [String: Any], timeout: TimeInterval) async throws -> String? {
        var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT", "manifest": manifest]
        if let clientKey { payload["client-key"] = clientKey }
        let id = nextID("register")
        let r = try await send(["type": "register", "id": id, "payload": payload], id: id, timeout: timeout,
                               timeoutError: clientKey == nil ? .pairingTimedOut : .unreachable)
        return r["client-key"] as? String ?? clientKey
    }

    func request(_ uri: String, payload: [String: Any]? = nil, timeout: TimeInterval = 4) async throws -> [String: Any] {
        let id = nextID("req")
        var msg: [String: Any] = ["type": "request", "id": id, "uri": uri]
        if let payload { msg["payload"] = payload }
        return try await send(msg, id: id, timeout: timeout, timeoutError: .unreachable)
    }

    func close() {
        dropPointer()
        task.cancel(with: .goingAway, reason: nil)
        failAll(TVControlError.unreachable)
    }
}

// MARK: - Pointer input socket (buttons)

private final class LGPointer: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    init(task: URLSessionWebSocketTask) { self.task = task }

    func start() {
        task.resume()
        drain()
    }

    /// Keep reading so the socket's pings are serviced; the TV sends nothing we need.
    private func drain() {
        task.receive { [weak self] result in
            if case .success = result { self?.drain() }
        }
    }

    func send(_ button: String) async throws {
        try await task.send(.string("type:button\nname:\(button)\n\n"))
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }
}
