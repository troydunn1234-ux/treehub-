import AppIntents
import Foundation

// Siri and Shortcuts for Pulse Lab. Opening a section lives in PulseLabActions.swift (shared with the
// widget extension for Control Center); the score check below answers without opening the app.

/// "What are my scores?": reads the numbers the app last handed the widget (WidgetBridge) and says them.
struct CheckLabScoresIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Today's Scores"
    static var description = IntentDescription("Tells you today's Watch readiness and WHOOP recovery, with resting heart rate from each.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let d = UserDefaults(suiteName: WidgetBridge.suite) else {
            return .result(dialog: "Open Pulse Lab once to sync your scores.")
        }
        func value(_ key: String) -> Double? {
            guard d.object(forKey: key) != nil else { return nil }
            let v = d.double(forKey: key)
            return v < 0 ? nil : v
        }
        let readiness = value(WidgetBridge.Key.readiness)
        let recovery = value(WidgetBridge.Key.recovery)
        let rhrWatch = value(WidgetBridge.Key.rhrWatch)
        let rhrWhoop = value(WidgetBridge.Key.rhrWhoop)

        var parts: [String] = []
        if let r = readiness { parts.append("Apple Watch readiness is \(Int(r.rounded()))") }
        if let r = recovery { parts.append("WHOOP recovery is \(Int(r.rounded())) percent") }
        if let w = rhrWatch, let h = rhrWhoop {
            parts.append("resting heart rate is \(Int(w.rounded())) on the Watch and \(Int(h.rounded())) on WHOOP")
        } else if let w = rhrWatch {
            parts.append("resting heart rate is \(Int(w.rounded()))")
        } else if let h = rhrWhoop {
            parts.append("WHOOP resting heart rate is \(Int(h.rounded()))")
        }
        guard !parts.isEmpty else {
            return .result(dialog: "No scores yet today. Open Pulse Lab to sync.")
        }
        var text = parts.joined(separator: ", ") + "."
        text = text.prefix(1).uppercased() + text.dropFirst()
        if let t = value(WidgetBridge.Key.updatedAt), !Calendar.current.isDateInToday(Date(timeIntervalSince1970: t)) {
            text += " These are from your last sync; open Pulse Lab to refresh."
        }
        return .result(dialog: "\(text)")
    }
}

struct PulseLabShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckLabScoresIntent(),
            phrases: [
                "Check my scores in \(.applicationName)",
                "What's my readiness in \(.applicationName)",
                "What's my recovery in \(.applicationName)",
                "How did I recover \(.applicationName)",
            ],
            shortTitle: "Today's scores",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenLabSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show my \(\.$section) in \(.applicationName)",
                "Take me to \(\.$section) in \(.applicationName)",
            ],
            shortTitle: "Open a section",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
