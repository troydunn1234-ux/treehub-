import SwiftUI
import Security

struct StreamingApp: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let configs: [VizioClient.AppConfig]

    /// A rich two-tone gradient per app (no logos, just a vibe).
    var colors: [Color] {
        let known: [String: (UInt32, UInt32)] = [
            "Netflix": (0xE50914, 0x3B0306), "YouTube": (0xFF2D2D, 0x5A0A0A), "YouTube TV": (0xFF4F4F, 0x4A0A16),
            "Prime Video": (0x1FA8FF, 0x0A2A55), "Hulu": (0x1CE783, 0x0B3B26), "Disney+": (0x3D7BFF, 0x0B1546),
            "HBO Max": (0x8A3BFF, 0x1E0B4A), "Peacock": (0xFFC93D, 0x3A2A00), "Paramount+": (0x2F7BFF, 0x061E5A),
            "Apple TV+": (0xBFC4CC, 0x1A1C20), "Tubi": (0xFF6A3D, 0x3D1300), "Pluto TV": (0xFFD23D, 0x2A2400),
            "Plex": (0xE5A00D, 0x2B1F02), "Sling TV": (0x2BA3FF, 0x0A2340), "fuboTV": (0xFF5A1F, 0x3A1200),
            "discovery+": (0x2F6BFF, 0x081A4A), "STARZ": (0x3A3A3A, 0x0A0A0A), "AMC+": (0x8C8C8C, 0x161616),
            "Vudu": (0x3D8BFF, 0x0A1E44), "Crackle": (0xFF8A00, 0x3A1F00), "PBS": (0x2F7BFF, 0x0A1D4A),
            "Pandora": (0x3D7BFF, 0x0A1438), "iHeartRadio": (0xE5002B, 0x3A000B), "TikTok": (0xFF2D6F, 0x112A33),
        ]
        if let (a, b) = known[name] { return [Color(hex: a), Color(hex: b)] }
        // Stable color from the name for everything else.
        var h: UInt32 = 2166136261
        for u in name.unicodeScalars { h = (h ^ u.value) &* 16777619 }
        let hue = Double(h % 360) / 360
        return [Color(hue: hue, saturation: 0.75, brightness: 0.95), Color(hue: hue, saturation: 0.85, brightness: 0.25)]
    }

    var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if name.count <= 7 { return name }
        return words.prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

@MainActor
@Observable
final class TVStore {
    let client = VizioClient()
    @ObservationIgnored lazy var discovery = TVDiscovery(client: client)

