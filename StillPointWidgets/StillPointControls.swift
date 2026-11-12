#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button control (iOS 18+; iPhone only, the watch widgets skip this file's body).
// BreatheNowControlIntent comes from StillPoint/App/StillPointActions.swift, which is compiled into the iOS
// extension and the app, so tapping the control opens Still Point and starts the practice.

@available(iOS 18.0, *)
struct BreatheNowControl: ControlWidget {
    static let kind = "com.troydunn.stillpoint.control.breathe"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: BreatheNowControlIntent()) {
                Label("Breathe", systemImage: "wind")
            }
        }
        .displayName("Breathe Now")
        .description("Opens Still Point and begins today's suggested practice.")
    }
}
#endif
