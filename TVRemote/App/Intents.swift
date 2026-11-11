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

// MARK: - Errors

enum CouchRemoteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noTV, noScene

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTV: return "Pair a TV in Couch Remote first."
        case .noScene: return "That scene no longer exists."
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
        AppShortcut(intent: SetVolumeIntent(),
                    phrases: ["Change the TV volume with \(.applicationName)", "Mute the TV with \(.applicationName)"],
                    shortTitle: "Volume", systemImageName: "speaker.wave.2.fill")
        AppShortcut(intent: OpenAppIntent(),
                    phrases: ["Open an app on the TV with \(.applicationName)"],
                    shortTitle: "Open app", systemImageName: "play.rectangle.fill")
        AppShortcut(intent: RunSceneIntent(),
                    phrases: ["Run \(\.$scene) in \(.applicationName)", "Run \(\.$scene) with \(.applicationName)",
                              "Run a scene in \(.applicationName)"],
                    shortTitle: "Run scene", systemImageName: "sparkles")
    }
}
