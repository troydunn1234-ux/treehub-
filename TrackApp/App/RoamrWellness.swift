import Foundation
import SwiftData

/// Roamr -> Rootbound: publishes the last 60 days of trips into the shared App Group feed
/// (Shared/Wellness/WellnessBridge.swift, roamr.json) so Rootbound can show a walk under a tree hug.
/// Only summary numbers plus a start / end point rounded to ~100 m; never the route. Read-only for Rootbound.
@MainActor
enum RoamrWellness {
    private static var lastPublish = Date.distantPast
    private static var saveObserver: NSObjectProtocol?
    private static var pendingSave: DispatchWorkItem?
    /// The context the save observer publishes from (kept here so the observer doesn't capture it).
    private static var observedContext: ModelContext?

    static func publish(_ context: ModelContext, force: Bool = false) {
        if TrackDemo.isOn { return }
        observeSaves(context)
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

    /// Any save also re-publishes (2 s after the last one): a trip finished from the Watch (saved without the
    /// .activitySaved note, often while Roamr is in the background), trimmed, retyped or deleted. Once per launch.
    private static func observeSaves(_ context: ModelContext) {
        observedContext = context
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                pendingSave?.cancel()
                let work = DispatchWorkItem {
                    MainActor.assumeIsolated {
                        if let c = observedContext { publish(c, force: true) }
                    }
                }
                pendingSave = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            }
        }
    }

    /// roamr://trip?id=<uuid> (Rootbound "Open in Roamr") opens that recording; roamr://history opens History.
    static func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "roamr" else { return false }
        switch url.host?.lowercased() {
        case "trip":
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
            // A trip that isn't here (deleted, other iPhone) opens History instead of waiting forever.
            if let raw, let id = UUID(uuidString: raw), hasTrip(id) {
                DriveFinishedNotifier.requestOpen(id.uuidString)
                // When the link launched Roamr, the tab bar isn't listening yet: it switches to History when it
                // appears, and History then opens the trip.
                RoamrPending.queue(.history)
            } else {
                openHistory()
            }
            return true
        case "history":
            openHistory()
            return true
        default:
            return false
        }
    }

    /// History tab. Queued like a Siri action, so it also works when the link launched Roamr (the tab bar isn't
    /// listening yet; it picks the action up when it appears).
    private static func openHistory() {
        RoamrPending.queue(.history)
        NotificationCenter.default.post(name: DriveFinishedNotifier.openActivityNote, object: nil)
    }

    private static func hasTrip(_ id: UUID) -> Bool {
        guard let context = RoamrContext.container?.mainContext else { return true }   // can't tell: let History look
        var fd = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == id })
        fd.fetchLimit = 1
        return ((try? context.fetchCount(fd)) ?? 1) > 0
    }
}
