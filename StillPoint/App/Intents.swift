import AppIntents
import Foundation

// MARK: - Practice as an App Entity (so Siri and Shortcuts can pick one)

struct PracticeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Practice"
    static var defaultQuery = PracticeQuery()

    var id: String
    var title: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    init(_ p: Practice, library lib: PracticeLibrary = .shared) {
        id = p.id
        title = p.title
        let t = lib.tradition(p.traditionId)?.name ?? (p.isMovement ? "Warm-up" : "Practice")
        subtitle = lib.isLocked(p) ? "\(t) · Pro" : t
    }
}

struct PracticeQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PracticeEntity] {
        let lib = PracticeLibrary.shared
        return identifiers.compactMap { lib.practice($0) }.map { PracticeEntity($0, library: lib) }
    }

    /// Open (unlocked) practices first, then the rest, so Siri's suggestions are ones that just work.
    func suggestedEntities() async throws -> [PracticeEntity] {
        let lib = PracticeLibrary.shared
        let open = lib.practices.filter { !lib.isLocked($0) }
        let locked = lib.practices.filter { lib.isLocked($0) }
        return (open + locked).map { PracticeEntity($0, library: lib) }
    }

    func entities(matching string: String) async throws -> [PracticeEntity] {
        let lib = PracticeLibrary.shared
        let q = string.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return try await suggestedEntities() }
        return lib.practices.filter { p in
            p.title.lowercased().contains(q) || p.id.contains(q)
                || (lib.tradition(p.traditionId)?.name.lowercased().contains(q) ?? false)
        }.map { PracticeEntity($0, library: lib) }
    }
}

// MARK: - Intents

/// "Start <practice>": opens Still Point and begins the practice at the usual length.
/// Locked practices open their page instead, where the unlock lives.
struct StartPracticeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Practice"
    static var description = IntentDescription("Opens Still Point and begins the practice you choose.")
    static var openAppWhenRun = true

    @Parameter(title: "Practice")
    var practice: PracticeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$practice)")
    }

    init() {}
    init(practice: PracticeEntity) { self.practice = practice }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.queue(practiceId: practice.id)
        return .result()
    }
}

/// "Start Still Point breathing": no questions asked, the best quick breath for right now.
struct StartBreathingIntent: AppIntent {
    static var title: LocalizedStringResource = "Breathe Now"
    static var description = IntentDescription("Opens Still Point and begins a short breathing practice suited to the time of day.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let lib = PracticeLibrary.shared
        var p = WidgetBridge.suggestedPractice(library: lib)
        if lib.isLocked(p) || !p.isBreathwork { p = lib.quickPractice }
        Router.queue(practiceId: p.id)
        return .result()
    }
}

// MARK: - Sauna / steam

enum HeatRoomEntity: String, AppEnum {
    case sauna, steam
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Heat room"
    static var caseDisplayRepresentations: [HeatRoomEntity: DisplayRepresentation] = [
        .sauna: "Sauna",
        .steam: "Steam room",
    ]
    var kind: HeatKind { self == .sauna ? .sauna : .steam }
}

/// "Start sauna in Still Point": starts the timer without opening the app (handy with wet hands).
struct StartHeatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sauna or Steam"
    static var description = IntentDescription("Starts timing a sauna or steam-room session. Heart rate for that time is pulled from Apple Health when you finish.")
    static var openAppWhenRun = false

    @Parameter(title: "Room", default: .sauna)
    var room: HeatRoomEntity

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$room) timer") }

    init() {}
    init(room: HeatRoomEntity) { self.room = room }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        HeatStore.shared.start(room.kind)
        return .result(dialog: "\(room.kind.title) timer started. Enjoy the heat.")
    }
}

/// "I'm out of the sauna": ends the running heat session.
struct EndHeatIntent: AppIntent {
    static var title: LocalizedStringResource = "End Sauna or Steam"
    static var description = IntentDescription("Stops the running sauna or steam-room timer and saves it to your heat log.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = HeatStore.shared.active else {
            return .result(dialog: "There's no sauna or steam session running.")
        }
        let mins = Int(s.minutes.rounded())
        HeatStore.shared.finish()
        return .result(dialog: "Saved \(mins) minutes in the \(s.kind.short.lowercased()). Cool down and drink some water.")
    }
}

/// Phrases Siri understands out of the box.
struct StillPointShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBreathingIntent(),
            phrases: [
                "Start \(.applicationName) breathing",
                "Breathe with \(.applicationName)",
                "Start a \(.applicationName) session",
                "Open \(.applicationName) and breathe",
            ],
            shortTitle: "Breathe now",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: StartPracticeIntent(),
            phrases: [
                "Start \(\.$practice) in \(.applicationName)",
                "Start \(\.$practice) with \(.applicationName)",
                "Begin \(\.$practice) in \(.applicationName)",
                "Start a practice in \(.applicationName)",
            ],
            shortTitle: "Start a practice",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: StartHeatIntent(),
            phrases: [
                "Start \(\.$room) in \(.applicationName)",
                "Start the \(\.$room) timer in \(.applicationName)",
                "I'm in the \(\.$room) \(.applicationName)",
            ],
            shortTitle: "Start sauna / steam",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: EndHeatIntent(),
            phrases: [
                "End heat session in \(.applicationName)",
                "I'm out of the sauna \(.applicationName)",
                "Stop the sauna timer in \(.applicationName)",
            ],
            shortTitle: "End sauna / steam",
            systemImageName: "checkmark.circle"
        )
    }
}
