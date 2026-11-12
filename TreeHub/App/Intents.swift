import AppIntents

// Siri phrases for Rootbound. The intents themselves live in RootboundActions.swift (shared with the
// widget extension so Control Center can run them too).

struct RootboundShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lime

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTreeHugIntent(),
            phrases: [
                "Log a tree hug in \(.applicationName)",
                "Log a hug in \(.applicationName)",
                "I hugged a tree \(.applicationName)",
                "Hug a tree with \(.applicationName)",
            ],
            shortTitle: "Log a tree hug",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: StartStrollIntent(),
            phrases: [
                "Start a \(\.$kind) in \(.applicationName)",
                "Start a \(\.$kind) with \(.applicationName)",
                "Go for a \(\.$kind) with \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Start a stroll",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: OpenRootboundSectionIntent(),
            phrases: [
                "Open my \(\.$section) in \(.applicationName)",
                "Show my \(\.$section) in \(.applicationName)",
                "Show my trees in \(.applicationName)",
            ],
            shortTitle: "Open grove",
            systemImageName: "tree.fill"
        )
    }
}
