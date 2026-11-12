import AppIntents
import Foundation
import SwiftData

// Siri and Shortcuts for Food Book. Snap a meal / open the stack live in FoodBookActions.swift (shared with
// the widget extension for Control Center); the quick logs below run without opening the app.

// MARK: - Quick logs (no app needed)

enum QuickDrink {
    case water, coffee

    /// Adds one glass / cup to today's log, saves, and refreshes the widget and Apple Health.
    @MainActor
    static func log(_ drink: QuickDrink) -> DayLog {
        let container = FoodBookApp.sharedContainer
        let ctx = container.mainContext
        let today = Day.key(Date())
        let l = DayLog.fetchOrCreate(today, in: ctx)
        switch drink {
        case .water: l.water += 1
        case .coffee: l.coffees += 1
        }
        l.updatedAt = Date()
        try? ctx.save()
        WidgetBridge.shared.attach(container: container)
        WidgetBridge.shared.writeNow()
        return l
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Glass of Water"
    static var description = IntentDescription("Adds a glass of water (250 ml) to today in Food Book.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let l = QuickDrink.log(.water)
        let day = l.day, ml = l.waterML, mg = l.caffeineMG
        await FoodHealth.shared.syncQuickLog(day: day, waterML: ml, caffeineMG: mg)
        let glasses = l.water
        return .result(dialog: "Logged. That's \(glasses) \(glasses == 1 ? "glass" : "glasses") of water today.")
    }
}

struct LogCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Coffee"
    static var description = IntentDescription("Adds a cup of coffee (about 95 mg caffeine) to today in Food Book.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let l = QuickDrink.log(.coffee)
        let day = l.day, ml = l.waterML, mg = l.caffeineMG
        await FoodHealth.shared.syncQuickLog(day: day, waterML: ml, caffeineMG: mg)
        let cups = l.coffees
        return .result(dialog: "Logged. That's \(cups) \(cups == 1 ? "coffee" : "coffees") today, about \(Int(mg)) mg of caffeine.")
    }
}

// MARK: - Siri phrases

struct FoodBookShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SnapMealIntent(),
            phrases: [
                "Snap a meal in \(.applicationName)",
                "Snap my food with \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log food in \(.applicationName)",
            ],
            shortTitle: "Snap a meal",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)",
                "I drank water \(.applicationName)",
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogCoffeeIntent(),
            phrases: [
                "Log a coffee in \(.applicationName)",
                "Log coffee in \(.applicationName)",
                "I had a coffee \(.applicationName)",
            ],
            shortTitle: "Log coffee",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: OpenSupplementStackIntent(),
            phrases: [
                "Open my supplements in \(.applicationName)",
                "Show my stack in \(.applicationName)",
                "Check off supplements in \(.applicationName)",
            ],
            shortTitle: "Supplement stack",
            systemImageName: "pills.fill"
        )
    }
}
