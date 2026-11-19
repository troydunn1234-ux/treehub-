import SwiftUI
import WidgetKit

// Rootbound's Control Center / Lock Screen controls (RootboundControls.swift). Walks are recorded in Roamr now,
// so there is no stroll Live Activity or "Start Stroll" control any more. "Hug a tree" (RootboundHugWidget.swift)
// is the Home Screen / Lock Screen widget.

@main
struct RootboundWidgets: WidgetBundle {
    var body: some Widget {
        RootboundHugWidget()
        if #available(iOS 18.0, *) {
            LogTreeHugControl()
        }
    }
}
