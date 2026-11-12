import AppIntents
import Foundation

// Food Book actions that open the app, for Siri, Shortcuts and Control Center.
// Compiled into BOTH the app and FoodBookWidgets (see project.yml), so it may only use Foundation / AppIntents.
// The intents open the app (openAppWhenRun), so perform() runs in the app's process: it leaves the
// action in UserDefaults and RootTabs (FoodBookApp.swift) acts on it once it is on screen.

enum FoodBookAction: String {
    case snap, stack
}

enum FoodBookPending {
    static let key = "fb.pendingAction"
    static let atKey = "fb.pendingActionAt"
    static let note = Notification.Name("fb.pendingAction")

    static func queue(_ action: FoodBookAction) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting action, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> FoodBookAction? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let at = d.double(forKey: atKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return FoodBookAction(rawValue: raw)
    }
}

struct SnapMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Snap a Meal"
    static var description = IntentDescription("Opens Food Book's camera so you can snap a meal and log its calories and macros.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FoodBookPending.queue(.snap)
        return .result()
    }
}

struct OpenSupplementStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Supplement Stack"
    static var description = IntentDescription("Opens Food Book to today's supplement checklist.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FoodBookPending.queue(.stack)
        return .result()
    }
}
