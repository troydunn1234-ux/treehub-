import Foundation
import UserNotifications

/// One day of WHOOP numbers typed in by hand (Log WHOOP sheet). Every field is optional: only what was
/// filled is stored. Merged into `LabStore.whoopDays` / `sleeps` as WHOOP data; the WHOOP API wins per field.
struct WhoopManualEntry: Codable, Equatable, Identifiable {
    var day: Date                // start of day (local): the morning the recovery belongs to
    var id: Date { day }
    var recovery: Double?        // %
    var strain: Double?          // 0–21
    var sleepPerformance: Double?// %
    var hrv: Double?             // ms (RMSSD)
    var rhr: Double?             // bpm
    var resp: Double?            // breaths/min
    var steps: Double?
    var sleepMin: Double?        // minutes asleep
    var kcal: Double?
    var savedAt = Date()

    init(day: Date) { self.day = day.dayStart }

    var isEmpty: Bool {
        [recovery, strain, sleepPerformance, hrv, rhr, resp, steps, sleepMin, kcal].allSatisfy { $0 == nil }
    }
}

/// Which manual field a number came from, so screens can badge it "WHOOP · MANUAL".
enum ManualField: String, CaseIterable {
    case recovery, strain, sleepPerformance, hrv, rhr, resp, steps, sleep, kcal

    /// All data screen stat ids → field.
    static func forStat(_ id: String) -> ManualField? {
        switch id {
        case "recovery": .recovery
        case "strain": .strain
        case "performance": .sleepPerformance
        case "hrv": .hrv
        case "rhr": .rhr
        case "resp": .resp
        case "steps": .steps
        case "asleep": .sleep
        case "totalKcal": .kcal
        default: nil
        }
    }
}

/// Small JSON file in Application Support holding every manual entry, keyed by day.
enum WhoopManualStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("whoop-manual.json")
    }

    static func load() -> [Date: WhoopManualEntry] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WhoopManualEntry].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.day.dayStart, $0) }, uniquingKeysWith: { a, b in a.savedAt > b.savedAt ? a : b })
    }

    static func save(_ entries: [Date: WhoopManualEntry]) {
        let list = entries.values.sorted { $0.day < $1.day }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// The morning ask: the automatic pop-up and the daily "Log today's WHOOP" notification.
enum WhoopPrompt {
    static let askKey = "whoopAskMorning"
    static let lastAskedKey = "whoopAskedDay"
    static let reminderKey = "whoopReminder"
    static let hourKey = "whoopReminderHour"
    static let minuteKey = "whoopReminderMinute"
    static let idPrefix = "com.troydunn.pulselab.whoopLog."
    static let url = URL(string: "pulselab://log-whoop")!

    /// "Ask me for WHOOP numbers each morning" (pop-up). On by default.
    static var askEnabled: Bool {
        get { UserDefaults.standard.object(forKey: askKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: askKey) }
    }
    /// Daily reminder notification. On by default; only scheduled once notifications are allowed.
    static var reminderOn: Bool {
        get { UserDefaults.standard.object(forKey: reminderKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: reminderKey) }
    }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 8 }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0 }

    static var reminderTime: Date {
        get { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            UserDefaults.standard.set(c.hour ?? 8, forKey: hourKey)
            UserDefaults.standard.set(c.minute ?? 0, forKey: minuteKey)
        }
    }

    /// Pop the sheet? After 6 am, once per day, only when today has no WHOOP recovery (API or manual).
    @MainActor
    static func shouldAsk(_ store: LabStore, now: Date = Date()) -> Bool {
        guard askEnabled, !LabStore.isDemo, Calendar.current.component(.hour, from: now) >= 6 else { return false }
        if UserDefaults.standard.double(forKey: lastAskedKey) >= now.dayStart.timeIntervalSince1970 { return false }
        return store.whoopDays.stat(on: now)?.recovery == nil
    }

    static func markAsked(_ now: Date = Date()) {
        UserDefaults.standard.set(now.dayStart.timeIntervalSince1970, forKey: lastAskedKey)
    }

    /// First save from the sheet: ask for notification permission (once) if the reminder is on.
    static func askPermissionIfNeeded(loggedToday: Bool) async {
        guard reminderOn else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await reschedule(loggedToday: loggedToday)
    }

    /// Turning the reminder on in Settings. False when notifications are denied.
    @discardableResult
    static func enableReminder(loggedToday: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        reminderOn = granted
        await reschedule(loggedToday: loggedToday)
        return granted
    }

    /// One notification per morning for the next 14 days at the chosen time, skipping today once it's logged.
    /// Rebuilt after every sync and save, so it keeps rolling forward. Does nothing until permission was given.
    static func reschedule(loggedToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<14).map { "\(idPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard reminderOn else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let now = Date(), cal = Calendar.current
        for i in 0..<14 {
            if i == 0 && loggedToday { continue }
            let day = now.dayStart.adding(days: i)
            guard let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Log today's WHOOP — 20 seconds"
            c.body = "Recovery, strain and sleep from the WHOOP app, so Pulse Lab can compare."
            c.sound = .default
            c.userInfo = ["url": url.absoluteString]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: ids[i], content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

/// Opening the Log WHOOP sheet from outside a view (notification tap, Siri, URL): RootView watches this.
enum LogWhoopPending {
    static let key = "pl.pendingLogWhoop"
    static let note = Notification.Name("pl.pendingLogWhoop")

    static func queue() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        NotificationCenter.default.post(name: note, object: nil)
    }

    static func take() -> Bool {
        let d = UserDefaults.standard
        let at = d.double(forKey: key)
        guard at > 0 else { return false }
        d.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - at < 120
    }
}
