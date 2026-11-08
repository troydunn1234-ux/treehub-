import Foundation
import Darwin

/// Roku TVs and sticks (Roku, TCL/Hisense/onn Roku TVs) via Roku's External Control Protocol:
/// plain HTTP on port 8060, no pairing. Discovery probes the Wi-Fi /24 subnet with unicast
/// requests, so no multicast entitlement is needed.
final class RokuController: TVController, @unchecked Sendable {
    let brand: TVBrand = .roku
    static let port = 8060

    private let session: URLSession
    private let probeSession: URLSession
    private let lock = NSLock()
    private var appCache: [String: (at: Date, apps: [(id: String, name: String)])] = [:]

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 2
        c.timeoutIntervalForResource = 4
        c.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: c)
        let p = URLSessionConfiguration.ephemeral
        p.timeoutIntervalForRequest = 0.6
        p.timeoutIntervalForResource = 1.2
        p.httpMaximumConnectionsPerHost = 1
        probeSession = URLSession(configuration: p)
    }

    // MARK: - Networking

    private func url(_ tv: DiscoveredTV, _ path: String) -> URL? {
        URL(string: "http://\(tv.host):\(tv.port)\(path)")
    }

    @discardableResult
    private func send(_ method: String, _ url: URL?, session s: URLSession? = nil) async throws -> Data {
        guard let url else { throw TVControlError.other("Bad TV address") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if method == "POST" { req.httpBody = Data() }
        do {
            let (data, resp) = try await (s ?? session).data(for: req)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 403 {
                    throw TVControlError.other("Turn on Settings → System → Advanced system settings → Control by mobile apps → Network access on your Roku.")
                }
                guard (200..<300).contains(http.statusCode) else { throw TVControlError.unreachable }
            }
            return data
        } catch let e as TVControlError {
            throw e
        } catch {
            throw TVControlError.unreachable
        }
    }

    // MARK: - Discovery

    func discover() -> AsyncStream<DiscoveredTV> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self, let prefix = Self.wifiPrefix() else { continuation.finish(); return }
                await withTaskGroup(of: DiscoveredTV?.self) { group in
                    var next = 1
                    func add() -> Bool {
                        guard next <= 254, !Task.isCancelled else { return false }
                        let host = "\(prefix).\(next)"
                        next += 1
                        group.addTask { await self.deviceInfo(host: host, quick: true) }
                        return true
                    }
                    for _ in 0..<32 { if !add() { break } }
                    while let found = await group.next() {
                        if let tv = found { continuation.yield(tv) }
                        _ = add()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func probe(host: String) async -> DiscoveredTV? {
        await deviceInfo(host: host.trimmingCharacters(in: .whitespaces), quick: false)
    }

    private func deviceInfo(host: String, quick: Bool) async -> DiscoveredTV? {
        guard let u = URL(string: "http://\(host):\(Self.port)/query/device-info"),
              let data = try? await send("GET", u, session: quick ? probeSession : session) else { return nil }
        let f = FlatXML.parse(data)
        guard f["model-name"] != nil || f["serial-number"] != nil || f["vendor-name"] != nil else { return nil }
        let isTV = (f["is-tv"] ?? "false").lowercased() == "true"
        let name = [f["user-device-name"], f["friendly-device-name"], f["friendly-model-name"]]
            .compactMap { $0 }.first { !$0.isEmpty } ?? (isTV ? "Roku TV" : "Roku")
        let model = f["friendly-model-name"] ?? f["model-name"] ?? "Roku"
        return DiscoveredTV(brand: .roku, host: host, port: Self.port, name: name, model: model,
                            serial: f["serial-number"] ?? f["device-id"])
    }

    /// "192.168.1" for the Wi-Fi (en0) IPv4 address, or nil.
    static func wifiPrefix() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), String(cString: ifa.ifa_name) == "en0" {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let parts = String(cString: buf).split(separator: ".")
                    if parts.count == 4 { return parts.prefix(3).joined(separator: ".") }
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    // MARK: - Pairing (Roku needs none)

    private func pairedKey(_ tv: DiscoveredTV) -> String { "tv.roku.\(tv.serial ?? tv.host)" }

    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws {
        guard await deviceInfo(host: tv.host, quick: false) != nil else { throw TVControlError.unreachable }
        UserDefaults.standard.set(true, forKey: pairedKey(tv))
    }

    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws {}
    func cancelPairing(_ tv: DiscoveredTV) async {}
    func isPaired(_ tv: DiscoveredTV) -> Bool { UserDefaults.standard.bool(forKey: pairedKey(tv)) }

    func forget(_ tv: DiscoveredTV) {
        UserDefaults.standard.removeObject(forKey: pairedKey(tv))
        lock.lock(); appCache[tv.id] = nil; lock.unlock()
    }

    // MARK: - Keys

    private func code(_ key: RemoteKey) -> String? {
        switch key {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .ok: return "Select"
        case .back: return "Back"
        case .home, .exit: return "Home"
        case .menu, .info: return "Info"
        case .play, .pause, .playPause: return "Play"
        case .seekForward: return "Fwd"
        case .seekBack: return "Rev"
        case .volumeUp: return "VolumeUp"
        case .volumeDown: return "VolumeDown"
        case .muteToggle: return "VolumeMute"
        case .powerToggle: return "Power"
        case .powerOn: return "PowerOn"
        case .powerOff: return "PowerOff"
        case .inputNext, .ccToggle: return nil
        }
    }

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws {
        guard let c = code(key) else { return }
        try await send("POST", url(tv, "/keypress/\(c)"))
    }

    func sendText(_ tv: DiscoveredTV, _ text: String) async throws {
        for ch in text {
            let enc = String(ch).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            guard !enc.isEmpty else { continue }
            try await send("POST", url(tv, "/keypress/Lit_\(enc)"))
        }
    }

    // MARK: - Apps

    private func apps(_ tv: DiscoveredTV) async -> [(id: String, name: String)] {
        lock.lock()
        let cached = appCache[tv.id]
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 600 { return cached.apps }
        guard let data = try? await send("GET", url(tv, "/query/apps")) else { return cached?.apps ?? [] }
        let list = AppsXML.parse(data).filter { !$0.id.isEmpty }
        lock.lock(); appCache[tv.id] = (Date(), list); lock.unlock()
        return list
    }

    private static let aliases: [String: [String]] = [
        "hbo max": ["max", "hbo max"],
        "max": ["max", "hbo max"],
        "prime video": ["prime video", "amazon prime video"],
        "disney+": ["disney plus", "disney+"],
        "paramount+": ["paramount plus", "paramount+"],
        "apple tv+": ["apple tv", "apple tv+"],
        "youtube tv": ["youtube tv"],
        "fubotv": ["fubo", "fubotv", "fubo tv"],
        "discovery+": ["discovery+", "discovery plus"],
        "pluto tv": ["pluto tv"],
        "sling tv": ["sling tv", "sling"],
    ]

    private static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "\u{2122}", with: "").replacingOccurrences(of: "\u{00AE}", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    func launch(_ tv: DiscoveredTV, appName: String) async throws {
        let list = await apps(tv)
        let want = Self.norm(appName)
        let names = Self.aliases[want] ?? [want]
        let match = list.first { names.contains(Self.norm($0.name)) }
            ?? list.first { app in names.contains { Self.norm(app.name).hasPrefix($0) } }
        guard let app = match else { throw list.isEmpty ? TVControlError.unreachable : TVControlError.appUnavailable }
        try await send("POST", url(tv, "/launch/\(app.id)"))
    }

    func availableApps(_ tv: DiscoveredTV) async -> [String] {
        await apps(tv).map(\.name)
    }

    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying? {
        guard let data = try? await send("GET", url(tv, "/query/active-app")) else { return nil }
        guard let app = AppsXML.parse(data).first else { return TVNowPlaying(appName: nil, appID: nil) }
        if app.id.isEmpty { return TVNowPlaying(appName: nil, appID: nil) } // home screen
        return TVNowPlaying(appName: app.name, appID: app.id)
    }
}

// MARK: - Tiny XML helpers

/// Collects leaf element text into a flat dictionary (device-info).
private final class FlatXML: NSObject, XMLParserDelegate {
    private var out: [String: String] = [:]
    private var text = ""

    static func parse(_ data: Data) -> [String: String] {
        let d = FlatXML()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) { text = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, out[elementName] == nil { out[elementName] = t }
        text = ""
    }
}

/// Collects <app id="…">Name</app> entries.
private final class AppsXML: NSObject, XMLParserDelegate {
    private var out: [(id: String, name: String)] = []
    private var currentID: String?
    private var text = ""

    static func parse(_ data: Data) -> [(id: String, name: String)] {
        let d = AppsXML()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "app" { currentID = attributeDict["id"] ?? ""; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if currentID != nil { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "app", let id = currentID {
            out.append((id, text.trimmingCharacters(in: .whitespacesAndNewlines)))
            currentID = nil
        }
    }
}
