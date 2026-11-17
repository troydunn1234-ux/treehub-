import Foundation
import SwiftData
import UIKit

/// App-wide handles for code that runs outside the SwiftUI tree (CarPlay scene, Siri "Stop Roamr",
/// the hard-stop alert). Set once in TrackHubApp.init.
@MainActor
enum RoamrContext {
    static weak var tracker: RouteTracker?
    static var container: ModelContainer?

    /// Same as tapping Finish in the app: save the activity, tell listeners, fill in place names.
    /// `auto`: finished on its own after you stopped moving (trims the idle tail, sends "Drive finished").
    @discardableResult
    static func finishAndSave(auto: Bool = false) -> Activity? {
        guard let tracker, tracker.isActive, let container else { return nil }
        let suggestion = tracker.suggestedKind
        let originalKind = tracker.kind
        guard let a = tracker.finish(auto: auto) else { return nil }
        if suggestion != originalKind && (suggestion == .drive || originalKind == .drive)
            && ActivityKind.available.contains(suggestion) { a.kind = suggestion }
        let context = container.mainContext
        context.insert(a)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(name: .activitySaved, object: nil, userInfo: [
            "id": a.id.uuidString, "auto": auto, "kind": a.kind.rawValue,
            "distanceM": a.distanceM, "seconds": a.elapsedSec,
        ])
        let pts = a.route
        Task {
            if let s = pts.first { a.startPlace = await Geo.placeName(for: s.coordinate) }
            if let e = pts.last { a.endPlace = await Geo.placeName(for: e.coordinate) }
            try? context.save()
        }
        return a
    }

    /// Starts a recording if nothing is running and location is allowed. Returns false if it couldn't.
    @discardableResult
    static func start(_ kind: ActivityKind) -> Bool {
        guard let tracker else { return false }
        guard !tracker.isActive else { return true }
        guard tracker.canTrack else { tracker.requestPermission(); return false }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        tracker.start(kind: kind)
        return true
    }
}
