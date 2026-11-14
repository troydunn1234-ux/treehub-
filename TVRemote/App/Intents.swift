import AppIntents
import Foundation

// Siri and Shortcuts for Couch Remote. These run inside the app's process (the app is launched in
// the background if needed), so they go straight through the shared TVStore / SceneStore.

// MARK: - TV power

struct TurnTVOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn TV On"
    static var description = IntentDescription("Turns on the TV Couch Remote is paired with.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        store.press(.powerOn)
        return .result(dialog: "Turning on \(store.tv?.name ?? "the TV").")
    }
}

struct TurnTVOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn TV Off"
    static var description = IntentDescription("Turns off the TV Couch Remote is paired with.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        store.press(.powerOff)
        return .result(dialog: "Turning off \(store.tv?.name ?? "the TV").")
    }
}

// MARK: - Volume

enum VolumeAction: String, AppEnum {
    case up, down, mute

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Volume"
    static var caseDisplayRepresentations: [VolumeAction: DisplayRepresentation] = [
        .up: "Up", .down: "Down", .mute: "Mute",
    ]
}

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Change TV Volume"
    static var description = IntentDescription("Turns the TV volume up or down, or mutes it.")

    @Parameter(title: "Action", default: .up)
    var action: VolumeAction

    @Parameter(title: "Presses", default: 3)
    var presses: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Volume \(\.$action) \(\.$presses) times")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        switch action {
        case .mute:
            store.press(.muteToggle)
            return .result(dialog: "Muted.")
        case .up, .down:
            let key: RemoteKey = action == .up ? .volumeUp : .volumeDown
            for i in 0..<max(1, min(presses, 20)) {
                if i > 0 { try? await Task.sleep(nanoseconds: 180_000_000) }
                store.press(key)
            }
            return .result(dialog: action == .up ? "Volume up." : "Volume down.")
        }
    }
}

/// "Mute the TV with Couch Remote": its own intent, so Siri never reads it as volume up.
struct MuteTVIntent: AppIntent {
    static var title: LocalizedStringResource = "Mute TV"
    static var description = IntentDescription("Mutes or unmutes the TV Couch Remote is paired with.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        store.press(.muteToggle)
        try? await Task.sleep(nanoseconds: 400_000_000)
        return .result(dialog: "Toggled mute on \(store.tv?.name ?? "the TV").")
    }
}

/// Volume levels Siri can say ("Set TV volume to 20 with Couch Remote"). App Shortcut phrases can only
/// fill in a list of choices, not any number, so the levels go in steps of 5.
enum TVVolumeLevel: String, AppEnum {
    case v0 = "0", v5 = "5", v10 = "10", v15 = "15", v20 = "20", v25 = "25", v30 = "30", v35 = "35", v40 = "40"
    case v45 = "45", v50 = "50", v55 = "55", v60 = "60", v65 = "65", v70 = "70", v75 = "75", v80 = "80"
    case v85 = "85", v90 = "90", v95 = "95", v100 = "100"

    var level: Int { Int(rawValue) ?? 0 }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Volume level"
    static var caseDisplayRepresentations: [TVVolumeLevel: DisplayRepresentation] = [
        .v0: DisplayRepresentation(title: "0", synonyms: ["zero"]),
        .v5: DisplayRepresentation(title: "5", synonyms: ["five"]),
        .v10: DisplayRepresentation(title: "10", synonyms: ["ten"]),
        .v15: DisplayRepresentation(title: "15", synonyms: ["fifteen"]),
        .v20: DisplayRepresentation(title: "20", synonyms: ["twenty"]),
        .v25: DisplayRepresentation(title: "25", synonyms: ["twenty five"]),
        .v30: DisplayRepresentation(title: "30", synonyms: ["thirty"]),
        .v35: DisplayRepresentation(title: "35", synonyms: ["thirty five"]),
        .v40: DisplayRepresentation(title: "40", synonyms: ["forty"]),
        .v45: DisplayRepresentation(title: "45", synonyms: ["forty five"]),
        .v50: DisplayRepresentation(title: "50", synonyms: ["fifty"]),
        .v55: DisplayRepresentation(title: "55", synonyms: ["fifty five"]),
        .v60: DisplayRepresentation(title: "60", synonyms: ["sixty"]),
        .v65: DisplayRepresentation(title: "65", synonyms: ["sixty five"]),
        .v70: DisplayRepresentation(title: "70", synonyms: ["seventy"]),
        .v75: DisplayRepresentation(title: "75", synonyms: ["seventy five"]),
        .v80: DisplayRepresentation(title: "80", synonyms: ["eighty"]),
        .v85: DisplayRepresentation(title: "85", synonyms: ["eighty five"]),
        .v90: DisplayRepresentation(title: "90", synonyms: ["ninety"]),
        .v95: DisplayRepresentation(title: "95", synonyms: ["ninety five"]),
        .v100: DisplayRepresentation(title: "100", synonyms: ["a hundred", "one hundred", "max"]),
    ]
}

