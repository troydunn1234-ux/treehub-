import Foundation
import SwiftData

/// Roamr -> Rootbound: publishes the last 60 days of trips into the shared App Group feed
/// (Shared/Wellness/WellnessBridge.swift, roamr.json) so Rootbound can show a walk under a tree hug.
/// Only summary numbers plus a start / end point rounded to ~100 m; never the route. Read-only for Rootbound.
@MainActor
enum RoamrWellness {
    private static var lastPublish = Date.distantPast

    static func publish(_ context: ModelContext, force: Bool = false) {
        if TrackDemo.isOn { return }
        if !force, Date().timeIntervalSince(lastPublish) < 20 { return }
        lastPublish = Date()
        let since = Date().addingTimeInterval(-Double(WellnessBridge.roamrKeepDays) * 86400)
        var fd = FetchDescriptor<Activity>(predicate: #Predicate { $0.start >= since },
                                           sortBy: [SortDescriptor(\.start, order: .reverse)])
        fd.fetchLimit = WellnessBridge.maxItems
        guard let list = try? context.fetch(fd) else { return }
        let trips = list.map { a -> WellnessBridge.Trip in
            let secs = max(1, a.movingSec > 0 ? a.movingSec : a.end.timeIntervalSince(a.start))
            var t = WellnessBridge.Trip(id: a.id, kind: a.kind.rawValue, start: a.start, end: a.end,
                                        distanceM: a.distanceM, movingSec: a.movingSec, elevGainM: a.elevGainM,
                                        avgSpeed: a.distanceM / secs, topSpeed: a.maxSpeed, avgHR: a.avgHR)
            // Coarse ends for walks, runs, hikes and rides only (drives don't need them).
            if a.kind != .drive {
                let pts = a.route
                if let f = pts.first { t.startLat = WellnessBridge.coarse(f.lat); t.startLng = WellnessBridge.coarse(f.lng) }
                if let l = pts.last { t.endLat = WellnessBridge.coarse(l.lat); t.endLng = WellnessBridge.coarse(l.lng) }
            }
            return t
        }
        WellnessBridge.publishRoamr(trips: trips)
    }

    /// roamr://trip?id=<uuid> (Rootbound "Open in Roamr") opens that recording; roamr://history opens History;
    /// roamr://track (a tap on the Live Activity) opens the Track tab with the live recording.
    static func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "roamr" else { return false }
        switch url.host?.lowercased() {
        case "trip":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
            if let id, UUID(uuidString: id) != nil { DriveFinishedNotifier.requestOpen(id) }
            else { NotificationCenter.default.post(name: DriveFinishedNotifier.openActivityNote, object: nil) }
            return true
        case "history":
            NotificationCenter.default.post(name: DriveFinishedNotifier.openActivityNote, object: nil)
            return true
        case "track":
            NotificationCenter.default.post(name: RoamrTabs.openTrack, object: nil)
            return true
        default:
            return false
        }
    }
}
