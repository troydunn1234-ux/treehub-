import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Local notifications and Home Screen widget data for the bundled web apps.
///
/// Page → native (window.webkit.messageHandlers.native.postMessage):
///   {op:"notify", action:"status"}                       → "authorized" | "denied" | "notDetermined"
///   {op:"notify", action:"permission"}                   → true when allowed (asks the first time)
///   {op:"notify", action:"now", id, title, body}         → shows a notification right away
///   {op:"notify", action:"schedule", prefix, items:[{id, title, body, at}]}
///        replaces every pending notification whose id starts with prefix; `at` is seconds since 1970
///   {op:"notify", action:"cancel", prefix}               → removes pending ones with that prefix
///   {op:"widget", json}                                  → saves json for the app's widget (App Group in
///                                                          Info.plist WebShellAppGroup) and reloads it
/// Nothing here leaves the phone.
final class ShellNotify: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ShellNotify()
    static let widgetKey = "shell.widget"

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// Show banners even while the app is open (budget alerts usually fire right after a bank sync).
    func install() { center.delegate = self }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    static var appGroup: String? {
        let g = ShellConfig.info["WebShellAppGroup"] as? String ?? ""
        return g.isEmpty ? nil : g
    }

    static func saveWidget(json: String) {
        guard let g = appGroup, let d = UserDefaults(suiteName: g) else { return }
        if d.string(forKey: widgetKey) == json { return }
        d.set(json, forKey: widgetKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func handle(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        install()
        let action = body["action"] as? String ?? ""
        switch action {
        case "status":
            center.getNotificationSettings { s in
                let v: String
                switch s.authorizationStatus {
                case .authorized, .provisional, .ephemeral: v = "authorized"
                case .denied: v = "denied"
                default: v = "notDetermined"
                }
                DispatchQueue.main.async { reply(v, nil) }
            }
        case "permission":
            center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                DispatchQueue.main.async { reply(ok, nil) }
            }
        case "now":
            let id = body["id"] as? String ?? UUID().uuidString
            let req = UNNotificationRequest(identifier: id, content: content(body), trigger: nil)
            center.add(req) { err in DispatchQueue.main.async { reply(err == nil, nil) } }
        case "schedule":
            let prefix = body["prefix"] as? String ?? ""
            let items = body["items"] as? [[String: Any]] ?? []
            removePending(prefix: prefix) { [self] in
                let now = Date().timeIntervalSince1970
                var added = 0
                for it in items.prefix(60) {
                    guard let id = it["id"] as? String, id.hasPrefix(prefix) else { continue }
                    let at = (it["at"] as? Double) ?? Double(it["at"] as? Int ?? 0)
                    guard at > now + 5 else { continue }
                    let date = Date(timeIntervalSince1970: at)
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: id, content: content(it), trigger: trig))
                    added += 1
                }
                DispatchQueue.main.async { reply(added, nil) }
            }
        case "cancel":
            removePending(prefix: body["prefix"] as? String ?? "") { DispatchQueue.main.async { reply(true, nil) } }
        default:
            reply(nil, "unknown action")
        }
    }

    private func content(_ d: [String: Any]) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = String((d["title"] as? String ?? ShellConfig.name).prefix(120))
        c.body = String((d["body"] as? String ?? "").prefix(400))
        c.sound = .default
        if let s = d["section"] as? String { c.userInfo = ["section": s] }
        return c
    }

    private func removePending(prefix: String, then: @escaping () -> Void) {
        guard !prefix.isEmpty else { then(); return }
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
            then()
        }
    }

    /// Tapping a notification opens the section it names (same path as Siri / Shortcuts).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["section"] as? String {
            DispatchQueue.main.async { ShellLink.queue(section: s) }
        }
        completionHandler()
    }
}

extension Bridge {
    func handleNotify(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        if body["op"] as? String == "widget" {
            ShellNotify.saveWidget(json: body["json"] as? String ?? "{}")
            reply(true, nil)
        } else {
            ShellNotify.shared.handle(body, reply: reply)
        }
    }
}
