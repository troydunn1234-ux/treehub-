import AppIntents
import Foundation

// Rootbound actions Siri, Shortcuts and Control Center can ask for.
// Compiled into BOTH the app and RootboundWidgets (see project.yml), so it may only use Foundation / AppIntents.
// The intents open the app (openAppWhenRun), so perform() runs in the app's process: it leaves the
// action in UserDefaults and RootView (TreeHubApp.swift) acts on it as soon as it is on screen.

enum RootboundAction: String {
    case logHug, stroll, hike, home, grove, collection
}

enum RootboundPending {
    static let key = "rb.pendingAction"
    static let atKey = "rb.pendingActionAt"
    static let note = Notification.Name("rb.pendingAction")

    static func queue(_ action: RootboundAction) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting action, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> RootboundAction? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let at = d.double(forKey: atKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return RootboundAction(rawValue: raw)
    }
}

// MARK: - Intents

struct LogTreeHugIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Tree Hug"
    static var description = IntentDescription("Opens Rootbound straight to the tree hug logger.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RootboundPending.queue(.logHug)
        return .result()
    }
}

enum StrollKindOption: String, AppEnum {
    case stroll, hike

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Outing"
    static var caseDisplayRepresentations: [StrollKindOption: DisplayRepresentation] = [
        .stroll: DisplayRepresentation(title: "Stroll", image: .init(systemName: "figure.walk")),
        .hike: DisplayRepresentation(title: "Hike", image: .init(systemName: "figure.hiking")),
    ]
}

struct StartStrollIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Stroll"
    static var description = IntentDescription("Opens Rootbound and starts recording a stroll or a hike.")
    static var openAppWhenRun = true

    @Parameter(title: "Outing", default: .stroll)
    var kind: StrollKindOption

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$kind)") }

    init() {}
    init(kind: StrollKindOption) { self.kind = kind }

    @MainActor
    func perform() async throws -> some IntentResult {
        RootboundPending.queue(kind == .hike ? .hike : .stroll)
        return .result()
    }
}

enum RootboundSectionOption: String, AppEnum {
    case home, grove, collection

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [RootboundSectionOption: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house.fill")),
        .grove: DisplayRepresentation(title: "Grove", image: .init(systemName: "tree.fill")),
        .collection: DisplayRepresentation(title: "Collection", image: .init(systemName: "sparkles")),
    ]
}

struct OpenRootboundSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Rootbound Section"
    static var description = IntentDescription("Opens Rootbound to your home, your grove of trees or your collection.")
    static var openAppWhenRun = true

    @Parameter(title: "Section", default: .grove)
    var section: RootboundSectionOption

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$section)") }

    init() {}
    init(section: RootboundSectionOption) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch section {
        case .home: RootboundPending.queue(.home)
        case .grove: RootboundPending.queue(.grove)
        case .collection: RootboundPending.queue(.collection)
        }
        return .result()
    }
}
