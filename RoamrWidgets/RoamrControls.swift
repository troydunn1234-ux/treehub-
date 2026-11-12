import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button controls (iOS 18+).
// The intents come from TrackApp/App/RoamrActions.swift, which is compiled into this extension and the app,
// so tapping a control opens Roamr and the app starts recording.

@available(iOS 18.0, *)
struct StartTrackingControl: ControlWidget {
    static let kind = "com.troydunn.roamr.control.walk"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRoamrTrackingIntent(kind: .walk)) {
                Label("Start Walk", systemImage: "figure.walk")
            }
        }
        .displayName("Start a Walk")
        .description("Opens Roamr and starts recording a walk.")
    }
}

@available(iOS 18.0, *)
struct StartDriveControl: ControlWidget {
    static let kind = "com.troydunn.roamr.control.drive"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRoamrTrackingIntent(kind: .drive)) {
                Label("Start Drive", systemImage: "car.fill")
            }
        }
        .displayName("Start a Drive")
        .description("Opens Roamr and starts recording a drive.")
    }
}