struct SetTVVolumeLevelIntent: AppIntent {
    static var title: LocalizedStringResource = "Set TV Volume"
    static var description = IntentDescription("Sets the TV volume to a level from 0 to 100. TVs that only take up and down presses get stepped there, so the level is close rather than exact.")

    @Parameter(title: "Level", default: .v20)
    var level: TVVolumeLevel

    static var parameterSummary: some ParameterSummary {
        Summary("Set the TV volume to \(\.$level)")
    }

    init() {}
    init(level: TVVolumeLevel) { self.level = level }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let exact = try await TVStore.shared.setVolume(level: level.level)
        return .result(dialog: exact ? "Volume set to \(level.level)." : "Volume stepped to about \(level.level).")
    }
}

// MARK: - Open an app

struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open App on TV"
    static var description = IntentDescription("Opens a streaming app (like Netflix or YouTube) on your TV.")

    @Parameter(title: "App")
    var appName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$appName) on the TV")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        let name = appName.trimmingCharacters(in: .whitespaces)
        let app = store.catalog.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? StreamingApp(name: name)
        await store.launch(app)
        return .result(dialog: "Opening \(app.name) on \(store.tv?.name ?? "the TV").")
    }
}

/// A streaming app the TV can open, so Siri can fill it in: "Open Netflix on the TV with Couch Remote".
struct TVAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV app"
    static var defaultQuery = TVAppQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    init(name: String) { id = name }
}

struct TVAppQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TVAppEntity] {
        identifiers.map { TVAppEntity(name: $0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TVAppEntity] {
        let q = string.trimmingCharacters(in: .whitespaces)
        let hits = TVStore.shared.catalog.filter { $0.name.localizedCaseInsensitiveContains(q) }.map { TVAppEntity(name: $0.name) }
        return hits.isEmpty && !q.isEmpty ? [TVAppEntity(name: q)] : hits
    }

    /// Favorites first, then the rest of the catalog.
    @MainActor
    func suggestedEntities() async throws -> [TVAppEntity] {
        let store = TVStore.shared
        let favs = store.favoriteApps.map(\.name)
        let rest = store.catalog.map(\.name).filter { !favs.contains($0) }
        return (favs + rest).map { TVAppEntity(name: $0) }
    }
}

struct OpenTVAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open TV App"
    static var description = IntentDescription("Opens a streaming app like Netflix, YouTube or Hulu on your TV.")

    @Parameter(title: "App")
    var app: TVAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) on the TV")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        let a = store.catalog.first { $0.name.caseInsensitiveCompare(app.id) == .orderedSame } ?? StreamingApp(name: app.id)
        await store.launch(a)
        return .result(dialog: "Opening \(a.name) on \(store.tv?.name ?? "the TV").")
    }
}

// MARK: - Sleep timer

enum SleepTimerLength: String, AppEnum {
    case m15, m30, m45, m60, m90, m120, off

    var minutes: Int {
        switch self {
        case .m15: return 15
        case .m30: return 30
        case .m45: return 45
        case .m60: return 60
        case .m90: return 90
        case .m120: return 120
        case .off: return 0
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep timer"
    static var caseDisplayRepresentations: [SleepTimerLength: DisplayRepresentation] = [
        .m15: DisplayRepresentation(title: "15 minutes", synonyms: ["fifteen minutes"]),
        .m30: DisplayRepresentation(title: "30 minutes", synonyms: ["thirty minutes", "half an hour"]),
        .m45: DisplayRepresentation(title: "45 minutes", synonyms: ["forty five minutes"]),
        .m60: DisplayRepresentation(title: "1 hour", synonyms: ["one hour", "an hour", "60 minutes"]),
        .m90: DisplayRepresentation(title: "90 minutes", synonyms: ["an hour and a half", "ninety minutes"]),
        .m120: DisplayRepresentation(title: "2 hours", synonyms: ["two hours"]),
        .off: DisplayRepresentation(title: "Off", synonyms: ["cancel", "nothing"]),
    ]
}

struct StartSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "TV Sleep Timer"
    static var description = IntentDescription("Turns the TV off after a while. Your phone needs to be on the same Wi-Fi as the TV; if iOS pauses the app, a notification lets you turn the TV off with one tap.")

    @Parameter(title: "Turn off after", default: .m30)
    var length: SleepTimerLength

    static var parameterSummary: some ParameterSummary {
        Summary("Sleep timer: \(\.$length)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let timer = SleepTimer.shared
        if length == .off {
            timer.cancel()
            return .result(dialog: "Sleep timer off.")
        }
        guard TVStore.shared.tv != nil else { throw CouchRemoteIntentError.noTV }
        timer.start(minutes: length.minutes)
        return .result(dialog: "The TV turns off in \(SleepTimer.label(minutes: length.minutes)).")
    }
}

// MARK: - Scenes

struct SceneEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static var defaultQuery = SceneQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(_ scene: RemoteScene) {
        id = scene.id
        name = scene.name
        emoji = scene.emoji
    }
}

struct SceneQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SceneEntity] {
        SceneStore.shared.scenes.filter { identifiers.contains($0.id) }.map(SceneEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SceneEntity] {
        SceneStore.shared.scenes.map(SceneEntity.init)
    }
}

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scene"
    static var description = IntentDescription("Runs one of your Couch Remote scenes (for example Movie night).")

    @Parameter(title: "Scene")
    var scene: SceneEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$scene)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = SceneStore.shared.scenes.first(where: { $0.id == scene.id }) else { throw CouchRemoteIntentError.noScene }
        await SceneStore.shared.run(s)
        return .result(dialog: "Running \(s.name).")
    }
}

