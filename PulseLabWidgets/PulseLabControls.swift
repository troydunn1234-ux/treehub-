import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button control (iOS 18+).
// OpenLabSectionIntent comes from PulseLab/App/PulseLabActions.swift, which is compiled into this extension
// and the app, so tapping the control opens Pulse Lab on Today.

@available(iOS 18.0, *)
struct PulseLabTodayControl: ControlWidget {
    static let kind = "com.troydunn.pulselab.control.today"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenLabSectionIntent(section: .today)) {
                Label("Today's Scores", systemImage: "waveform.path.ecg")
            }
        }
        .displayName("Today's Scores")
        .description("Opens Pulse Lab to today's Watch vs WHOOP scores.")
    }
}
