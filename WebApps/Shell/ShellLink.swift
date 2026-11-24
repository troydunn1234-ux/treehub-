import Foundation

/// Siri / Shortcuts ask the bundled web app to open one of its sections (each app's Native/*Intents.swift).
/// The section waits in UserDefaults; the web view hands it to the page once it has loaded, or straight away
/// when the app is already open, by calling `window.__shellOpen(section)` (defined by each index.html).
/// A link that carries data for the page (ridequest://import?d=…) also keeps its query, and the page gets
/// `window.__shellOpen(section, query)`; section-only links are handed over exactly as before.
enum ShellLink {
    static let key = "shell.pendingSection"
    static let atKey = "shell.pendingSectionAt"
    static let queryKey = "shell.pendingQuery"
    static let note = Notification.Name("shell.pendingSection")

    static func queue(section: String, query: String? = nil) {
        let d = UserDefaults.standard
        d.set(section, forKey: key)
        if let q = query, !q.isEmpty { d.set(q, forKey: queryKey) } else { d.removeObject(forKey: queryKey) }
        d.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting section, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> String? { takeLink()?.section }

    /// The waiting section and its query (nil for a plain section link), once; same two-minute rule.
    static func takeLink() -> (section: String, query: String?)? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key), !raw.isEmpty else { return nil }
        let at = d.double(forKey: atKey)
        let query = d.string(forKey: queryKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        d.removeObject(forKey: queryKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return (raw, query)
    }
}
