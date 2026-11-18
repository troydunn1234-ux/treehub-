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
            if a.kind != .drive, let ends = coarseEnds(a) {
                t.startLat = ends.startLat; t.startLng = ends.startLng
                t.endLat = ends.endLat; t.endLng = ends.endLng
            }
            return t
        }
        WellnessBridge.publishRoamr(trips: trips)
    }

    // MARK: Route ends without decoding routes

    struct Ends: Equatable { var startLat: Double; var startLng: Double; var endLat: Double; var endLng: Double }

    /// Coarse start / end per trip, remembered by id + end time + distance (a trim or edit changes those), so a
    /// publish (on every save and every trip back to the front) doesn't read and decode up to 300 routes on the
    /// main thread: only trips it hasn't seen yet are read, and only their first and last points are decoded.
    private static var endsCache: [UUID: (key: String, ends: Ends?)] = [:]

    private static var seeded = false

    private static func cacheKey(end: Date, distanceM: Double) -> String { "\(end.timeIntervalSince1970)|\(distanceM)" }

    /// The feed already published holds every trip's coarse ends: start from it, so even the first publish after
    /// a launch only reads routes of trips that are new or changed since.
    private static func seedFromFeed() {
        guard !seeded else { return }
        seeded = true
        for t in WellnessBridge.roamr()?.trips ?? [] where t.kind != ActivityKind.drive.rawValue {
            guard let a = t.startLat, let b = t.startLng, let c = t.endLat, let d = t.endLng, endsCache[t.id] == nil else { continue }
            endsCache[t.id] = (cacheKey(end: t.end, distanceM: t.distanceM), Ends(startLat: a, startLng: b, endLat: c, endLng: d))
        }
    }

    private static func coarseEnds(_ a: Activity) -> Ends? {
        seedFromFeed()
        let key = cacheKey(end: a.end, distanceM: a.distanceM)
        if let hit = endsCache[a.id], hit.key == key { return hit.ends }
        var ends: Ends?
        if let data = a.routeData, let fl = routeEnds(data) ?? fullEnds(a) {
            ends = Ends(startLat: WellnessBridge.coarse(fl.first.lat), startLng: WellnessBridge.coarse(fl.first.lng),
                        endLat: WellnessBridge.coarse(fl.last.lat), endLng: WellnessBridge.coarse(fl.last.lng))
        }
        endsCache[a.id] = (key, ends)
        return ends
    }

    private static func fullEnds(_ a: Activity) -> (first: RoutePoint, last: RoutePoint)? {
        let pts = a.route
        guard let f = pts.first, let l = pts.last else { return nil }
        return (f, l)
    }

    /// First and last point of a stored route (`Activity.routeData`, a JSON array of flat point objects) without
    /// decoding the points in between. Nil when the data doesn't look like that (the caller then decodes it all).
    nonisolated static func routeEnds(_ data: Data) -> (first: RoutePoint, last: RoutePoint)? {
        let open = UInt8(ascii: "{"), close = UInt8(ascii: "}")
        guard let s0 = data.firstIndex(of: open), let e0 = data[s0...].firstIndex(of: close),
              let e1 = data.lastIndex(of: close), let s1 = data[..<e1].lastIndex(of: open), s1 >= s0 else { return nil }
        let dec = JSONDecoder()
        guard let f = try? dec.decode(RoutePoint.self, from: Data(data[s0...e0])),
              let l = try? dec.decode(RoutePoint.self, from: Data(data[s1...e1])) else { return nil }
        return (f, l)
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
