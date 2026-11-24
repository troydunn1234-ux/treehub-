import Foundation
import Combine
import UserNotifications

/// An optional, gentle daily nudge. Off by default; one local notification a day at the chosen time.
final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    static let category = "STILLPOINT_REMINDER"
    static let requestId = "sp.daily"
    private static let enabledKey = "sp.reminder.on"
    private static let hourKey = "sp.reminder.hour"
    private static let minuteKey = "sp.reminder.minute"

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { requestAndSchedule() } else { cancel() }
            Self.bedtimeTextChanged()
        }
    }

    /// Only the hour and minute matter; the day is ignored.
    @Published var time: Date {
        didSet {
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            UserDefaults.standard.set(c.hour ?? 21, forKey: Self.hourKey)
            UserDefaults.standard.set(c.minute ?? 0, forKey: Self.minuteKey)
            if enabled { schedule() }
            Self.bedtimeTextChanged()
        }
    }

    /// False when the person turned the reminder on but notifications are denied in Settings.
    @Published private(set) var denied = false

    private override init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Self.enabledKey)
        let hour = d.object(forKey: Self.hourKey) as? Int ?? 21
        let minute = d.object(forKey: Self.minuteKey) as? Int ?? 0
        time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        super.init()
    }

    /// Call once at launch: registers the category so a tap opens the app, and keeps the schedule fresh.
    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: "open", title: "Begin", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.category, actions: [open], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        if enabled { refreshAuthorization() }
    }

    private func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                self.denied = s.authorizationStatus == .denied
                if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional { self.schedule() }
            }
        }
    }

    private func requestAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.denied = !granted
                if granted { self.schedule() }
            }
        }
    }

    /// Called when the bedtime pick is turned on/off or moved: drops or restores this reminder's own notification.
    func refreshSchedule() {
        if enabled { refreshAuthorization() } else { cancel() }
    }

    /// The reminder's hour (0–23).
    var hour: Int { Calendar.current.component(.hour, from: time) }

    /// True when the bedtime pick carries this reminder tonight instead of a separate notification.
    var folded: Bool {
        EveningReminder.folded(reminderOn: enabled, reminderHour: hour, bedtimeOn: EveningReminder.bedtimeOnSaved())
    }

    /// The bedtime pick's text includes "Haven't practiced yet today?" when this reminder is folded into it.
    private static func bedtimeTextChanged() {
        Task { @MainActor in DailyMoments.shared.reschedule(RightNow.shared) }
    }

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestId])
        // One evening notification, not two: the bedtime pick already carries this nudge. Removing the pending
        // request above also clears a separate one left by an earlier build.
        if folded { return }
        let content = UNMutableNotificationContent()
        content.title = "Still Pointz"
        content.body = Self.copy()
        content.sound = .default
        content.categoryIdentifier = Self.category
        var comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.requestId, content: content, trigger: trigger))
    }

    private func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestId])
    }

    /// Gentle, varied copy; picked by the day the reminder is scheduled.
    private static func copy() -> String {
        let lines = [
            "Two minutes of stillness?",
            "A few slow breaths, whenever you're ready.",
            "The day can wait a moment. Breathe.",
            "Time to sit for a little while?",
            "Nothing to do but breathe, for two minutes.",
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return lines[day % lines.count]
    }

    // Show the banner even if the app is already open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// A tap on the reminder simply brings the app to the Today tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Stress nudge: open straight into the suggested practice.
        let info = response.notification.request.content.userInfo
        if let id = info["practiceId"] as? String {
            Router.queue(practiceId: id, minutes: info["minutes"] as? Int)
        }
        DispatchQueue.main.async { Reminders.onOpen?() }
        completionHandler()
    }

    /// Set by the app to route the tap (e.g. switch to Today).
    static var onOpen: (() -> Void)?
}

/// Keeps the evenings to one notification. The old daily reminder (default 9 PM) and the bedtime "Right now" pick
/// (default 9:30 PM) used to both fire. When the bedtime pick is on and the reminder is set for the evening, the
/// reminder schedules nothing of its own and the bedtime pick says "Haven't practiced yet today?" instead.
/// With the bedtime pick off (or a morning/daytime reminder) the reminder works exactly as before.
enum EveningReminder {
    /// From 5 PM on counts as the evening.
    static let eveningStartHour = 17

    static func isEvening(hour: Int) -> Bool { hour >= eveningStartHour }

    /// Whether the daily reminder skips its own notification because the bedtime pick carries it.
    static func folded(reminderOn: Bool, reminderHour: Int, bedtimeOn: Bool) -> Bool {
        reminderOn && bedtimeOn && isEvening(hour: reminderHour)
    }

    /// Whether the daily reminder schedules its own notification.
    static func reminderSchedulesOwn(reminderOn: Bool, reminderHour: Int, bedtimeOn: Bool) -> Bool {
        reminderOn && !folded(reminderOn: reminderOn, reminderHour: reminderHour, bedtimeOn: bedtimeOn)
    }

    /// Whether one bedtime pick should add the "Haven't practiced yet today?" nudge: only when the reminder is folded
    /// into it, and not on a day that already has a session.
    static func bedtimeNudge(reminderOn: Bool, reminderHour: Int, bedtimeOn: Bool, practicedThatDay: Bool) -> Bool {
        folded(reminderOn: reminderOn, reminderHour: reminderHour, bedtimeOn: bedtimeOn) && !practicedThatDay
    }

    /// The bedtime pick's text, with or without the folded-in nudge.
    static func bedtimeBody(because: String, title: String, minutes: Int, nudge: Bool) -> String {
        nudge ? String(localized: "Haven't practiced yet today? \(title) · \(minutes) min wind-down. \(because).")
              : String(localized: "\(because). \(title) · \(minutes) min")
    }

    /// The saved bedtime-pick switch, read the same way DailyMoments does (default on). Read only, never written.
    static func bedtimeOnSaved(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: "sp.moment.bedOn") as? Bool ?? true
    }
}
