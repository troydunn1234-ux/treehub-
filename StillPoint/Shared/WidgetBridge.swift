import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hands the widget / complication what it shows: streak, this week's minutes vs goal, and a suggested practice.
/// Writes to the App Group suite so the widget extension (a separate target) can read it, then asks WidgetKit to refresh.
enum WidgetBridge {
    static let suite = "group.com.troydunn.stillpoint"
    static let urlScheme = "stillpoint"

    enum Key {
        static let streak = "streak"
        static let weekMinutes = "weekMinutes"
        static let weekGoal = "weekGoal"
        static let suggestedTitle = "suggestedTitle"
        static let suggestedId = "suggestedId"
        static let updated = "updated"
    }

    /// Deep link that starts (or opens) a practice: `stillpoint://practice/<id>`.
    static func practiceURL(_ id: String) -> URL? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "\(urlScheme)://practice/\(safe)")
    }

    /// The practice id in a `stillpoint://practice/<id>` link, or nil for other links.
    static func practiceId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == urlScheme, url.host?.lowercased() == "practice" else { return nil }
        let id = url.pathComponents.filter { $0 != "/" }.first ?? ""
        return id.isEmpty ? nil : id.removingPercentEncoding ?? id
    }

    /// Call after every session save, goal change, and on launch / foreground.
    static func publish(log: SessionLog = .shared, library lib: PracticeLibrary = .shared) {
        let suggestion = suggestedPractice(library: lib)
        let d = UserDefaults(suiteName: suite) ?? .standard
        d.set(log.streak, forKey: Key.streak)
        d.set(log.calendarWeekMinutes, forKey: Key.weekMinutes)
        d.set(log.weeklyGoal, forKey: Key.weekGoal)
        d.set(suggestion.title, forKey: Key.suggestedTitle)
        d.set(suggestion.id, forKey: Key.suggestedId)
        d.set(Date().timeIntervalSince1970, forKey: Key.updated)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// A practice that suits the hour: wake-up in the morning, focus by day, calm in the evening, wind-down at night.
    /// Stable for the whole day so the widget doesn't flicker between refreshes. Prefers practices the person can run.
    static func suggestedPractice(library lib: PracticeLibrary = .shared, now: Date = Date()) -> Practice {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let wanted: [String]
        switch hour {
        case 5..<11: wanted = ["morning", "energy", "focus"]
        case 11..<17: wanted = ["focus", "calm"]
        case 17..<21: wanted = ["calm", "gratitude", "compassion"]
        default: wanted = ["sleep", "calm"]
        }
        var pool: [Practice] = []
        if hour >= 21 || hour < 5, let wind = lib.tradition("wind-down") {
            pool += lib.practices(in: wind)
        }
        for w in wanted {
            if let i = lib.intentions.first(where: { $0.id.lowercased() == w || $0.name.lowercased() == w }) {
                pool += lib.practices(for: i)
            }
        }
        // Sitting practices only (a widget tap should land somewhere you can simply begin).
        pool = pool.filter { !$0.isMovement }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.id).inserted }
        let open = pool.filter { !lib.isLocked($0) }
        let candidates = open.isEmpty ? pool : open
        guard !candidates.isEmpty else { return lib.quickPractice }
        let day = cal.ordinality(of: .day, in: .year, for: now) ?? 0
        return candidates[day % candidates.count]
    }
}
