import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button controls (iOS 18+).
// The intents come from TreeHub/App/RootboundActions.swift, which is compiled into this extension and the app,
// so tapping a control opens Rootbound and the app carries out the action.

@available(iOS 18.0, *)
struct LogTreeHugControl: ControlWidget {
    static let kind = "com.troydunn.rootbound.control.loghug"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogTreeHugIntent()) {
                Label("Log Tree Hug", systemImage: "heart.fill")
            }
        }
        .displayName("Log a Tree Hug")
        .description("Opens Rootbound straight to the tree hug logger.")
    }
}

@available(iOS 18.0, *)
struct StartStrollControl: ControlWidget {
    static let kind = "com.troydunn.rootbound.control.stroll"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartStrollIntent(kind: .stroll)) {
                Label("Start Stroll", systemImage: "figure.walk")
            }
        }
        .displayName("Start a Stroll")
        .description("Opens Rootbound and starts recording a stroll.")
    }
}
