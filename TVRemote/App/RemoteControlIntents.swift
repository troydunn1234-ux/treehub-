import AppIntents
import Foundation

// One-tap TV keys for Control Center, the Lock Screen and the Action button (TVRemote/Widgets/RemoteControls.swift).
// This file is compiled into the app AND the widget extension. As a LiveActivityIntent, the system runs perform()
// in the app's process (starting it in the background if needed), where the paired TV and its connection live;
// the extension's copy (COUCH_WIDGETS) is only there so the control can name the intent and never does the work.

enum TVControlKey: String, AppEnum {
    case power, volumeUp, volumeDown, mute

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV key"
    static var caseDisplayRepresentations: [TVControlKey: DisplayRepresentation] = [
        .power: "Power", .volumeUp: "Volume up", .volumeDown: "Volume down", .mute: "Mute",
    ]
}

struct TVControlKeyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Press TV Key"
    static var description = IntentDescription("Presses power, volume or mute on the TV Couch Remote is paired with.")
    static var isDiscoverable = false

    @Parameter(title: "Key", default: .power)
    var key: TVControlKey

    init() {}
    init(key: TVControlKey) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if COUCH_WIDGETS
        return .result()
        #else
        let store = TVStore.shared
        guard store.tv != nil else { throw CouchRemoteIntentError.noTV }
        let k: RemoteKey
        switch key {
        case .power: k = .powerToggle
        case .volumeUp: k = .volumeUp
        case .volumeDown: k = .volumeDown
        case .mute: k = .muteToggle
        }
        // Wait for the TV's answer (a cold background launch may still be connecting), not a fixed delay.
        await store.pressAndWait(k)
        return .result()
        #endif
    }
}
