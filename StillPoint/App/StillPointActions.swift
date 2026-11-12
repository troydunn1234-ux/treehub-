import AppIntents
import Foundation

// Still Point's Control Center action. Compiled into BOTH the app and the iOS StillPointWidgets extension
// (see project.yml; not the watch widgets), so it may only use Foundation / AppIntents.
// It opens the app (openAppWhenRun), so perform() runs in the app's process and hands the practice to the
// same queue Siri uses (Router.queue in StillPointApp.swift; keys mirrored here because Router is app-only).

struct BreatheNowControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Breathe Now"
    static var description = IntentDescription("Opens Still Point and begins today's suggested practice.")
    static var openAppWhenRun = true
    /// Shortcuts already offers StartBreathingIntent; this one is for the control only.
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        // The practice the app last suggested (WidgetBridge.publish), else the quick resonance breath.
        let suggested = UserDefaults(suiteName: "group.com.troydunn.stillpoint")?.string(forKey: "suggestedId") ?? ""
        let id = suggested.isEmpty ? "resonance" : suggested
        UserDefaults.standard.set(id, forKey: "sp.pendingPractice")                         // Router.pendingKey
        NotificationCenter.default.post(name: Notification.Name("sp.pendingPractice"), object: nil) // Router.pendingNote
        return .result()
    }
}
