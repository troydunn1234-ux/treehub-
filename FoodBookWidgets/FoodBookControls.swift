import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button control (iOS 18+).
// SnapMealIntent comes from FoodApp/App/FoodBookActions.swift, which is compiled into this extension and the app,
// so tapping the control opens Food Book and the app opens the camera.

@available(iOS 18.0, *)
struct SnapMealControl: ControlWidget {
    static let kind = "com.troydunn.foodbook.control.snap"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: SnapMealIntent()) {
                Label("Snap a Meal", systemImage: "camera.fill")
            }
        }
        .displayName("Snap a Meal")
        .description("Opens Food Book's camera to log a meal.")
    }
}
