import Foundation
import Network
import Security
import CryptoKit

/// Google TV / Android TV (Sony, TCL & Hisense Google TV, Chromecast with Google TV, Shield…)
/// using the Android TV Remote protocol v2 — the same one Google's own TV remote uses.
///
/// - Pairing: TLS on port 6467 with our self-signed client certificate; the TV shows a
///   6-character hex code, and both sides prove they saw it via a SHA-256 over both RSA keys.
/// - Remote: TLS on port 6466 with the same certificate; key presses and app links as protobuf.
///
/// Requires "_androidtvremote2._tcp" in NSBonjourServices.
final class GoogleTVController: TVController, @unchecked Sendable {
    let brand: TVBrand = .googleTV

    static let pairingPort = 6467
    static let remotePort = 6466

    private let lock = NSLock()
    private var pairings: [String: GTVLink] = [:]
    private var remotes: [String: GTVRemoteSession] = [:]

    // MARK: Discovery

    func discover() -> AsyncStream<DiscoveredTV> {
        AsyncStream { cont in
            let queue = DispatchQueue(label: "gtv.discover")
            let seen = SeenBox()
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_androidtvremote2._tcp", domain: nil), using: params)
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    guard case let .service(name, _, _, _) = r.endpoint, !seen.names.contains(name) else { continue }
                    seen.names.insert(name)
                    var serial: String?
                    if case let .bonjour(txt) = r.metadata, let bt = txt["bt"], !bt.isEmpty { serial = bt }
                    Self.resolve(r.endpoint, queue: queue) { host in
                        cont.yield(DiscoveredTV(brand: .googleTV, host: host, port: Self.remotePort,
                                                name: name, model: "Google TV", serial: serial))
                    }
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 8) {
                browser.cancel()
                cont.finish()
            }
            cont.onTermination = { _ in browser.cancel() }
        }
    }

    private final class SeenBox: @unchecked Sendable { var names = Set<String>() }

    /// Bonjour endpoint → IP, by opening (and immediately closing) a plain TCP connection.
    private static func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue, done: @escaping (String) -> Void) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case let .hostPort(host, _)? = conn.currentPath?.remoteEndpoint {
                    var h = "\(host)"
                    if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
                    done(h)
                }
                conn.cancel()
            case .failed, .waiting:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { conn.cancel() }
    }

    func probe(host: String) async -> DiscoveredTV? {
        guard let identity = try? GTVIdentity.identity() else { return nil }
        let link = GTVLink(host: host, port: Self.pairingPort, identity: identity, pinnedFingerprint: nil, label: "probe")
        defer { link.close() }
        do {
            try await link.start(timeout: 1.5)
            return DiscoveredTV(brand: .googleTV, host: host, port: Self.remotePort,
                                name: "Google TV (\(host))", model: "Google TV", serial: nil)
        } catch {
            return nil
        }
    }

    // MARK: Pairing

    private static let outerVersion = 2
    private static let statusOK = 200

    private static func outer(_ field: Int, _ build: (inout PBWriter) -> Void) -> PBWriter {
        var w = PBWriter()
        w.int(1, outerVersion)  // protocol_version
        w.int(2, statusOK)      // status
        w.message(field, build)
        return w
    }

    /// Waits for the TV's reply and checks it's OK and carries `field`.
    private static func expect(_ link: GTVLink, field: Int, timeout: TimeInterval = 10) async throws -> PBMessage {
        let raw = try await link.next(timeout: timeout)
        guard let msg = PBMessage(raw) else { throw TVControlError.other("The TV sent something unexpected.") }
        if let status = msg.int(2), status != statusOK { throw TVControlError.pairingRejected }
        guard msg.field(field) != nil else { throw TVControlError.pairingRejected }
        return msg
    }

    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws {
        await cancelPairing(tv)
        let identity: SecIdentity
        do { identity = try GTVIdentity.identity() } catch { throw TVControlError.other("Couldn't create this phone's TV certificate.") }
        let link = GTVLink(host: tv.host, port: Self.pairingPort, identity: identity, pinnedFingerprint: nil, label: "pair")
        try await link.start(timeout: 3)

        // 1. PairingRequest → PairingRequestAck
        try await link.send(Self.outer(10) { r in
            r.string(1, "atvremote")
            r.string(2, phoneName.isEmpty ? "Couch Remote" : phoneName)
        })
        _ = try await Self.expect(link, field: 11)

        // 2. Options: we enter a 6-digit hex code shown on the TV.
        try await link.send(Self.outer(20) { o in
            o.message(1) { e in e.int(1, 3); e.int(2, 6) }  // input_encodings: HEXADECIMAL, 6 symbols
            o.int(3, 1)                                      // preferred_role: INPUT
        })
        _ = try await Self.expect(link, field: 20)

        // 3. Configuration → ack; the TV now shows the code.
        try await link.send(Self.outer(30) { c in
            c.message(1) { e in e.int(1, 3); e.int(2, 6) }
            c.int(2, 1)  // client_role: INPUT
        })
        _ = try await Self.expect(link, field: 31)

        lock.withLock { pairings[tv.id] = link }
    }

    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws {
        guard let link = lock.withLock({ pairings[tv.id] }) else { throw TVControlError.pairingTimedOut }
        let code = pin.uppercased().filter { $0.isHexDigit }
        guard code.count == 6, let check = UInt8(code.prefix(2), radix: 16),
              let b1 = UInt8(code.dropFirst(2).prefix(2), radix: 16),
              let b2 = UInt8(code.dropFirst(4).prefix(2), radix: 16) else { throw TVControlError.badPIN }
        guard let serverCert = link.peerCertificate,
              let server = try? GTVIdentity.components(of: serverCert),
              let client = try? GTVIdentity.publicKeyComponents() else {
            throw TVControlError.other("Couldn't read the TV's certificate.")
        }

        var hasher = SHA256()
        hasher.update(data: Data(client.modulus))
        hasher.update(data: Data(client.exponent))
        hasher.update(data: Data(server.modulus))
        hasher.update(data: Data(server.exponent))
        hasher.update(data: Data([b1, b2]))
        let secret = Array(hasher.finalize())
        // The first byte of the hash is the code's first two characters: catches typos locally.
        guard secret[0] == check else { throw TVControlError.badPIN }

        try await link.send(Self.outer(40) { s in s.data(1, secret) })
        do {
            _ = try await Self.expect(link, field: 41)
        } catch TVControlError.pairingRejected {
            throw TVControlError.badPIN
        }
        Self.savePin(GTVIdentity.fingerprint(serverCert), for: tv)
        link.close()
        lock.withLock { pairings[tv.id] = nil }
    }

    func cancelPairing(_ tv: DiscoveredTV) async {
        let link = lock.withLock { () -> GTVLink? in
            let l = pairings[tv.id]; pairings[tv.id] = nil; return l
        }
        link?.close()
    }

    func isPaired(_ tv: DiscoveredTV) -> Bool { Self.loadPin(for: tv) != nil }

    func forget(_ tv: DiscoveredTV) {
        let s = lock.withLock { () -> GTVRemoteSession? in
            let r = remotes[tv.id]; remotes[tv.id] = nil; return r
        }
        s?.close()
        Self.deletePin(for: tv)
    }

    // MARK: Remote

    private func session(_ tv: DiscoveredTV) async throws -> GTVRemoteSession {
        if let s = lock.withLock({ remotes[tv.id] }), s.isAlive { return s }
        guard let pin = Self.loadPin(for: tv) else { throw TVControlError.notPaired }
        guard let identity = try? GTVIdentity.identity() else { throw TVControlError.notPaired }
        let s = GTVRemoteSession(host: tv.host, identity: identity, pinnedFingerprint: pin)
        do {
            try await s.connect()
        } catch {
            // A refused certificate (TV reset / re-paired elsewhere) shows up as a failed handshake.
            throw TVControlError.unreachable
        }
        lock.withLock { remotes[tv.id] = s }
        return s
    }

    /// Runs `body` on a live session, reconnecting once if the old connection died.
    private func withSession(_ tv: DiscoveredTV, _ body: (GTVRemoteSession) async throws -> Void) async throws {
        let s = try await session(tv)
        do {
            try await body(s)
        } catch {
            s.close()
            lock.withLock { if remotes[tv.id] === s { remotes[tv.id] = nil } }
            try await body(try await session(tv))
        }
    }

    private static func keyCode(_ key: RemoteKey) -> Int? {
        switch key {
        case .up: return 19
        case .down: return 20
        case .left: return 21
        case .right: return 22
        case .ok: return 23
        case .back: return 4
        case .home, .exit: return 3
        case .menu: return 82
        case .info: return 165
        case .playPause: return 85
        case .play: return 126
        case .pause: return 127
        case .seekForward: return 90
        case .seekBack: return 89
        case .volumeUp: return 24
        case .volumeDown: return 25
        case .muteToggle: return 164
        case .powerToggle, .powerOn, .powerOff: return 26
        case .inputNext: return 178
        case .ccToggle: return 175
        }
    }

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws {
        guard let code = Self.keyCode(key) else { return }
        try await withSession(tv) { s in
            // POWER toggles; skip it when the TV is already in the asked-for state.
            if key == .powerOn, s.isOn == true { return }
            if key == .powerOff, s.isOn == false { return }
            try await s.key(code)
        }
    }

    /// Catalog name → Android TV app link. Names match the app catalog (plus a few aliases).
    static let appLinks: [String: String] = [
        "Netflix": "https://www.netflix.com/title",
        "YouTube": "https://www.youtube.com",
        "Prime Video": "https://app.primevideo.com",
        "Disney+": "https://www.disneyplus.com",
        "Hulu": "https://www.hulu.com",
        "HBO Max": "https://play.max.com",
        "Max": "https://play.max.com",
        "Peacock": "https://www.peacocktv.com",
        "Paramount+": "https://www.paramountplus.com",
        "Plex": "plex://",
        "Spotify": "spotify://",
        "Tubi": "https://tubitv.com",
        "YouTube TV": "https://tv.youtube.com",
        "Apple TV+": "https://tv.apple.com",
    ]

    static let packageNames: [String: String] = [
        "com.netflix.ninja": "Netflix",
        "com.google.android.youtube.tv": "YouTube",
        "com.google.android.youtube.tvunplugged": "YouTube TV",
        "com.amazon.amazonvideo.livingroom": "Prime Video",
        "com.disney.disneyplus": "Disney+",
        "com.hulu.livingroomplus": "Hulu",
        "com.wbd.stream": "HBO Max",
        "com.hbo.hbonow": "HBO Max",
        "com.peacocktv.peacockandroid": "Peacock",
        "com.cbs.ott": "Paramount+",
        "com.plexapp.android": "Plex",
        "com.spotify.tv.android": "Spotify",
        "com.tubitv": "Tubi",
        "com.apple.atve.androidtv.appletv": "Apple TV+",
        "com.google.android.apps.tv.launcherx": "Home",
    ]

    func launch(_ tv: DiscoveredTV, appName: String) async throws {
        guard let link = Self.appLinks[appName] else { throw TVControlError.appUnavailable }
        try await withSession(tv) { s in try await s.launch(link) }
    }

    func availableApps(_ tv: DiscoveredTV) async -> [String] {
        Self.appLinks.keys.filter { $0 != "Max" }.sorted()
    }

    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying? {
        guard let s = try? await session(tv) else { return nil }
        guard let pkg = s.currentPackage else { return TVNowPlaying(appName: nil, appID: nil) }
        return TVNowPlaying(appName: Self.packageNames[pkg], appID: pkg)
    }

    func sendText(_ tv: DiscoveredTV, _ text: String) async throws {
        try await withSession(tv) { s in try await s.typeText(text) }
    }

    /// The IME batch edit sets the whole field, so the phone sends the full text each time.
    var textMode: TVTextMode { .replace }

    func backspace(_ tv: DiscoveredTV, count: Int) async throws {
        for _ in 0..<max(0, count) { try await withSession(tv) { s in try await s.key(67) } }  // KEYCODE_DEL
    }

    func submitText(_ tv: DiscoveredTV) async throws {
        try await withSession(tv) { s in try await s.key(66) }  // KEYCODE_ENTER
    }

    func openSearch(_ tv: DiscoveredTV) async throws {
        try await withSession(tv) { s in try await s.key(84) }  // KEYCODE_SEARCH
    }

    func keyboardEvents(_ tv: DiscoveredTV) -> AsyncStream<Bool> {
        AsyncStream { cont in
            let job = Task { [weak self] in
                guard let self, let s = try? await self.session(tv) else { cont.finish(); return }
                let token = s.addKeyboardListener { open in cont.yield(open) }
                cont.onTermination = { _ in s.removeKeyboardListener(token) }
            }
            _ = job
        }
    }

    // MARK: Pinned TV certificate (Keychain)

    private static func account(_ tv: DiscoveredTV) -> String { "tv.googleTV.\(tv.serial ?? tv.host)" }

    func didMove(from old: DiscoveredTV, to new: DiscoveredTV) async {
        guard Self.account(old) != Self.account(new), let pin = Self.loadPin(for: old) else { return }
        Self.savePin(pin, for: new)
        Self.deletePin(for: old)
    }

    private static func savePin(_ fingerprint: String, for tv: DiscoveredTV) {
        deletePin(for: tv)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "couchremote.tv",
            kSecAttrAccount as String: account(tv),
            kSecValueData as String: Data(fingerprint.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadPin(for tv: DiscoveredTV) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "couchremote.tv",
            kSecAttrAccount as String: account(tv),
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func deletePin(for tv: DiscoveredTV) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "couchremote.tv",
            kSecAttrAccount as String: account(tv),
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// A live connection to the TV's remote port. Handles the TV's configure / set-active /
/// ping handshake and keeps track of the foreground app and power state.
final class GTVRemoteSession: @unchecked Sendable {
    private let link: GTVLink
    private var configured = false
    private var active = false
    private var readyWaiter: CheckedContinuation<Void, Never>?
    private var imeCounter: Int?
    private var fieldCounter: Int?
    private var _currentPackage: String?
    private var _isOn: Bool?
    private var keyboardListeners: [UUID: (Bool) -> Void] = [:]

    /// Called (on the link queue) with true when the TV opens a text field's keyboard.
    func addKeyboardListener(_ f: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        link.queue.async { [self] in keyboardListeners[id] = f }
        return id
    }
    func removeKeyboardListener(_ id: UUID) { link.queue.async { [self] in keyboardListeners[id] = nil } }

    var currentPackage: String? { link.queue.sync { _currentPackage } }
    var isOn: Bool? { link.queue.sync { _isOn } }
    var isAlive: Bool { link.isOpen }

    init(host: String, identity: SecIdentity, pinnedFingerprint: String) {
        link = GTVLink(host: host, port: GoogleTVController.remotePort, identity: identity,
                       pinnedFingerprint: pinnedFingerprint, label: "remote")
        link.onMessage = { [weak self] msg in self?.handle(msg) }
    }

    func connect() async throws {
        try await link.start(timeout: 3)
        // Wait (briefly) for the TV's configure → set-active handshake before sending keys.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            link.queue.async { [self] in
                if active { cont.resume(); return }
                readyWaiter = cont
                link.queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, let w = self.readyWaiter else { return }
                    self.readyWaiter = nil
                    w.resume()
                }
            }
        }
    }

    func close() { link.close() }

    func key(_ code: Int) async throws {
        var w = PBWriter()
        w.message(10) { k in k.int(1, code); k.int(2, 3) }  // remote_key_inject, direction SHORT
        try await link.send(w)
    }

    func launch(_ appLink: String) async throws {
        var w = PBWriter()
        w.message(90) { l in l.string(1, appLink) }  // remote_app_link_launch_request
        try await link.send(w)
    }

    func typeText(_ text: String) async throws {
        let counters = link.queue.sync { (imeCounter, fieldCounter) }
        guard let ime = counters.0, let field = counters.1 else { throw TVControlError.unsupported }
        let pos = max(0, text.count - 1)
        var w = PBWriter()
        w.message(21) { b in                       // remote_ime_batch_edit
            b.int(1, ime)
            b.int(2, field)
            b.message(3) { e in                    // edit_info
                e.int(1, 1)                        // insert
                e.message(2) { o in                // text_field_status
                    o.int(1, pos)
                    o.int(2, pos)
                    o.string(3, text)
                }
            }
        }
        try await link.send(w)
    }

    // Runs on link.queue.
    private func handle(_ raw: [UInt8]) {
        guard let msg = PBMessage(raw) else { return }

        if msg.field(1) != nil {  // remote_configure from the TV → answer with ours
            configured = true
            var w = PBWriter()
            w.message(1) { c in
                c.int(1, 622)
                c.message(2) { d in
                    d.string(1, "iPhone")
                    d.string(2, "Apple")
                    d.int(3, 1)
                    d.string(4, "1")
                    d.string(5, "atvremote")
                    d.string(6, "1.0.0")
                }
            }
            sendDetached(w)
        }
        if msg.field(2) != nil {  // remote_set_active → we're active
            var w = PBWriter()
            w.message(2) { a in a.int(1, 622) }
            sendDetached(w)
            active = true
            if let r = readyWaiter { readyWaiter = nil; r.resume() }
        }
        if let ping = msg.message(8) {  // remote_ping_request → response with the same value
            let val = ping.int(1) ?? 0
            var w = PBWriter()
            w.message(9) { p in p.int(1, val) }
            sendDetached(w)
        }
        if let ime = msg.message(20) {  // remote_ime_key_inject: foreground app + text field
            if let app = ime.message(1) {
                if let pkg = app.string(12), !pkg.isEmpty { _currentPackage = pkg }
                if let c = app.int(1) { imeCounter = c }
            }
            if let status = ime.message(2), let c = status.int(1) { fieldCounter = c }
        }
        if let show = msg.message(22) {  // remote_ime_show_request: a text field wants the keyboard
            if let field = show.message(2), let c = field.int(1) { fieldCounter = c }
            keyboardListeners.values.forEach { $0(true) }
        }
        if let start = msg.message(40) {  // remote_start: TV turned on / off
            _isOn = (start.int(1) ?? 0) != 0
        }
    }

    private func sendDetached(_ w: PBWriter) {
        Task { [link] in try? await link.send(w) }
    }
}
