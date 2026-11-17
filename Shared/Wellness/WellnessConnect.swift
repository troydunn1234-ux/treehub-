import Foundation
import UIKit
import Observation

// How one app's records line up with another's, read from the shared wellness feed (WellnessBridge.swift):
//  • today across the apps: calm minutes (Still Pointz), tree hugs (Rootbound), distance on foot (Roamr), readiness (Pulse Lab)
//  • a walk and the hugs logged on it, a walk and the breathwork during / right after it
//  • a tree and the walks that passed it, a breath session and the tree it was done with
// Read-only: nothing here writes the feed, Apple Health or any app's own data. Compiled into Rootbound, Roamr,
// Still Pointz and Pulse Lab, so it uses no app's own types (each app passes its own unit preference).

enum WellnessConnect {
    /// Screenshot / QA runs ("-demo"): the cards show sample numbers instead of an empty feed.
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    // MARK: - Freshness

    /// "updated just now", "updated 5 min ago", "updated 3 h ago", "updated yesterday", "updated Nov 12".
    static func updatedText(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 90 { return "updated just now" }   // also absorbs a little clock skew
        if s < 3600 { return "updated \(Int(s / 60)) min ago" }
        let cal = Calendar.current
        if s < 12 * 3600 || cal.isDate(date, inSameDayAs: now) { return "updated \(Int(s / 3600)) h ago" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "updated yesterday" }
        return "updated " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Formatting (no app's Units type: each app passes its own preference)

    /// "2.4 mi" / "3.9 km", "0 mi" when nothing.
    static func distance(_ meters: Double, metric: Bool) -> String {
        let unit = metric ? "km" : "mi"
        let v = max(0, meters) / (metric ? 1000 : 1609.344)
        if v == 0 { return "0 \(unit)" }
        if v < 0.1 { return "0.1 \(unit)" }
        return String(format: "%.1f", v) + " " + unit
    }

    /// "12 min", "1 h 05 min".
    static func minutes(_ m: Double) -> String {
        let total = Int(max(0, m).rounded())
        if total < 60 { return "\(total) min" }
        return "\(total / 60) h " + String(format: "%02d", total % 60) + " min"
    }

    /// Metric for apps without their own setting (Still Pointz), from the region.
    static var localeMetric: Bool { Locale.current.measurementSystem == .metric }

    /// "rooted-breath" -> "Rooted Breath".
    static func practiceName(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    // MARK: - Today across the apps

    struct Today: Equatable {
        struct Calm: Equatable { var minutes: Double; var sessions: Int; var updated: Date }
        struct Hugs: Equatable { var count: Int; var minutes: Double; var lastTree: String?; var updated: Date }
        struct Moves: Equatable { var distanceM: Double; var trips: Int; var updated: Date }
        struct Ready: Equatable {
            var readiness: Double?
            var recovery: Double?
            /// False when Pulse Lab's newest summary is from an earlier day (then both numbers are nil).
            var isToday: Bool
            var updated: Date
        }
        /// Each is nil when that app has never shared (not installed, or not opened since it learned to share).
        var calm: Calm?
        var hugs: Hugs?
        var moves: Moves?
        var ready: Ready?
    }

    /// Today's numbers from the four feed parts (pure, so it's testable).
    static func today(on day: Date, stillPoint: WellnessBridge.StillPointPart?, rootbound: WellnessBridge.RootboundPart?,
                      roamr: WellnessBridge.RoamrPart?, pulseLab: WellnessBridge.PulseLabPart?) -> Today {
        let cal = Calendar.current
        var t = Today()
        if let sp = stillPoint {
            let s = sp.sessions.filter { $0.isCalm && cal.isDate($0.date, inSameDayAs: day) }
            t.calm = .init(minutes: s.reduce(0) { $0 + $1.minutes }, sessions: s.count, updated: sp.updated)
        }
        if let rb = rootbound {
            let h = rb.hugs.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
            t.hugs = .init(count: h.count, minutes: h.reduce(0) { $0 + $1.minutes }, lastTree: h.first?.tree, updated: rb.updated)
        }
        if let r = roamr {
            let w = r.trips.filter { $0.isOnFoot && cal.isDate($0.start, inSameDayAs: day) }
            t.moves = .init(distanceM: w.reduce(0) { $0 + $1.distanceM }, trips: w.count, updated: r.updated)
        }
        if let p = pulseLab {
            let isToday = p.date == WellnessBridge.dayKey(day)
            t.ready = .init(readiness: isToday ? p.readiness : nil, recovery: isToday ? p.whoopRecovery : nil,
                            isToday: isToday, updated: p.updated)
        }
        return t
    }

    /// Screenshot numbers for "-demo" runs.
    static func sampleToday(now: Date = Date()) -> Today {
        Today(calm: .init(minutes: 18, sessions: 2, updated: now.addingTimeInterval(-5 * 60)),
              hugs: .init(count: 1, minutes: 6, lastTree: "Grandpa Oak", updated: now.addingTimeInterval(-40 * 60)),
              moves: .init(distanceM: 3860, trips: 1, updated: now.addingTimeInterval(-2 * 3600)),
              ready: .init(readiness: 74, recovery: 68, isToday: true, updated: now.addingTimeInterval(-25 * 60)))
    }

    // MARK: - A walk and the tree hugs on it (Roamr trip detail)

    /// Hugs logged in Rootbound on a trip: the hug overlaps the trip (± `slack`), or Rootbound attached this trip
    /// to the hug (its walks within ±2 h). Oldest first.
    static func hugs(onTrip id: UUID, start: Date, end: Date, in hugs: [WellnessBridge.TreeHug],
                     slack: TimeInterval = 15 * 60) -> [WellnessBridge.TreeHug] {
        let a = start.addingTimeInterval(-slack), b = end.addingTimeInterval(slack)
        return hugs.filter { h in
            if h.walkIDs?.contains(id) == true { return true }
            let hugEnd = h.date.addingTimeInterval(max(0, h.minutes) * 60)
            return hugEnd >= a && h.date <= b
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - A walk and the breathwork during or right after it

    struct BreathMatch: Identifiable, Equatable {
        var session: WellnessBridge.Session
        /// Began before the trip ended.
        var during: Bool
        /// Whole minutes after the trip ended (0 when during).
        var minutesAfter: Int
        var id: UUID { session.id }
    }

    /// Still Pointz calm sessions (a minute or more) that began during a trip or up to `within` after it ended.
    static func breaths(forTrip start: Date, end: Date, in sessions: [WellnessBridge.Session],
                        within: TimeInterval = 30 * 60) -> [BreathMatch] {
        let last = end.addingTimeInterval(within)
        return sessions
            .filter { $0.isCalm && $0.minutes >= 1 && $0.date >= start && $0.date <= last }
            .sorted { $0.date < $1.date }
            .map { s in
                let during = s.date < end
                return BreathMatch(session: s, during: during,
                                   minutesAfter: during ? 0 : max(0, Int((s.date.timeIntervalSince(end) / 60).rounded())))
            }
    }

    // MARK: - A tree and the walks that passed it (Rootbound tree page)

    /// Great-circle distance in meters.
    static func meters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lng2 - lng1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    struct PassingTrip: Identifiable, Equatable {
        enum Reason: Equatable { case hugged, startedNear, endedNear }
        var trip: WellnessBridge.Trip
        var reason: Reason
        var id: UUID { trip.id }
    }

    /// Walks, runs and hikes that passed a tree: one of its hugs happened on the trip (± `slack`), or the trip
    /// started or ended within `radius` of it. Roamr shares only start and end points (rounded to ~100 m), never
    /// the route, so a walk that went by mid-route without a hug can't be told apart. Newest first.
    static func tripsPassing(treeLat lat: Double?, treeLng lng: Double?, hugTimes: [(start: Date, minutes: Double)],
                             in trips: [WellnessBridge.Trip], radius: Double = 250,
                             slack: TimeInterval = 15 * 60) -> [PassingTrip] {
        var out: [PassingTrip] = []
        for t in trips where t.isOnFoot {
            let a = t.start.addingTimeInterval(-slack), b = t.end.addingTimeInterval(slack)
            if hugTimes.contains(where: { $0.start.addingTimeInterval(max(0, $0.minutes) * 60) >= a && $0.start <= b }) {
                out.append(PassingTrip(trip: t, reason: .hugged))
                continue
            }
            guard let lat, let lng else { continue }
            if let sLat = t.startLat, let sLng = t.startLng, meters(lat, lng, sLat, sLng) <= radius {
                out.append(PassingTrip(trip: t, reason: .startedNear))
            } else if let eLat = t.endLat, let eLng = t.endLng, meters(lat, lng, eLat, eLng) <= radius {
                out.append(PassingTrip(trip: t, reason: .endedNear))
            }
        }
        return out.sorted { $0.trip.start > $1.trip.start }
    }

    // MARK: - A breath session and its tree (Still Pointz session page)

    struct TreeMatch: Equatable {
        enum How: Equatable {
            /// Linked to a hug in Rootbound's hug logger.
            case linked
            /// Started from Rootbound's "Breathe with this tree".
            case tagged
            /// A hug of the tree overlaps the session.
            case sameTime
        }
        var treeID: UUID?
        /// The tree's current name in Rootbound (renames show), else the name the session was started with.
        var name: String
        var species: String
        /// Hugs of this tree in Rootbound's feed (last 120 days).
        var hugCount: Int
        var lastHug: Date?
        var how: How
    }

    /// The tree a Still Pointz session went with, if any: linked in Rootbound first, then the tree the session was
    /// started for, then a hug overlapping it (± `slack`).
    static func tree(forSession id: UUID, start: Date, end: Date, taggedTreeID: String?, taggedName: String?,
                     in hugs: [WellnessBridge.TreeHug], slack: TimeInterval = 5 * 60) -> TreeMatch? {
        func clean(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        func summary(_ treeID: UUID?, anchor: WellnessBridge.TreeHug?, fallback: String, how: TreeMatch.How) -> TreeMatch {
            let same = treeID.map { tid in hugs.filter { $0.treeID == tid } } ?? (anchor.map { [$0] } ?? [])
            let newest = same.max { $0.date < $1.date }
            return TreeMatch(treeID: treeID, name: clean(newest?.tree) ?? fallback, species: clean(newest?.species) ?? "",
                             hugCount: same.count, lastHug: newest?.date, how: how)
        }
        if let h = hugs.first(where: { $0.sessionIDs?.contains(id) == true }) {
            return summary(h.treeID, anchor: h, fallback: clean(h.tree) ?? "your tree", how: .linked)
        }
        if let raw = taggedTreeID, let tid = UUID(uuidString: raw) {
            return summary(tid, anchor: nil, fallback: clean(taggedName) ?? "your tree", how: .tagged)
        }
        let a = start.addingTimeInterval(-slack), b = end.addingTimeInterval(slack)
        let overlapping = hugs.filter { $0.date <= b && $0.date.addingTimeInterval(max(0, $0.minutes) * 60) >= a }
        if let h = overlapping.min(by: { abs($0.date.timeIntervalSince(start)) < abs($1.date.timeIntervalSince(start)) }) {
            return summary(h.treeID, anchor: h, fallback: clean(h.tree) ?? "a tree", how: .sameTime)
        }
        if let n = clean(taggedName) {
            return TreeMatch(treeID: nil, name: n, species: "", hugCount: 0, lastHug: nil, how: .tagged)
        }
        return nil
    }

    // MARK: - Opening the other apps

    /// One of the family apps another app links to.
    struct Peer: Equatable {
        let name: String
        let scheme: String
        let bundleID: String
    }

    static let rootbound = Peer(name: "Rootbound", scheme: "rootbound", bundleID: "com.troydunn.rootbound")
    static let stillPoint = Peer(name: "Still Pointz", scheme: "stillpoint", bundleID: "com.troydunn.stillpoint")
    static let roamr = Peer(name: "Roamr", scheme: "roamr", bundleID: "com.troydunn.roamr")
    static let pulseLab = Peer(name: "Pulse Lab", scheme: "pulselab", bundleID: "com.troydunn.pulselab")

    static let rootboundHome = URL(string: "rootbound://home")!
    static let stillPointJourney = URL(string: "stillpoint://journey")!
    static let roamrHistory = URL(string: "roamr://history")!
    static let pulseLabToday = URL(string: "pulselab://today")!

    /// rootbound://tree?id=…
    static func rootboundTree(_ id: UUID) -> URL {
        URL(string: "rootbound://tree?id=\(id.uuidString)") ?? rootboundHome
    }

    /// roamr://trip?id=…
    static func roamrTrip(_ id: UUID) -> URL {
        URL(string: "roamr://trip?id=\(id.uuidString)") ?? roamrHistory
    }

    /// stillpoint://journey?session=… (older Still Pointz builds ignore the session and just open Journey).
    static func stillPointSession(_ id: UUID) -> URL {
        URL(string: "stillpoint://journey?session=\(id.uuidString)") ?? stillPointJourney
    }

    /// True when the app is on this iPhone. Needs its scheme in LSApplicationQueriesSchemes (project.yml),
    /// otherwise iOS always answers false.
    @MainActor
    static func isInstalled(_ peer: Peer) -> Bool {
        guard let u = URL(string: peer.scheme + "://") else { return false }
        return UIApplication.shared.canOpenURL(u)
    }

    /// App Store ID of a family app (from MoreApps).
    static func appStoreID(_ peer: Peer) -> Int? {
        MoreApps.all.first(where: { $0.bundleID == peer.bundleID })?.appStoreID
    }

    /// App Store page of a family app (IDs from MoreApps).
    static func storeURL(_ peer: Peer) -> URL? {
        guard let id = appStoreID(peer) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    /// Opens `url` in the other app when it's installed (canOpenURL), else its App Store page on top of this app
    /// (closing it comes straight back here). False when there was nothing to open.
    @MainActor
    @discardableResult
    static func open(_ url: URL, in peer: Peer) -> Bool {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        return showStore(peer)
    }

    /// The App Store page for `peer`, in-app. False when it has no App Store ID.
    @MainActor
    @discardableResult
    static func showStore(_ peer: Peer) -> Bool {
        guard let id = appStoreID(peer) else { return false }
        StoreProductPage.open(id)
        return true
    }
}

/// The four feed parts as this app last read them, reloaded whenever the app becomes active (the other apps can
/// only publish while this one is in the background). Views read it in `body`, so a card that starts empty
/// still appears the moment there's something to show, and nothing reads files on every redraw.
@MainActor
@Observable
final class WellnessFeed {
    static let shared = WellnessFeed()

    private(set) var stillPoint: WellnessBridge.StillPointPart?
    private(set) var rootbound: WellnessBridge.RootboundPart?
    private(set) var roamr: WellnessBridge.RoamrPart?
    private(set) var pulseLab: WellnessBridge.PulseLabPart?
    /// URL schemes of the family apps on this iPhone.
    private(set) var installed: Set<String> = []
    @ObservationIgnored private var loadedAt = Date.distantPast
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var reloadQueued = false

    private init() {
        reload()
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WellnessFeed.shared.reload() }
        }
        // Another family app running in the background (Roamr finishing a walk, Pulse Lab's background refresh,
        // Still Pointz saving a Watch session) rewrote its part: show it now, not at the next foreground.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                        wellnessFeedChangedCallback, WellnessBridge.changedNotification as CFString,
                                        nil, .deliverImmediately)
    }

    /// Several parts often change together (a save in one app, then its feed): read once, half a second later.
    fileprivate func feedChanged() {
        guard !reloadQueued else { return }
        reloadQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                WellnessFeed.shared.reloadQueued = false
                WellnessFeed.shared.reload()
            }
        }
    }

    /// Read the shared folder again (four small JSON files).
    func reload() {
        loadedAt = Date()
        // The other three apps (this app never asks iOS about its own scheme).
        let me = Bundle.main.bundleIdentifier ?? ""
        let peers = [WellnessConnect.rootbound, WellnessConnect.stillPoint, WellnessConnect.roamr, WellnessConnect.pulseLab]
            .filter { $0.bundleID != me }
        let nowInstalled = Set(peers.filter { WellnessConnect.isInstalled($0) }.map(\.scheme))
        if nowInstalled != installed { installed = nowInstalled }
        guard !WellnessConnect.isDemo else { return }
        let sp = WellnessBridge.stillPoint(), rb = WellnessBridge.rootbound()
        let rr = WellnessBridge.roamr(), pl = WellnessBridge.pulseLab()
        // Only assign what changed, so views don't redraw for nothing.
        if sp?.updated != stillPoint?.updated || sp?.sessions.count != stillPoint?.sessions.count { stillPoint = sp }
        if rb?.updated != rootbound?.updated || rb?.hugs.count != rootbound?.hugs.count { rootbound = rb }
        if rr?.updated != roamr?.updated || rr?.trips.count != roamr?.trips.count { roamr = rr }
        if pl != pulseLab { pulseLab = pl }
    }

    /// For onAppear: reload unless it just happened (several cards appearing together).
    func refreshIfStale(after seconds: TimeInterval = 5) {
        if Date().timeIntervalSince(loadedAt) > seconds { reload() }
    }

    /// True when `peer` is on this iPhone (always in "-demo" screenshot runs).
    func has(_ peer: WellnessConnect.Peer) -> Bool { WellnessConnect.isDemo || installed.contains(peer.scheme) }

    /// Today across the apps (sample numbers in "-demo" runs).
    var today: WellnessConnect.Today {
        if WellnessConnect.isDemo { return WellnessConnect.sampleToday() }
        return WellnessConnect.today(on: Date(), stillPoint: stillPoint, rootbound: rootbound, roamr: roamr, pulseLab: pulseLab)
    }
}

/// Darwin notification callback for `WellnessBridge.changedNotification`. A C function (captures nothing), so it
/// only hops to the main queue and lets the feed reload there.
private let wellnessFeedChangedCallback: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async {
        MainActor.assumeIsolated { WellnessFeed.shared.feedChanged() }
    }
}
