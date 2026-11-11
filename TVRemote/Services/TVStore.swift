import SwiftUI
import Security

struct StreamingApp: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String

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
    /// The one store the app, Siri (App Intents), Scenes and the Watch bridge all share.
    static let shared = TVStore()

    // One controller per brand. Each speaks its TV's own local-network protocol.
    @ObservationIgnored let vizio = VizioController()
    @ObservationIgnored private(set) lazy var controllers: [TVBrand: TVController] = [
        .vizio: vizio, .roku: RokuController(), .samsung: SamsungController(),
        .lg: LGController(), .googleTV: GoogleTVController(),
    ]
    func controller(for brand: TVBrand) -> TVController { controllers[brand] ?? vizio }

    @ObservationIgnored lazy var discovery = TVDiscovery(controllers: TVBrand.allCases.map { controller(for: $0) })

    /// Every TV this phone is paired with, and which one the remote controls.
    private(set) var tvs: [DiscoveredTV] = [] { didSet { saveTVs() } }
    private(set) var activeID: String? = nil { didSet { UserDefaults.standard.set(activeID, forKey: "activeDevice") } }
    var tv: DiscoveredTV? { tvs.first { $0.id == activeID } ?? tvs.first }
    private(set) var reconnecting = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var lastReconnect = Date.distantPast
    private(set) var catalog: [StreamingApp] = []
    var favorites: [String] { didSet { UserDefaults.standard.set(favorites, forKey: "favorites") } }
    private(set) var nowPlaying: String?
    private(set) var reachable = true
    var toast: String?
    var errorText: String?
    private(set) var isPaired = false

    private func saveTVs() {
        guard !Self.demo, let d = try? JSONEncoder().encode(tvs) else { return }
        UserDefaults.standard.set(d, forKey: "devices")
    }

    private func updatePaired() {
        isPaired = Self.demo || (tv.map { controller(for: $0.brand).isPaired($0) } ?? false)
    }

    static let defaultFavorites = ["Netflix", "YouTube", "Prime Video", "Hulu", "Disney+", "HBO Max",
                                   "Peacock", "Paramount+", "Apple TV+", "YouTube TV", "Tubi", "Pluto TV"]

    static let demoTVs: [DiscoveredTV] = [
        DiscoveredTV(brand: .vizio, host: "192.168.1.40", port: 7345, name: "Living Room TV", model: "V-Series 65", serial: "demo1"),
        DiscoveredTV(brand: .samsung, host: "192.168.1.41", port: 8002, name: "Bedroom TV", model: "Crystal UHD 55", serial: "demo2"),
        DiscoveredTV(brand: .roku, host: "192.168.1.42", port: 8060, name: "Basement Roku", model: "TCL Roku TV 50", serial: "demo3"),
    ]

    init() {
        favorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? Self.defaultFavorites
        loadCatalog()
        if Self.demo {
            tvs = Self.demoTVs
            activeID = Self.demoTVs[0].id
            nowPlaying = "HBO Max"
        } else {
            tvs = Self.loadSaved()
            if let migrated = VizioController.migrateLegacy() {
                for t in migrated.tvs where !tvs.contains(where: { $0.id == t.id }) { tvs.append(t) }
                activeID = UserDefaults.standard.string(forKey: "activeDevice") ?? migrated.activeID
            } else {
                activeID = UserDefaults.standard.string(forKey: "activeDevice") ?? tvs.first?.id
            }
            // Observers don't run during init, so save explicitly (keeps migrated TVs).
            saveTVs()
            UserDefaults.standard.set(activeID, forKey: "activeDevice")
        }
        updatePaired()
        watchKeyboard()
    }

    private static func loadSaved() -> [DiscoveredTV] {
        guard let d = UserDefaults.standard.data(forKey: "devices"),
              let list = try? JSONDecoder().decode([DiscoveredTV].self, from: d) else { return [] }
        return list
    }

    /// Simulator screenshots: pretend TVs are paired and never touch the network.
    static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") || UserDefaults.standard.bool(forKey: "demoMode") }
    /// Demo started from the setup screen (not from screenshots), so it can be exited.
    var inAppDemo: Bool { UserDefaults.standard.bool(forKey: "demoMode") }

    /// "Try the demo": explore the whole app with pretend TVs of different brands, no network.
    func startDemo() {
        UserDefaults.standard.set(true, forKey: "demoMode")
        tvs = Self.demoTVs
        activeID = Self.demoTVs[0].id
        nowPlaying = "HBO Max"
        updatePaired()
        show("Demo mode: nothing is sent to a TV")
    }

    func endDemo() {
        UserDefaults.standard.set(false, forKey: "demoMode")
        tvs = Self.loadSaved()
        activeID = UserDefaults.standard.string(forKey: "activeDevice").flatMap { id in tvs.first { $0.id == id }?.id } ?? tvs.first?.id
        nowPlaying = nil
        updatePaired()
    }

    private func loadCatalog() {
        // The app list is brand-neutral: names (+ colors). Each brand's controller knows how to open them.
        var names = Set(vizio.catalog.keys)
        // Popular apps every brand has, even if the VIZIO list lacks them.
        names.formUnion(Self.defaultFavorites)
        catalog = names.map { StreamingApp(name: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var favoriteApps: [StreamingApp] { favorites.compactMap { f in catalog.first { $0.name == f } } }

    // MARK: Pairing

    private var pairingTV: DiscoveredTV?
    var phoneName: String { "Couch Remote (\(UIDevice.current.name))" }

    /// Starts pairing. For PIN brands the TV now shows a code (call finishPairing next).
    /// For "Allow" brands this waits until the user accepts on the TV, then the TV is saved.
    /// For Roku it just connects. Returns true when the step succeeded.
    func beginPairing(with t: DiscoveredTV) async -> Bool {
        errorText = nil
        // Free: one TV. A second TV (that isn't the same set moving IPs) is Pro.
        if !tvs.isEmpty, !tvs.contains(where: { sameTV($0, t) }), !Unlock.shared.gate("A second TV") { return false }
        let c = controller(for: t.brand)
        do {
            try await c.beginPairing(t, phoneName: phoneName)
            pairingTV = t
            if t.brand.pairing != .pinOnTV { completePairing(t) }
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func finishPairing(pin: String) async -> Bool {
        guard let t = pairingTV else { return false }
        errorText = nil
        do {
            try await controller(for: t.brand).finishPairing(t, pin: pin)
            completePairing(t)
            return true
        } catch {
            errorText = (error as? TVControlError)?.errorDescription ?? "That code didn't work. Check the code on your TV and try again."
            return false
        }
    }

    private func completePairing(_ t: DiscoveredTV) {
        if let i = tvs.firstIndex(where: { sameTV($0, t) }) { tvs[i] = t } else { tvs.append(t) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { activeID = t.id }
        reachable = true
        failures = 0
        nowPlaying = nil
        pairingTV = nil
        updatePaired()
        watchKeyboard()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func cancelPairing() async {
        if let t = pairingTV { await controller(for: t.brand).cancelPairing(t) }
        pairingTV = nil
    }

    /// Forget the active TV.
    func forgetTV() { if let t = tv { forget(t) } }

    func forget(_ t: DiscoveredTV) {
        if !Self.demo { controller(for: t.brand).forget(t) }
        tvs.removeAll { $0.id == t.id }
        if activeID == t.id { activeID = tvs.first?.id; nowPlaying = nil }
        reachable = true
        updatePaired()
    }

    func switchTo(_ t: DiscoveredTV) {
        guard t.id != activeID else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            activeID = t.id
            nowPlaying = nil
            reachable = true
        }
        failures = 0
        updatePaired()
        closeKeyboard()
        watchKeyboard()
        Task { await refresh() }
    }

    /// Same physical TV? Same brand, and the same hardware id, else same name + model.
    func sameTV(_ a: DiscoveredTV, _ b: DiscoveredTV) -> Bool {
        guard a.brand == b.brand else { return false }
        let real: (String?) -> String? = { s in (s?.isEmpty == false && !(s!.hasPrefix("legacy-"))) ? s : nil }
        if let x = real(a.serial), let y = real(b.serial) { return x == y }
        return (a.name == b.name && a.model == b.model) || a.host == b.host
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
            if let found = discovery.found.first(where: { sameTV($0, lost) }) {
                discovery.stop()
                if found.host != lost.host || found.port != lost.port {
                    if let i = tvs.firstIndex(where: { $0.id == lost.id }) {
                        var moved = tvs[i]
                        moved.host = found.host
                        moved.port = found.port
                        // Keep the saved id (and its credentials) stable when the TV had none.
                        if moved.serial == nil, let s = found.serial { moved.serial = s }
                        await controller(for: lost.brand).didMove(from: lost, to: moved)
                        tvs[i] = moved
                        if activeID == lost.id { activeID = moved.id }
                    }
                    show("Found \(lost.name) again")
                } else if userInitiated {
                    show("\(lost.name) is back")
                }
                failures = 0
                reachable = true
                updatePaired()
                await refresh()
                return
            }
            if !discovery.searching { break }
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
        guard let t = tv else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do {
            try await controller(for: t.brand).launch(t, appName: app.name)
            show("Opening \(app.name) on your TV")
            nowPlaying = app.name
            reachable = true
            failures = 0
            Reviews.noteWin()
        } catch {
            handle(error)
        }
    }

    func press(_ key: RemoteKey) {
        if Self.demo { return }
        guard let t = tv else { return }
        let c = controller(for: t.brand)
        Task {
            do { try await c.press(t, key); reachable = true; failures = 0 } catch { handle(error) }
        }
    }

    func sendText(_ text: String) async {
        if Self.demo { show("Typed on your TV"); return }
        guard let t = tv else { return }
        do { try await controller(for: t.brand).sendText(t, text) } catch { handle(error) }
    }

    // MARK: Phone keyboard ("Type on TV")

    /// The keyboard bar is showing.
    var typing = false
    /// The TV said a text field is focused (LG, Samsung, Google TV report this).
    private(set) var tvWantsKeyboard = false
    /// What we believe is in the TV's text field right now.
    @ObservationIgnored private var sentText = ""
    @ObservationIgnored private var pendingText: String?
    @ObservationIgnored private var typeTask: Task<Void, Never>?
    @ObservationIgnored private var keyboardWatch: Task<Void, Never>?

    /// Can the active TV take typing at all?
    var canType: Bool {
        guard let t = tv else { return false }
        return Self.demo || controller(for: t.brand).textMode != .none
    }

    func openKeyboard() {
        guard Unlock.shared.gate("Typing on your TV") else { return }
        sentText = ""
        pendingText = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { typing = true }
    }

    func closeKeyboard() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { typing = false }
        tvWantsKeyboard = false
    }

    /// Called on every edit in the phone's text field; sends only what changed, ~150 ms after typing pauses.
    func typed(_ text: String) {
        pendingText = text
        typeTask?.cancel()
        typeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushTyping()
        }
    }

    private func flushTyping() async {
        guard let new = pendingText else { return }
        pendingText = nil
        let old = sentText
        guard new != old else { return }
        if Self.demo { sentText = new; return }
        guard let t = tv else { return }
        let c = controller(for: t.brand)
        do {
            switch c.textMode {
            case .none:
                return
            case .replace:
                // Clearing the box: delete keys where the TV has them, else send the empty field.
                if new.isEmpty, (try? await c.backspace(t, count: old.count)) != nil {
                } else {
                    try await c.sendText(t, new)
                }
            case .append:
                // Common prefix, then delete the rest of the old text and type the rest of the new.
                let common = zip(old, new).prefix { $0.0 == $0.1 }.count
                let deletes = old.count - common
                let insert = String(new.dropFirst(common))
                if deletes > 0 { try await c.backspace(t, count: deletes) }
                if !insert.isEmpty { try await c.sendText(t, insert) }
            }
            sentText = new
            reachable = true
        } catch TVControlError.unsupported {
            // e.g. no backspace on this TV: fall back to typing just the new characters
            if new.count > old.count, new.hasPrefix(old) {
                try? await c.sendText(t, String(new.dropFirst(old.count)))
                sentText = new
            }
        } catch {
            handle(error)
        }
    }

    /// The keyboard's Return key: send what's left, then submit.
    func submitTyping() {
        typeTask?.cancel()
        Task {
            await flushTyping()
            if Self.demo { show("Typed \"\(sentText)\" on your TV"); closeKeyboard(); return }
            guard let t = tv else { return }
            do { try await controller(for: t.brand).submitText(t) } catch { handle(error) }
            closeKeyboard()
        }
    }

    /// Open the TV's search, then the phone keyboard. Brands without a search key just open the keyboard.
    func searchOnTV() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if Self.demo { show("Search opened on your TV"); openKeyboard(); return }
        guard let t = tv else { return }
        let c = controller(for: t.brand)
        Task {
            do { try await c.openSearch(t) } catch TVControlError.unsupported { } catch { handle(error); return }
            if c.textMode != .none { openKeyboard() } else {
                show("Search is open. VIZIO TVs don't take typing from phones, so use the TV remote's voice button or arrows.")
            }
        }
    }

    /// Listen for the active TV's on-screen keyboard and pop the phone keyboard to match.
    func watchKeyboard() {
        keyboardWatch?.cancel()
        guard !Self.demo, let t = tv else { return }
        let c = controller(for: t.brand)
        guard c.textMode != .none else { return }
        keyboardWatch = Task { [weak self] in
            while !Task.isCancelled {
                for await open in c.keyboardEvents(t) {
                    guard let self, self.tv?.id == t.id else { return }
                    self.tvWantsKeyboard = open
                    if open, !self.typing { self.openKeyboard() }
                    if !open, self.typing { self.closeKeyboard() }
                }
                // Stream ended (socket dropped or brand can't report): try again later.
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, self.tv?.id == t.id else { return }
            }
        }
    }

    func refresh() async {
        if Self.demo { return }
        guard let t = tv else { return }
        let c = controller(for: t.brand)
        if let v = c as? VizioController {
            do {
                nowPlaying = try await v.check(t).appName
                reachable = true; failures = 0
            } catch TVControlError.notPaired {
                handle(TVControlError.notPaired)
            } catch {
                noteUnreachable()
            }
            return
        }
        if let now = await c.nowPlaying(t) {
            nowPlaying = now.appName
            reachable = true; failures = 0
        }
    }

    private func handle(_ error: Error?) {
        guard let error else { return }
        if case TVControlError.unreachable = error { noteUnreachable() }
        if case TVControlError.notPaired = error, let t = tv { controller(for: t.brand).forget(t); updatePaired() }
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

/// Keychain storage for each TV's auth token.
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
