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
        if let r = readiness { parts.append("Watch readiness is \(Int(r.rounded()))") }
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

/// "Log WHOOP": opens Pulse Lab straight to the Log WHOOP sheet to type today's numbers.
struct LogWhoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Log WHOOP"
    static var description = IntentDescription("Opens Pulse Lab to type today's WHOOP recovery, strain and sleep by hand.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LogWhoopPending.queue()
        return .result()
    }
}

/// "Today's recovery": says this morning's briefing (recovery, sleep vs the week, HRV vs baseline,
/// yesterday's strain and the takeaway) from what the app last synced. Doesn't open the app.
struct TodaysRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Recovery"
    static var description = IntentDescription("Reads this morning's briefing: recovery, sleep against your week, HRV against your baseline and yesterday's strain.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let d = UserDefaults(suiteName: WidgetBridge.suite),
              let text = d.string(forKey: WidgetBridge.Key.briefingSpoken), !text.isEmpty else {
            let none = String(localized: "No briefing yet. Open Pulse Lab once to sync.")
            return .result(dialog: "\(none)")
        }
        var out = text
        let day = d.double(forKey: WidgetBridge.Key.briefingDay)
        if day > 0, !Calendar.current.isDateInToday(Date(timeIntervalSince1970: day)) {
            out = String(localized: "This is from your last sync, not today: ") + out
        }
        return .result(dialog: "\(out)")
    }
}

/// "Sync Pulse Lab": reads Health (and WHOOP when it's due) in the background, then says the briefing.
struct SyncPulseLabIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Pulse Lab"
    static var description = IntentDescription("Pulls the latest Health and WHOOP numbers into Pulse Lab and its widgets, then reads today's briefing.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LabStore.shared
        await store.refresh(.background)
        let b = store.briefing
        let head = String(localized: "Pulse Lab is synced.")
        let said = b.isEmpty ? head : head + " " + b.spoken
        return .result(dialog: "\(said)")
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
            ],
            shortTitle: "Today's scores",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: TodaysRecoveryIntent(),
            phrases: [
                "Today's recovery in \(.applicationName)",
                "What's my recovery in \(.applicationName)",
                "How did I recover \(.applicationName)",
                "Morning briefing in \(.applicationName)",
            ],
            shortTitle: "Today's recovery",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: SyncPulseLabIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Refresh \(.applicationName)",
            ],
            shortTitle: "Sync",
            systemImageName: "arrow.triangle.2.circlepath"
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
        AppShortcut(
            intent: LogWhoopIntent(),
            phrases: [
                "Log WHOOP in \(.applicationName)",
                "Log my WHOOP in \(.applicationName)",
                "Log today's WHOOP in \(.applicationName)",
            ],
            shortTitle: "Log WHOOP",
            systemImageName: "square.and.pencil"
        )
    }
}
