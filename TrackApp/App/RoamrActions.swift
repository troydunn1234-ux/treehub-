import AppIntents
import Foundation

// Roamr actions Siri, Shortcuts and Control Center can ask for.
// Compiled into BOTH the app and RoamrWidgets (see project.yml), so it may only use Foundation / AppIntents.
// The intents open the app (openAppWhenRun), so perform() runs in the app's process: it leaves the
// action in UserDefaults and TrackRootView (TrackHubApp.swift) acts on it as soon as it is on screen.

enum RoamrAction: String {
    case walk, run, hike, ride, drive, history, stats
}

enum RoamrPending {
    static let key = "roamr.pendingAction"
    static let atKey = "roamr.pendingActionAt"
    static let note = Notification.Name("roamr.pendingAction")

    static func queue(_ action: RoamrAction) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting action, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> RoamrAction? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let at = d.double(forKey: atKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return RoamrAction(rawValue: raw)
    }
}

// MARK: - Intents

enum RoamrKindOption: String, AppEnum {
    case walk, run, hike, ride, drive

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Activity"
    static var caseDisplayRepresentations: [RoamrKindOption: DisplayRepresentation] = [
        .walk: DisplayRepresentation(title: "Walk", image: .init(systemName: "figure.walk")),
        .run: DisplayRepresentation(title: "Run", image: .init(systemName: "figure.run")),
        .hike: DisplayRepresentation(title: "Hike", image: .init(systemName: "figure.hiking")),
        .ride: DisplayRepresentation(title: "Ride", image: .init(systemName: "bicycle")),
        .drive: DisplayRepresentation(title: "Drive", image: .init(systemName: "car.fill")),
    ]

    var action: RoamrAction {
        switch self {
        case .walk: return .walk
        case .run: return .run
        case .hike: return .hike
        case .ride: return .ride
        case .drive: return .drive
        }
    }
}

struct StartRoamrTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Tracking"
    static var description = IntentDescription("Opens Roamr and starts recording a walk, run, hike, ride or drive.")
    static var openAppWhenRun = true

    @Parameter(title: "Activity", default: .walk)
    var kind: RoamrKindOption

    static var parameterSummary: some ParameterSummary { Summary("Start tracking a \(\.$kind)") }

    init() {}
    init(kind: RoamrKindOption) { self.kind = kind }

    @MainActor
    func perform() async throws -> some IntentResult {
        RoamrPending.queue(kind.action)
        return .result()
    }
}

enum RoamrSectionOption: String, AppEnum {
    case history, stats

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [RoamrSectionOption: DisplayRepresentation] = [
        .history: DisplayRepresentation(title: "History", image: .init(systemName: "clock.arrow.circlepath")),
        .stats: DisplayRepresentation(title: "Stats", image: .init(systemName: "chart.bar.fill")),
    ]
}

struct OpenRoamrSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Roamr Section"
    static var description = IntentDescription("Opens Roamr to your trip history or your stats.")
    static var openAppWhenRun = true

    @Parameter(title: "Section", default: .history)
    var section: RoamrSectionOption

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$section)") }

    init() {}
    init(section: RoamrSectionOption) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        RoamrPending.queue(section == .stats ? .stats : .history)
        return .result()
    }
}
