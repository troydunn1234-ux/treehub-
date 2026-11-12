import Foundation

/// Siri / Shortcuts ask the bundled web app to open one of its sections (each app's Native/*Intents.swift).
/// The section waits in UserDefaults; the web view hands it to the page once it has loaded, or straight away
/// when the app is already open, by calling `window.__shellOpen(section)` (defined by each index.html).
enum ShellLink {
    static let key = "shell.pendingSection"
    static let atKey = "shell.pendingSectionAt"
    static let note = Notification.Name("shell.pendingSection")

    static func queue(section: String) {
        UserDefaults.standard.set(section, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting section, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> String? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key), !raw.isEmpty else { return nil }
        let at = d.double(forKey: atKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return raw
    }
}
