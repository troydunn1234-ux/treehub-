import AppIntents

// Siri phrases for Roamr. The intents themselves live in RoamrActions.swift (shared with the
// widget extension so Control Center can run them too).

struct RoamrShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoamrTrackingIntent(),
            phrases: [
                "Start a \(\.$kind) in \(.applicationName)",
                "Track a \(\.$kind) with \(.applicationName)",
                "Start tracking a \(\.$kind) in \(.applicationName)",
                "Start tracking with \(.applicationName)",
            ],
            shortTitle: "Start tracking",
            systemImageName: "location.north.circle.fill"
        )
        AppShortcut(
            intent: StopRoamrTrackingIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop tracking in \(.applicationName)",
                "Stop my drive in \(.applicationName)",
                "Finish my trip in \(.applicationName)",
            ],
            shortTitle: "Stop & save",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: LogGasIntent(),
            phrases: [
                "Log gas in \(.applicationName)",
                "Log a fill-up in \(.applicationName)",
                "Add gas to \(.applicationName)",
            ],
            shortTitle: "Log gas",
            systemImageName: "fuelpump.fill"
        )
        AppShortcut(
            intent: OpenRoamrSectionIntent(),
            phrases: [
                "Open my \(\.$section) in \(.applicationName)",
                "Show my \(\.$section) in \(.applicationName)",
                "Show my trips in \(.applicationName)",
            ],
            shortTitle: "History & stats",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: StartGroupDriveIntent(),
            phrases: [
                "Start a group drive in \(.applicationName)",
            ],
            shortTitle: "Group drive",
            systemImageName: "person.2.fill"
        )
    }
}
