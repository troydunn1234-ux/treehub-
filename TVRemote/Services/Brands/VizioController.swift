import Foundation
import Network

/// VIZIO SmartCast TVs (2016+), over VizioClient. Pairing shows a 4-digit code on the TV.
/// Auth tokens live in the Keychain at "tv.vizio.<serial or host>".
final class VizioController: TVController, @unchecked Sendable {
    let brand: TVBrand = .vizio
    let client = VizioClient()

    private let lock = NSLock()
    private var pending: [String: (token: Int, challenge: Int)] = [:]

    /// Brand catalog: app name → launch recipes (some apps have several depending on TV software).
    let catalog: [String: [VizioClient.AppConfig]]

    init() {
        struct Raw: Decodable { let name: String; let config: [VizioClient.AppConfig]? }
        var c: [String: [VizioClient.AppConfig]] = [:]
        if let url = Bundle.main.url(forResource: "vizio_apps", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([Raw].self, from: data) {
            for r in raw { if let cfg = r.config, !cfg.isEmpty { c[r.name] = cfg } }
        }
        catalog = c
    }

    static func tokenKey(_ tv: DiscoveredTV) -> String { "tv.vizio.\(tv.serial ?? tv.host)" }
    private func token(_ tv: DiscoveredTV) -> String? { Keychain.get(Self.tokenKey(tv)) }
    private func info(_ tv: DiscoveredTV) -> VizioClient.TVInfo {
        VizioClient.TVInfo(host: tv.host, port: tv.port, name: tv.name, model: tv.model, serial: tv.serial)
    }
    private static func make(_ i: VizioClient.TVInfo) -> DiscoveredTV {
        DiscoveredTV(brand: .vizio, host: i.host, port: i.port, name: i.name, model: i.model, serial: i.serial)
    }

    private func map(_ error: Error) -> Error {
        guard let v = error as? VizioClient.VizioError else { return error }
        switch v {
        case .unreachable: return TVControlError.unreachable
        case .notPaired: return TVControlError.notPaired
        case .rejected(let r): return TVControlError.other("The TV said: \(r.replacingOccurrences(of: "_", with: " ").lowercased()).")
        case .badResponse: return TVControlError.other("The TV sent back something unexpected.")
        }
    }

    // MARK: Discovery

    func discover() -> AsyncStream<DiscoveredTV> {
        let client = self.client
        return AsyncStream { continuation in
            let seen = SeenHosts()
            let emit: @Sendable (VizioClient.TVInfo) -> Void = { i in
                if seen.insert(i.host) { continuation.yield(Self.make(i)) }
            }
            // Bonjour: TVs that advertise SmartCast.
            let params = NWParameters.tcp
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjour(type: "_viziocast._tcp", domain: nil), using: params)
            let queue = DispatchQueue(label: "vizio.discovery")
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    let conn = NWConnection(to: r.endpoint, using: .tcp)
                    conn.stateUpdateHandler = { state in
                        guard case .ready = state else { return }
                        if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                            var h = "\(host)"
                            if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
                            let p = Int(port.rawValue)
                            conn.cancel()
                            Task { if let tv = await client.probe(host: h, port: p == 0 ? 7345 : p, timeout: 3) { emit(tv) } }
                        } else { conn.cancel() }
                    }
                    conn.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + 5) { conn.cancel() }
                }
            }
            browser.start(queue: queue)

            // Subnet sweep for TVs that don't advertise.
            let scan = Task {
                if let prefix = TVDiscovery.wifiPrefix() {
                    let hosts = (1...254).map { "\(prefix).\($0)" }
                    await withTaskGroup(of: VizioClient.TVInfo?.self) { group in
                        var it = hosts.makeIterator()
                        func next() -> Bool {
                            guard let h = it.next() else { return false }
                            group.addTask {
                                if Task.isCancelled { return nil }
                                if let tv = await client.probe(host: h, port: 7345, timeout: 1.2) { return tv }
                                return await client.probe(host: h, port: 9000, timeout: 0.8)
                            }
                            return true
                        }
                        for _ in 0..<32 { if !next() { break } }
                        while let r = await group.next() {
                            if let r { emit(r) }
                            _ = next()
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                browser.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in scan.cancel(); browser.cancel() }
        }
    }

    func probe(host: String) async -> DiscoveredTV? {
        if let i = await client.probe(host: host, port: 7345, timeout: 3) { return Self.make(i) }
        if let i = await client.probe(host: host, port: 9000, timeout: 3) { return Self.make(i) }
        return nil
    }

    // MARK: Pairing

    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws {
        do {
            let p = try await client.startPairing(info(tv), deviceName: phoneName)
            lock.lock(); pending[tv.id] = p; lock.unlock()
        } catch { throw map(error) }
    }

    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws {
        lock.lock(); let p = pending[tv.id]; lock.unlock()
        guard let p else { throw TVControlError.notPaired }
        do {
            let auth = try await client.finishPairing(info(tv), pin: pin, token: p.token, challenge: p.challenge)
            Keychain.set(auth, for: Self.tokenKey(tv))
            await client.pinCertificate(for: tv.host, port: tv.port)
            lock.lock(); pending[tv.id] = nil; lock.unlock()
        } catch VizioClient.VizioError.unreachable {
            throw TVControlError.unreachable
        } catch {
            throw TVControlError.badPIN
        }
    }

    func cancelPairing(_ tv: DiscoveredTV) async {
        lock.lock(); let p = pending.removeValue(forKey: tv.id); lock.unlock()
        if let p { await client.cancelPairing(info(tv), token: p.token, challenge: p.challenge) }
    }

    func isPaired(_ tv: DiscoveredTV) -> Bool { token(tv) != nil }

    func forget(_ tv: DiscoveredTV) {
        Keychain.delete(Self.tokenKey(tv))
        VizioClient.forgetPin(host: tv.host)
    }

    /// The TV moved to a new address: keep its token, trust its certificate fresh.
    func didMove(from old: DiscoveredTV, to new: DiscoveredTV) async {
        let oldKey = Self.tokenKey(old), newKey = Self.tokenKey(new)
        if oldKey != newKey, let t = Keychain.get(oldKey) { Keychain.set(t, for: newKey); Keychain.delete(oldKey) }
        if old.host != new.host {
            VizioClient.forgetPin(host: new.host)
            await client.pinCertificate(for: new.host, port: new.port)
        }
    }

    // MARK: Control

    private func vizioKey(_ k: RemoteKey) -> VizioClient.Key {
        switch k {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .ok: return .ok
        case .back: return .back
        case .home: return .home
        case .menu: return .menu
        case .info: return .info
        case .exit: return .exit
        case .play, .playPause: return .play
        case .pause: return .pause
        case .seekForward: return .seekForward
        case .seekBack: return .seekBack
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .muteToggle: return .muteToggle
        case .powerToggle: return .powerToggle
        case .powerOn: return .powerOn
        case .powerOff: return .powerOff
        case .inputNext: return .inputNext
        case .ccToggle: return .ccToggle
        }
    }

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws {
        guard let auth = token(tv) else { throw TVControlError.notPaired }
        do { try await client.press(info(tv), auth: auth, vizioKey(key)) } catch { throw map(error) }
    }

    func launch(_ tv: DiscoveredTV, appName: String) async throws {
        guard let auth = token(tv) else { throw TVControlError.notPaired }
        guard let configs = catalog[appName], !configs.isEmpty else { throw TVControlError.appUnavailable }
        var last: Error = TVControlError.appUnavailable
        for cfg in configs {
            do { try await client.launch(info(tv), auth: auth, app: cfg); return } catch { last = map(error) }
        }
        throw last
    }

    func availableApps(_ tv: DiscoveredTV) async -> [String] { Array(catalog.keys).sorted() }

    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying? {
        guard let auth = token(tv) else { return nil }
        guard let cur = try? await client.currentApp(info(tv), auth: auth) else { return nil }
        let name = catalog.first { $0.value.contains { $0.APP_ID == cur.APP_ID && $0.NAME_SPACE == cur.NAME_SPACE } }?.key
            ?? catalog.first { $0.value.contains { $0.APP_ID == cur.APP_ID } }?.key
        return TVNowPlaying(appName: name, appID: cur.APP_ID)
    }

    /// Throws on unreachable/unpaired so the store can react; nowPlaying() swallows errors.
    func check(_ tv: DiscoveredTV) async throws -> TVNowPlaying {
        guard let auth = token(tv) else { throw TVControlError.notPaired }
        do {
            let cur = try await client.currentApp(info(tv), auth: auth)
            guard let cur else { return TVNowPlaying(appName: nil, appID: nil) }
            let name = catalog.first { $0.value.contains { $0.APP_ID == cur.APP_ID && $0.NAME_SPACE == cur.NAME_SPACE } }?.key
                ?? catalog.first { $0.value.contains { $0.APP_ID == cur.APP_ID } }?.key
            return TVNowPlaying(appName: name, appID: cur.APP_ID)
        } catch { throw map(error) }
    }

    func sendText(_ tv: DiscoveredTV, _ text: String) async throws { throw TVControlError.unsupported }
    /// SmartCast's local API has no text-entry command (pyvizio and the SmartCast app protocol only
    /// expose key presses, app launch and settings), so typing from the phone isn't possible.
    var textMode: TVTextMode { .none }

    // MARK: Migration from the Vizio-only app

    /// Old builds saved [VizioClient.TVInfo] under "tvs" with tokens at TVInfo.id. Convert once.
    static func migrateLegacy() -> (tvs: [DiscoveredTV], activeID: String?)? {
        let d = UserDefaults.standard
        var legacy: [VizioClient.TVInfo] = []
        if let data = d.data(forKey: "tvs"), let list = try? JSONDecoder().decode([VizioClient.TVInfo].self, from: data) {
            legacy = list
        } else if let data = d.data(forKey: "tv"), var old = try? JSONDecoder().decode(VizioClient.TVInfo.self, from: data) {
            old.tokenKey = "auth.\(old.host)"
            legacy = [old]
        } else {
            return nil
        }
        let oldActive = d.string(forKey: "activeTV")
        var out: [DiscoveredTV] = []
        var active: String?
        for i in legacy {
            // Keep a stable id even for TVs without a serial, so the token follows IP changes.
            let serial = (i.serial?.isEmpty == false) ? i.serial! : "legacy-\(i.id)"
            let tv = DiscoveredTV(brand: .vizio, host: i.host, port: i.port, name: i.name, model: i.model, serial: serial)
            if let t = Keychain.get(i.id) { Keychain.set(t, for: tokenKey(tv)) }
            out.append(tv)
            if i.id == oldActive { active = tv.id }
        }
        d.removeObject(forKey: "tvs")
        d.removeObject(forKey: "tv")
        return (out, active ?? out.first?.id)
    }
}

/// Thread-safe "have we reported this host yet" set used by discovery streams.
final class SeenHosts: @unchecked Sendable {
    private var set = Set<String>()
    private let lock = NSLock()
    /// True the first time a host is inserted.
    func insert(_ h: String) -> Bool { lock.lock(); defer { lock.unlock() }; return set.insert(h).inserted }
}
