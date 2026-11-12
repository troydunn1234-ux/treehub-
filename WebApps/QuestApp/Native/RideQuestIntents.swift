import AppIntents
import Foundation

// Siri and Shortcuts for Ride Quest. Each intent opens the app and asks the page to switch tabs
// (ShellLink -> window.__shellOpen -> setTab in web/index.html).

enum QuestTabOption: String, AppEnum {
    case budgets, review, subs, arcade, log, transfers = "moves"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tab"
    static var caseDisplayRepresentations: [QuestTabOption: DisplayRepresentation] = [
        .budgets: DisplayRepresentation(title: "Budgets", image: .init(systemName: "chart.pie.fill")),
        .review: DisplayRepresentation(title: "Review", image: .init(systemName: "checklist")),
        .subs: DisplayRepresentation(title: "Subscriptions", image: .init(systemName: "repeat")),
        .arcade: DisplayRepresentation(title: "Arcade", image: .init(systemName: "gamecontroller.fill")),
        .log: DisplayRepresentation(title: "Money log", image: .init(systemName: "list.bullet.rectangle")),
        .transfers: DisplayRepresentation(title: "Transfers", image: .init(systemName: "arrow.left.arrow.right")),
    ]
}

struct OpenQuestTabIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Ride Quest Tab"
    static var description = IntentDescription("Opens Ride Quest to your budgets, review, subscriptions, arcade, money log or transfers.")
    static var openAppWhenRun = true

    @Parameter(title: "Tab", default: .budgets)
    var tab: QuestTabOption

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$tab)") }

    init() {}
    init(tab: QuestTabOption) { self.tab = tab }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: tab.rawValue)
        return .result()
    }
}

struct LogSpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Spending"
    static var description = IntentDescription("Opens Ride Quest's money log so you can add what you spent.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: QuestTabOption.log.rawValue)
        return .result()
    }
}

struct CheckSubscriptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Subscriptions"
    static var description = IntentDescription("Opens Ride Quest to your subscriptions and bills.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: QuestTabOption.subs.rawValue)
        return .result()
    }
}

struct RideQuestShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lime

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSpendingIntent(),
            phrases: [
                "Log spending in \(.applicationName)",
                "Log a purchase in \(.applicationName)",
                "Add an expense to \(.applicationName)",
            ],
            shortTitle: "Log spending",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: CheckSubscriptionsIntent(),
            phrases: [
                "Check my subscriptions in \(.applicationName)",
                "Show my subs in \(.applicationName)",
                "Show my bills in \(.applicationName)",
            ],
            shortTitle: "Subscriptions",
            systemImageName: "repeat"
        )
        AppShortcut(
            intent: OpenQuestTabIntent(),
            phrases: [
                "Open \(\.$tab) in \(.applicationName)",
                "Show my \(\.$tab) in \(.applicationName)",
                "Check my budgets in \(.applicationName)",
            ],
            shortTitle: "Open a tab",
            systemImageName: "flag.checkered"
        )
    }
}