// MARK: - PC media

enum PCMediaAction: String, AppEnum {
    case playPause, next, previous, mute

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Media key"
    static var caseDisplayRepresentations: [PCMediaAction: DisplayRepresentation] = [
        .playPause: "Play / Pause", .next: "Next track", .previous: "Previous track", .mute: "Mute",
    ]

    /// What PCClient.media(_:) sends (same values as the buttons in the PC tab).
    var command: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next"
        case .previous: return "prev"
        case .mute: return "mute"
        }
    }
}

/// Media keys on the paired PC, through the same PCClient the PC tab and Scenes use.
struct PCMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "PC Media Control"
    static var description = IntentDescription("Plays or pauses, skips or mutes what's playing on your paired PC.")

    @Parameter(title: "Key", default: .playPause)
    var action: PCMediaAction

    static var parameterSummary: some ParameterSummary {
        Summary("Press \(\.$action) on the PC")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pc = PCClient.shared
        guard pc.isPaired else { throw CouchRemoteIntentError.noPC }
        if pc.state != .connected {
            pc.connect()
            // Give the socket a moment to come up (the send would queue anyway, but this keeps Siri's answer honest).
            for _ in 0..<20 where pc.state != .connected {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        pc.media(action.command)
        // Let the message leave before Siri finishes and the app is suspended.
        try? await Task.sleep(nanoseconds: 250_000_000)
        switch action {
        case .playPause: return .result(dialog: "Done.")
        case .next: return .result(dialog: "Next track.")
        case .previous: return .result(dialog: "Previous track.")
        case .mute: return .result(dialog: "Toggled mute on the PC.")
        }
    }
}

// MARK: - Errors

enum CouchRemoteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noTV, noScene, noPC

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTV: return "Pair a TV in Couch Remote first."
        case .noScene: return "That scene no longer exists."
        case .noPC: return "Pair your PC in Couch Remote's PC tab first."
        }
    }
}

// MARK: - Siri phrases

struct CouchRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnTVOnIntent(),
                    phrases: ["Turn on the TV with \(.applicationName)", "Turn on my TV with \(.applicationName)"],
                    shortTitle: "TV on", systemImageName: "power")
        AppShortcut(intent: TurnTVOffIntent(),
                    phrases: ["Turn off the TV with \(.applicationName)", "Turn off my TV with \(.applicationName)"],
                    shortTitle: "TV off", systemImageName: "power.circle")
        AppShortcut(intent: SetTVVolumeLevelIntent(),
                    phrases: ["Set TV volume to \(\.$level) with \(.applicationName)",
                              "Set the TV volume to \(\.$level) with \(.applicationName)",
                              "Set the TV volume with \(.applicationName)"],
                    shortTitle: "Set volume", systemImageName: "speaker.wave.3.fill")
        AppShortcut(intent: SetVolumeIntent(),
                    phrases: ["Change the TV volume with \(.applicationName)", "Turn the TV volume up with \(.applicationName)"],
                    shortTitle: "Volume", systemImageName: "speaker.wave.2.fill")
        AppShortcut(intent: MuteTVIntent(),
                    phrases: ["Mute the TV with \(.applicationName)", "Unmute the TV with \(.applicationName)",
                              "Mute my TV with \(.applicationName)"],
                    shortTitle: "Mute", systemImageName: "speaker.slash.fill")
        AppShortcut(intent: OpenTVAppIntent(),
                    phrases: ["Open \(\.$app) on the TV with \(.applicationName)", "Put on \(\.$app) with \(.applicationName)",
                              "Open an app on the TV with \(.applicationName)"],
                    shortTitle: "Open app", systemImageName: "play.rectangle.fill")
        AppShortcut(intent: StartSleepTimerIntent(),
                    phrases: ["Set a sleep timer for \(\.$length) with \(.applicationName)",
                              "Start a TV sleep timer with \(.applicationName)",
                              "Turn off the TV in \(\.$length) with \(.applicationName)"],
                    shortTitle: "Sleep timer", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: RunSceneIntent(),
                    phrases: ["Run \(\.$scene) in \(.applicationName)", "Run \(\.$scene) with \(.applicationName)",
                              "Run a scene in \(.applicationName)"],
                    shortTitle: "Run scene", systemImageName: "sparkles")
        AppShortcut(intent: PCMediaIntent(),
                    phrases: ["Play or pause the PC with \(.applicationName)", "Pause my PC with \(.applicationName)",
                              "Press \(\.$action) on the PC with \(.applicationName)"],
                    shortTitle: "PC media", systemImageName: "playpause.fill")
    }
}
