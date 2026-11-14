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
        static let bestStreak = "bestStreak"
        static let practicedToday = "practicedToday"
        static let streakDay = "streakDay"
        static let suggestedDetail = "suggestedDetail"
        static let suggestedSymbol = "suggestedSymbol"
        /// A sitting practice for the "Breathe Now" control (the routine may be a movement one).
        static let breatheId = "breatheId"
        /// A sauna / steam timer running on this device (Watch complication): kind raw value + start time.
        static let heatKind = "heatKind"
        static let heatStart = "heatStart"
    }

    /// Kinds of the widgets, for targeted reloads.
    static let heatComplicationKinds = ["StillPointHeat.sauna", "StillPointHeat.steam"]

    /// Deep link that starts (or opens) a practice: `stillpoint://practice/<id>`.
    static func practiceURL(_ id: String) -> URL? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "\(urlScheme)://practice/\(safe)")
    }

    /// Deep link that starts (or opens) a sauna / steam timer: `stillpoint://heat/<sauna|steam>`.
    static func heatURL(_ kind: HeatKind) -> URL? { URL(string: "\(urlScheme)://heat/\(kind.rawValue)") }

    /// The heat kind in a `stillpoint://heat/<kind>` link, or nil for other links.
    static func heatKind(from url: URL) -> HeatKind? {
        guard url.scheme?.lowercased() == urlScheme, url.host?.lowercased() == "heat" else { return nil }
        let k = url.pathComponents.filter { $0 != "/" }.first?.lowercased() ?? ""
        return HeatKind(rawValue: k) ?? .sauna
    }

    /// Tell the Watch complications a heat timer started (kind + start) or stopped (nil).
    static func publishHeat(kind: HeatKind?, start: Date?) {
        let d = UserDefaults(suiteName: suite) ?? .standard
        if let kind, let start {
            d.set(kind.rawValue, forKey: Key.heatKind)
            d.set(start.timeIntervalSince1970, forKey: Key.heatStart)
        } else {
            d.removeObject(forKey: Key.heatKind)
            d.removeObject(forKey: Key.heatStart)
        }
        #if canImport(WidgetKit)
        for k in heatComplicationKinds { WidgetCenter.shared.reloadTimelines(ofKind: k) }
        #endif
    }

    /// The practice id in a `stillpoint://practice/<id>` link, or nil for other links.
    static func practiceId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == urlScheme, url.host?.lowercased() == "practice" else { return nil }
        let id = url.pathComponents.filter { $0 != "/" }.first ?? ""
        return id.isEmpty ? nil : id.removingPercentEncoding ?? id
    }

    /// Call after every session save, goal change, and on launch / foreground.
    static func publish(log: SessionLog = .shared, library lib: PracticeLibrary = .shared) {
        let suggestion = suggestedPractice(library: lib, log: log)
        let d = UserDefaults(suiteName: suite) ?? .standard
        d.set(log.streak, forKey: Key.streak)
        d.set(log.bestStreak, forKey: Key.bestStreak)
        d.set(log.practicedToday, forKey: Key.practicedToday)
        // The streak's last day: today if practiced, else yesterday (the streak counts up to yesterday).
        let today = Calendar.current.startOfDay(for: Date())
        let lastDay = log.practicedToday ? today : Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        d.set(log.streak > 0 ? lastDay.timeIntervalSince1970 : 0, forKey: Key.streakDay)
        let usual = Prefs.shared.settings.defaultMinutes
        let mins = suggestion.minutes.contains(usual) ? usual : suggestion.defaultMinutes
        let label = suggestion.focus?.title ?? lib.tradition(suggestion.traditionId)?.name ?? "Breathe"
        d.set("\(label) · \(mins) min", forKey: Key.suggestedDetail)
        d.set(suggestion.focus?.symbol ?? "wind", forKey: Key.suggestedSymbol)
        let hour = Calendar.current.component(.hour, from: Date())
        d.set((sittingPractice(library: lib, hour: hour, now: Date(), skip: []) ?? lib.quickPractice).id, forKey: Key.breatheId)
        d.set(log.calendarWeekMinutes, forKey: Key.weekMinutes)
        d.set(log.weeklyGoal, forKey: Key.weekGoal)
        d.set(suggestion.title, forKey: Key.suggestedTitle)
        d.set(suggestion.id, forKey: Key.suggestedId)
        d.set(Date().timeIntervalSince1970, forKey: Key.updated)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Today's routine: joint circles first thing, a stretch in the evening (each once a day, if one is open),
    /// otherwise a sitting practice that suits the hour. Stable within a part of the day so the widget doesn't flicker.
    static func suggestedPractice(library lib: PracticeLibrary = .shared, log: SessionLog? = nil, now: Date = Date()) -> Practice {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let doneToday = Set((log?.sessions(on: now) ?? []).filter { $0.seconds >= 60 }.map(\.practiceId))
        let routineFocus: BodyFocus? = (5..<11).contains(hour) ? .joint : (17..<21).contains(hour) ? .stretch : nil
        if let f = routineFocus {
            let open = lib.practices(focus: f).filter { !lib.isLocked($0) }
            let doneFocus = open.contains { doneToday.contains($0.id) }
            if !doneFocus, let pick = open.first { return pick }
        }
        if let s = sittingPractice(library: lib, hour: hour, now: now, skip: doneToday) { return s }
        return lib.quickPractice
    }

    private static func sittingPractice(library lib: PracticeLibrary, hour: Int, now: Date, skip: Set<String>) -> Practice? {
        let cal = Calendar.current
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
        var candidates = open.isEmpty ? pool : open
        // Already done today? Offer the next one.
        let fresh = candidates.filter { !skip.contains($0.id) }
        if !fresh.isEmpty { candidates = fresh }
        guard !candidates.isEmpty else { return nil }
        let day = cal.ordinality(of: .day, in: .year, for: now) ?? 0
        return candidates[day % candidates.count]
    }
}
