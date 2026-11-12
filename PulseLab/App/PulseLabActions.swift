import AppIntents
import Foundation

// Pulse Lab actions that open the app, for Siri, Shortcuts and Control Center.
// Compiled into BOTH the app and PulseLabWidgets (see project.yml), so it may only use Foundation / AppIntents.
// The intent opens the app (openAppWhenRun), so perform() runs in the app's process: it leaves the tab
// in UserDefaults and RootView (PulseLabApp.swift) switches to it.

enum PulseLabPending {
    static let key = "pl.pendingTab"
    static let atKey = "pl.pendingTabAt"
    static let note = Notification.Name("pl.pendingTab")

    /// `tab` is a LabTab name (today, sleep, heart, moves, vs).
    static func queue(tab: String) {
        UserDefaults.standard.set(tab, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// The waiting tab name, once. Anything older than two minutes is dropped so a stale request never fires later.
    static func take() -> String? {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: key) else { return nil }
        let at = d.double(forKey: atKey)
        d.removeObject(forKey: key)
        d.removeObject(forKey: atKey)
        guard Date().timeIntervalSince1970 - at < 120 else { return nil }
        return raw
    }
}

enum LabSectionOption: String, AppEnum {
    case today, sleep, heart, moves, vs

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [LabSectionOption: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today", image: .init(systemName: "waveform.path.ecg")),
        .sleep: DisplayRepresentation(title: "Sleep", image: .init(systemName: "moon.zzz.fill")),
        .heart: DisplayRepresentation(title: "Heart", image: .init(systemName: "heart.text.square.fill")),
        .moves: DisplayRepresentation(title: "Moves", image: .init(systemName: "flame.fill")),
        .vs: DisplayRepresentation(title: "Watch vs WHOOP", image: .init(systemName: "bolt.horizontal.fill")),
    ]
}

struct OpenLabSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pulse Lab Section"
    static var description = IntentDescription("Opens Pulse Lab to Today, Sleep, Heart, Moves or the Watch vs WHOOP comparison.")
    static var openAppWhenRun = true

    @Parameter(title: "Section", default: .today)
    var section: LabSectionOption

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$section)") }

    init() {}
    init(section: LabSectionOption) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        PulseLabPending.queue(tab: section.rawValue)
        return .result()
    }
}
