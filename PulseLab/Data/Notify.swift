import Foundation
import UserNotifications

/// Weekly summary: one local notification every Sunday at 6 pm ("WHOOP vs Watch this week").
/// Off by default; Settings flips `enabled`, and `LabStore.refresh` calls `reschedule` so the
/// text always reflects the latest agreement numbers.
enum Notify {
    static let key = "weeklySummary"
    static let identifier = "com.troydunn.pulselab.weekly"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Ask for permission (first time only) and schedule. Returns false if the user has denied notifications.
    @discardableResult
    static func enable(agreements: [Agreement]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { enabled = false; return false }
        enabled = true
        reschedule(agreements: agreements)
        return true
    }

    static func disable() {
        enabled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Replace the pending request with one carrying the latest one-line stat. No-op when off.
    static func reschedule(agreements: [Agreement]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "WHOOP vs Watch this week"
        content.body = line(agreements)
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 1      // Sunday
        comps.hour = 18
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// "Agreed on 5 of 6 metrics · RHR gap 3 bpm" — built from whatever has at least 3 days of overlap.
    static func line(_ agreements: [Agreement]) -> String {
        let scored = agreements.filter { $0.n >= 3 }
        guard !scored.isEmpty else { return "Wear both trackers a few more days and the weekly verdict fills in." }
        let agreed = scored.filter { ($0.agreePercent ?? 0) >= 55 }.count
        var parts = ["Agreed on \(agreed) of \(scored.count) metric\(scored.count == 1 ? "" : "s")"]
        if let rhr = scored.first(where: { $0.metric == "Resting HR" }), let b = rhr.bias {
            parts.append("RHR gap \(Int(abs(b).rounded())) bpm")
        } else if let sleep = scored.first(where: { $0.metric == "Sleep" }), let b = sleep.bias {
            parts.append("Sleep gap \(Int((abs(b) * 60).rounded())) min")
        }
        return parts.joined(separator: " · ")
    }
}
