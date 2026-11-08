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

    private(set) var tv: VizioClient.TVInfo?
    private(set) var catalog: [StreamingApp] = []
    var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "favorites") } }
    private(set) var nowPlaying: String?
    private(set) var screenOn: Bool?
    private(set) var reachable = true
    var toast: String?
    var errorText: String?

    private var auth: String? { tv.flatMap { Keychain.get("auth.\($0.host)") } }
    private(set) var isPaired = false

    static let defaultFavorites = ["Netflix", "YouTube", "Prime Video", "Hulu", "Disney+", "HBO Max",
                                   "Peacock", "Paramount+", "Apple TV+", "YouTube TV", "Tubi", "Pluto TV"]

    init() {
        favorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? Self.defaultFavorites
        if let d = UserDefaults.standard.data(forKey: "tv"), let t = try? JSONDecoder().decode(VizioClient.TVInfo.self, from: d) { tv = t }
        loadCatalog()
        isPaired = tv != nil && auth != nil
    }

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
            Keychain.set(token, for: "auth.\(t.host)")
            await client.pinCertificate(for: t.host, port: t.port)
            tv = t
            isPaired = true
            if let d = try? JSONEncoder().encode(t) { UserDefaults.standard.set(d, forKey: "tv") }
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

    func forgetTV() {
        if let t = tv { Keychain.delete("auth.\(t.host)"); VizioClient.forgetPin(host: t.host) }
        tv = nil
        isPaired = false
        UserDefaults.standard.removeObject(forKey: "tv")
        nowPlaying = nil
    }

    // MARK: Actions

    func launch(_ app: StreamingApp) async {
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
                return
            } catch { lastError = error }
        }
        handle(lastError)
    }

    func press(_ key: VizioClient.Key) {
        guard let t = tv, let a = auth else { return }
        Task {
            do { try await client.press(t, auth: a, key); reachable = true } catch { handle(error) }
        }
    }

    func refresh() async {
        guard let t = tv, let a = auth else { return }
        do {
            let cur = try await client.currentApp(t, auth: a)
            nowPlaying = cur.flatMap { app(matching: $0)?.name }
            reachable = true
            screenOn = await client.powerState(t, auth: a)
        } catch VizioClient.VizioError.notPaired {
            handle(VizioClient.VizioError.notPaired)
        } catch {
            reachable = false
        }
    }

    private func handle(_ error: Error?) {
        guard let error else { return }
        if case VizioClient.VizioError.unreachable = error { reachable = false }
        if case VizioClient.VizioError.notPaired = error, let t = tv { Keychain.delete("auth.\(t.host)"); isPaired = false }
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