    /// Every TV this phone is paired with, and which one the remote controls.
    private(set) var tvs: [VizioClient.TVInfo] = [] { didSet { saveTVs() } }
    private(set) var activeID: String? = nil { didSet { UserDefaults.standard.set(activeID, forKey: "activeTV") } }
    var tv: VizioClient.TVInfo? { tvs.first { $0.id == activeID } ?? tvs.first }
    private(set) var reconnecting = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var lastReconnect = Date.distantPast
    private(set) var catalog: [StreamingApp] = []
    var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "favorites") } }
    private(set) var nowPlaying: String?
    private(set) var screenOn: Bool?
    private(set) var reachable = true
    var toast: String?
    var errorText: String?

    private var auth: String? { tv.flatMap { Keychain.get($0.id) } }
    private(set) var isPaired = false

    private func saveTVs() {
        guard !Self.demo, let d = try? JSONEncoder().encode(tvs) else { return }
        UserDefaults.standard.set(d, forKey: "tvs")
    }

    private func updatePaired() { isPaired = Self.demo || (tv != nil && auth != nil) }

    static let defaultFavorites = ["Netflix", "YouTube", "Prime Video", "Hulu", "Disney+", "HBO Max",
                                   "Peacock", "Paramount+", "Apple TV+", "YouTube TV", "Tubi", "Pluto TV"]

    init() {
        favorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? Self.defaultFavorites
        loadCatalog()
        if Self.demo {
            tvs = [VizioClient.TVInfo(host: "192.168.1.40", port: 7345, name: "Living Room TV", model: "V-Series 65", tokenKey: "demo.1"),
                   VizioClient.TVInfo(host: "192.168.1.41", port: 7345, name: "Bedroom TV", model: "M-Series 50", tokenKey: "demo.2")]
            activeID = "demo.1"
            nowPlaying = "HBO Max"
        } else {
            if let d = UserDefaults.standard.data(forKey: "tvs"), let list = try? JSONDecoder().decode([VizioClient.TVInfo].self, from: d) {
                tvs = list
            } else if let d = UserDefaults.standard.data(forKey: "tv"), var old = try? JSONDecoder().decode(VizioClient.TVInfo.self, from: d) {
                // One-time move from the single-TV version: its token lives at "auth.<host>".
                old.tokenKey = "auth.\(old.host)"
                tvs = [old]
                UserDefaults.standard.removeObject(forKey: "tv")
            }
            activeID = UserDefaults.standard.string(forKey: "activeTV") ?? tvs.first?.id
            // Observers don't run during init, so save explicitly (keeps the migrated TV).
            saveTVs()
            UserDefaults.standard.set(activeID, forKey: "activeTV")
        }
        updatePaired()
    }

    /// Simulator screenshots: pretend a TV is paired and never touch the network.
    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    private func loadCatalog() {
        struct Raw: Decodable { let name: String; let config: [VizioClient.AppConfig]? }
        guard let url = Bundle.main.url(forResource: "vizio_apps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([Raw].self, from: data) else { return }
        catalog = raw.compactMap { r in
            guard let c = r.config, !c.isEmpty else { return nil }
            return StreamingApp(name: r.name, configs: c)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var favoriteApps: [StreamingApp] { favorites.compactMap { f in catalog.first { $0.name == f } } }

    func app(matching cfg: VizioClient.AppConfig) -> StreamingApp? {
        catalog.first { $0.configs.contains { $0.APP_ID == cfg.APP_ID && $0.NAME_SPACE == cfg.NAME_SPACE } }
            ?? catalog.first { $0.configs.contains { $0.APP_ID == cfg.APP_ID } }
    }

    // MARK: Pairing

    private var pairing: (token: Int, challenge: Int)?
    private var pairingTV: VizioClient.TVInfo?

    func beginPairing(with t: VizioClient.TVInfo) async -> Bool {
        errorText = nil
        do {
            pairing = try await client.startPairing(t, deviceName: "Clicker (\(UIDevice.current.name))")
            pairingTV = t
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func finishPairing(pin: String) async -> Bool {
        guard let t = pairingTV, let p = pairing else { return false }
        errorText = nil
        do {
            let token = try await client.finishPairing(t, pin: pin, token: p.token, challenge: p.challenge)
            var paired = t
            // Re-pairing a TV we already know keeps its slot; otherwise it's a new one.
            if let existing = tvs.firstIndex(where: { $0.isSameTV(as: t) }) {
                paired.tokenKey = tvs[existing].id
                tvs[existing] = paired
            } else {
                paired.tokenKey = "auth.\(t.serial ?? UUID().uuidString)"
                tvs.append(paired)
            }
            Keychain.set(token, for: paired.id)
            await client.pinCertificate(for: t.host, port: t.port)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { activeID = paired.id }
            reachable = true
            updatePaired()
            nowPlaying = nil
            pairing = nil; pairingTV = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            errorText = "That code didn't work. Check the code on your TV and try again."
            return false
        }
    }

    func cancelPairing() async {
        if let t = pairingTV, let p = pairing { await client.cancelPairing(t, token: p.token, challenge: p.challenge) }
        pairing = nil; pairingTV = nil
    }

    /// Forget the active TV.
    func forgetTV() { if let t = tv { forget(t) } }

    func forget(_ t: VizioClient.TVInfo) {
        Keychain.delete(t.id)
        VizioClient.forgetPin(host: t.host)
        tvs.removeAll { $0.id == t.id }
        if activeID == t.id { activeID = tvs.first?.id; nowPlaying = nil }
        reachable = true
        updatePaired()
    }

    func switchTo(_ t: VizioClient.TVInfo) {
        guard t.id != activeID else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            activeID = t.id
            nowPlaying = nil
            reachable = true
        }
        failures = 0
        updatePaired()
        Task { await refresh() }
    }

    // MARK: Reconnect

    /// The TV stopped answering. Look for it on the Wi-Fi; if it shows up at a new
    /// address (router restart, moved rooms), quietly switch to the new address.
    func reconnect(userInitiated: Bool = false) async {
        guard !Self.demo, let lost = tv, !reconnecting else { return }
        if !userInitiated && Date().timeIntervalSince(lastReconnect) < 60 { return }
        lastReconnect = Date()
        reconnecting = true
        defer { reconnecting = false }
        discovery.start()
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if let found = discovery.found.first(where: { $0.isSameTV(as: lost) || $0.host == lost.host }) {
                discovery.stop()
                if found.host != lost.host || found.port != lost.port {
                    if let i = tvs.firstIndex(where: { $0.id == lost.id }) {
                        var moved = tvs[i]
                        VizioClient.forgetPin(host: found.host)   // new address: trust its cert fresh
                        moved.host = found.host
                        moved.port = found.port
                        if moved.serial == nil { moved.serial = found.serial }
                        tvs[i] = moved
                        await client.pinCertificate(for: found.host, port: found.port)
                    }
                    show("Found \(lost.name) again")
                } else if userInitiated {
                    show("\(lost.name) is back")
                }
                failures = 0
                reachable = true
                await refresh()
                return
            }
            if !discovery.searching && Date() > deadline.addingTimeInterval(-20) { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        discovery.stop()
        if userInitiated { show("Couldn't find \(lost.name). Is it on and on this Wi-Fi?") }
    }

    private func noteUnreachable() {
        reachable = false
        failures += 1
        if failures >= 2 { Task { await reconnect() } }
    }

    // MARK: Actions

    func launch(_ app: StreamingApp) async {
        if Self.demo { show("Opening \(app.name) on your TV"); nowPlaying = app.name; return }
        guard let t = tv, let a = auth else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Some apps have more than one launch recipe depending on the TV's software; try each.
        var lastError: Error?
        for cfg in app.configs {
            do {
                try await client.launch(t, auth: a, app: cfg)
                show("Opening \(app.name) on your TV")
                nowPlaying = app.name
                reachable = true
                failures = 0
                return
            } catch { lastError = error }
        }
        handle(lastError)
    }

    func press(_ key: VizioClient.Key) {
        if Self.demo { return }
        guard let t = tv, let a = auth else { return }
        Task {
            do { try await client.press(t, auth: a, key); reachable = true; failures = 0 } catch { handle(error) }
        }
    }

    func refresh() async {
        if Self.demo { return }
        guard let t = tv, let a = auth else { return }
        do {
            let cur = try await client.currentApp(t, auth: a)
            nowPlaying = cur.flatMap { app(matching: $0)?.name }
            reachable = true
            failures = 0
            screenOn = await client.powerState(t, auth: a)
        } catch VizioClient.VizioError.notPaired {
            handle(VizioClient.VizioError.notPaired)
        } catch {
            noteUnreachable()
        }
    }

    private func handle(_ error: Error?) {
        guard let error else { return }
        if case VizioClient.VizioError.unreachable = error { noteUnreachable() }
        if case VizioClient.VizioError.notPaired = error, let t = tv { Keychain.delete(t.id); updatePaired() }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        show(error.localizedDescription)
    }

    func show(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toast == text { withAnimation(.easeOut) { toast = nil } }
        }
    }

    func toggleFavorite(_ app: StreamingApp) {
        if let i = favorites.firstIndex(of: app.name) { favorites.remove(at: i) } else { favorites.append(app.name) }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// Minimal Keychain wrapper for the TV's auth token.
enum Keychain {
    static func set(_ value: String, for key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}
