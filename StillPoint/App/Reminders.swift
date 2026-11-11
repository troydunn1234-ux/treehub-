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
        }
    }

    /// Only the hour and minute matter; the day is ignored.
    @Published var time: Date {
        didSet {
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            UserDefaults.standard.set(c.hour ?? 21, forKey: Self.hourKey)
            UserDefaults.standard.set(c.minute ?? 0, forKey: Self.minuteKey)
            if enabled { schedule() }
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

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestId])
        let content = UNMutableNotificationContent()
        content.title = "Still Point"
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
        DispatchQueue.main.async { Reminders.onOpen?() }
        completionHandler()
    }

    /// Set by the app to route the tap (e.g. switch to Today).
    static var onOpen: (() -> Void)?
}
