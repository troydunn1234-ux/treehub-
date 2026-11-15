import SwiftUI
import WidgetKit

// Rootbound's Control Center / Lock Screen controls (RootboundControls.swift). Walks are recorded in Roamr now,
// so there is no stroll Live Activity or "Start Stroll" control any more.

@main
struct RootboundWidgets: WidgetBundle {
    var body: some Widget {
        if #available(iOS 18.0, *) {
            LogTreeHugControl()
        }
    }
}
