import Foundation
import Combine

enum HapticStyle: String, Codable, CaseIterable, Identifiable {
    case subtle, strong, off
    var id: String { rawValue }
    var label: String {
        switch self { case .subtle: return "Subtle"; case .strong: return "Strong"; case .off: return "Off" }
    }
}

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case timer, cycles
    var id: String { rawValue }
    var label: String { self == .timer ? "Timer" : "Breaths" }
}

/// Everything the user can tune about how a session feels. Shared by iPhone and Watch and synced between them.
struct SessionSettings: Codable, Equatable {
    var haptics: HapticStyle = .strong
    /// A gentle click every second of the exhale, so you can count without looking.
    var exhaleTicks: Bool = false
    /// Start / end bells (felt as haptics on the Watch).
    var bells: Bool = true
    /// Interval bell every N minutes; 0 = off.
    var intervalMinutes: Int = 0
    var sound: Bool = false
    /// Watch: vibration only. Uses only the silent tap haptic, in patterns, so nothing
    /// ever makes a sound even with the Watch unmuted. Off = Apple's richer haptics (which chime).
    var silentHaptics: Bool = true
    /// After a few seconds the screen fades to near-black with only the orb.
    var dimScreen: Bool = false
    var showNumbers: Bool = true
    var mode: SessionMode = .timer
    var cycles: Int = 12
    var defaultMinutes: Int = 5
    /// Watch only: live heart rate during sessions.
    var trackHeartRate: Bool = true
    /// Watch only: also save the session as a Mind & Body workout.
    var saveAsWorkout: Bool = false
    /// Count warm-up / movement minutes as Mindful Minutes in Apple Health.
    var logMovementAsMindful: Bool = false

    static let key = "sp.settings"

    static func load() -> SessionSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(SessionSettings.self, from: d) else { return SessionSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func asDictionary() -> [String: Any] {
        guard let d = try? JSONEncoder().encode(self) else { return [:] }
        return ["settings": d]
    }

    static func from(_ dict: [String: Any]) -> SessionSettings? {
        guard let d = dict["settings"] as? Data else { return nil }
        return try? JSONDecoder().decode(SessionSettings.self, from: d)
    }

    init() {}

    // Tolerant decoding so adding fields never wipes saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SessionSettings.Defaults()
        haptics = (try? c.decode(HapticStyle.self, forKey: .haptics)) ?? d.haptics
        exhaleTicks = (try? c.decode(Bool.self, forKey: .exhaleTicks)) ?? d.exhaleTicks
        bells = (try? c.decode(Bool.self, forKey: .bells)) ?? d.bells
        intervalMinutes = (try? c.decode(Int.self, forKey: .intervalMinutes)) ?? d.intervalMinutes
        sound = (try? c.decode(Bool.self, forKey: .sound)) ?? d.sound
        silentHaptics = (try? c.decode(Bool.self, forKey: .silentHaptics)) ?? true
        dimScreen = (try? c.decode(Bool.self, forKey: .dimScreen)) ?? d.dimScreen
        showNumbers = (try? c.decode(Bool.self, forKey: .showNumbers)) ?? d.showNumbers
        mode = (try? c.decode(SessionMode.self, forKey: .mode)) ?? d.mode
        cycles = (try? c.decode(Int.self, forKey: .cycles)) ?? d.cycles
        defaultMinutes = (try? c.decode(Int.self, forKey: .defaultMinutes)) ?? d.defaultMinutes
        trackHeartRate = (try? c.decode(Bool.self, forKey: .trackHeartRate)) ?? d.trackHeartRate
        saveAsWorkout = (try? c.decode(Bool.self, forKey: .saveAsWorkout)) ?? d.saveAsWorkout
        logMovementAsMindful = (try? c.decode(Bool.self, forKey: .logMovementAsMindful)) ?? false
    }

    private struct Defaults {
        let haptics = HapticStyle.strong, exhaleTicks = false, bells = true, intervalMinutes = 0, sound = false
        let dimScreen = false, showNumbers = true, mode = SessionMode.timer, cycles = 12, defaultMinutes = 5
        let trackHeartRate = true, saveAsWorkout = false
    }
}

/// App-wide preferences: settings, favorites, recents. Observable from SwiftUI.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var settings: SessionSettings { didSet { settings.save(); onChange?() } }
    @Published private(set) var favorites: [String]
    @Published private(set) var recents: [String]
    /// Still Point Pro is unlocked (on iPhone: from the App Store; on Watch: mirrored from the phone).
    @Published private(set) var pro: Bool

    /// Called after settings or favorites change (used to sync to the other device).
    var onChange: (() -> Void)?

    private init() {
        settings = SessionSettings.load()
        favorites = UserDefaults.standard.stringArray(forKey: "sp.favorites") ?? []
        recents = UserDefaults.standard.stringArray(forKey: "sp.recents") ?? []
        pro = UserDefaults.standard.bool(forKey: "sp.pro")
    }

    func setPro(_ on: Bool) {
        guard on != pro else { return }
        pro = on
        UserDefaults.standard.set(on, forKey: "sp.pro")
        onChange?()
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.insert(id, at: 0) }
        UserDefaults.standard.set(favorites, forKey: "sp.favorites")
        onChange?()
    }

    func setFavorites(_ ids: [String]) {
        guard ids != favorites else { return }
        favorites = ids
        UserDefaults.standard.set(favorites, forKey: "sp.favorites")
    }

    func markRecent(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
        UserDefaults.standard.set(recents, forKey: "sp.recents")
    }

    /// Apply settings received from the other device without echoing them back.
    func applyRemote(_ s: SessionSettings, favorites fav: [String]?, pro: Bool? = nil) {
        let saved = onChange
        onChange = nil
        if s != settings { settings = s }
        if let fav { setFavorites(fav) }
        if let pro { setPro(pro) }
        onChange = saved
    }
}

/// Keys used between iPhone and Watch.
enum SyncKey {
    static let command = "cmd"
    static let start = "start"
    static let practiceId = "practiceId"
    static let minutes = "minutes"
    static let favorites = "favorites"
    static let pro = "pro"
    static let session = "session"
    static let weekGoal = "weekGoal"
}
