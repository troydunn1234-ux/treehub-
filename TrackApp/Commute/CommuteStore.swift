import Foundation
import CoreLocation
import Observation
import SwiftData

/// The pinned places (Navigator's Home, Work and Favorites) and each trip's two ends, read without decoding whole
/// routes. Nothing new is stored: pins live where the Directions sheet already keeps them.
@MainActor
enum CommuteStore {

    /// Home, Work, then the named spots, in that order.
    static func pins(_ nav: Navigator = .shared) -> [CommutePin] {
        var out: [CommutePin] = []
        if let h = nav.home { out.append(CommutePin(role: .home, place: h)) }
        if let w = nav.work { out.append(CommutePin(role: .work, place: w)) }
        out += nav.favorites.map { CommutePin(role: .custom, place: $0) }
        if out.isEmpty, TrackDemo.isOn { return demoPins }
        return out
    }

    /// -demo only (simulator screenshots): made-up spots that match the demo commute drives. Never saved.
    static let demoPins: [CommutePin] = [
        CommutePin(role: .home, place: NavPlace(name: "Home", subtitle: "Mission District, San Francisco",
                                                coordinate: .init(latitude: 37.7599, longitude: -122.4148))),
        CommutePin(role: .work, place: NavPlace(name: "Work", subtitle: "SoMa, San Francisco",
                                                coordinate: .init(latitude: 37.7880, longitude: -122.3990))),
        CommutePin(role: .custom, place: NavPlace(name: "Climbing gym", subtitle: "Dogpatch, San Francisco",
                                                  coordinate: .init(latitude: 37.7570, longitude: -122.3880))),
    ]

    // MARK: Trip ends

    private struct Ends { var from: CLLocationCoordinate2D; var to: CLLocationCoordinate2D }
    /// Each trip's two ends, remembered with its end time and distance (a trim changes both). A hit never touches
    /// the stored route: the old check read the route file on every call to compare its size, and History and the
    /// Track screen ask for every drive each time they redraw.
    private static var cache: [UUID: (key: String, ends: Ends)] = [:]

    private static func endsKey(_ a: Activity) -> String { "\(a.end.timeIntervalSince1970)|\(a.distanceM)" }

    /// The trip's two ends (cached; re-read after a trim). Nil for a trip without a route.
    static func trip(_ a: Activity) -> CommuteMath.Trip? {
        let key = endsKey(a)
        let ends: Ends
        if let hit = cache[a.id], hit.key == key {
            ends = hit.ends
        } else {
            guard let read = readEnds(a) else { return nil }
            cache[a.id] = (key, read)
            ends = read
        }
        return CommuteMath.Trip(id: a.id, start: a.start, seconds: a.elapsedSec, meters: a.distanceM,
                                from: ends.from, to: ends.to, fromName: a.startPlace, toName: a.endPlace)
    }

    /// First and last point of the stored route (only those two are decoded when the data allows).
    private static func readEnds(_ a: Activity) -> Ends? {
        guard let data = a.routeData else { return nil }
        if let e = RoamrWellness.routeEnds(data) { return Ends(from: e.first.coordinate, to: e.last.coordinate) }
        let pts = a.route
        guard let f = pts.first, let l = pts.last else { return nil }
        return Ends(from: f.coordinate, to: l.coordinate)
    }

    /// Whether the ends of the recent drives have been read (`warm(in:)`). The Track screen's "Pin this?" card waits
    /// for it instead of reading up to 150 route files while Roamr opens.
    @Observable final class Readiness {
        var warm = false
        /// Bumped when a drive is put on (or taken off) a commute by hand, so the Commutes cards redraw.
        var assignments = 0
    }
    static let readiness = Readiness()

    /// A moment after launch: reads the ends of the last 60 days of drives (the ones "Pin this?" looks at), a few at
    /// a time with a breather in between so the screen stays smooth, then lets the card show.
    static func warm(in context: ModelContext, now: Date = Date()) async {
        let since = now.addingTimeInterval(-60 * 86_400)
        var fd = FetchDescriptor<Activity>(predicate: #Predicate { $0.start > since && $0.kindRaw == "drive" },
                                           sortBy: [SortDescriptor(\.start, order: .reverse)])
        fd.fetchLimit = 150
        let drives = (try? context.fetch(fd)) ?? []
        var read = 0
        for a in drives {
            if Task.isCancelled { break }
            guard a.modelContext != nil, !a.isDeleted else { continue }
            if let hit = cache[a.id], hit.key == endsKey(a) { continue }
            _ = trip(a)
            read += 1
            if read % 8 == 0 { try? await Task.sleep(for: .milliseconds(12)) }
        }
        readiness.warm = true
    }

    /// Drives, as commute trips (routes between pins are about the car: they carry a fuel estimate).
    static func driveTrips(_ activities: [Activity]) -> [CommuteMath.Trip] {
        activities.filter { $0.kind == .drive }.compactMap(trip)
    }

    /// Routes between pins from these drives, hand-picked assignments included (History's Commutes card and page).
    static func routes(_ activities: [Activity], pins: [CommutePin]) -> [CommuteMath.Route] {
        _ = readiness.assignments   // redraw after "Count as commute…"
        guard pins.count >= 2 else { return [] }
        return CommuteMath.routes(driveTrips(activities), pins: pins, assignments: assignments())
    }

    // MARK: "Count as commute…" (a drive put on a commute by hand)

    /// Trip id -> [from pin id, to pin id]. On this iPhone only; nothing in the trip itself changes except, when
    /// it had no name of its own, its title ("Home → Work").
    static let assignmentsKey = "roamr.commuteAssignments"

    static func assignments() -> [UUID: CommuteMath.Assignment] {
        let raw = UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: [String]] ?? [:]
        var out: [UUID: CommuteMath.Assignment] = [:]
        for (k, v) in raw {
            guard let id = UUID(uuidString: k), v.count == 2 else { continue }
            out[id] = CommuteMath.Assignment(from: v[0], to: v[1])
        }
        return out
    }

    static func assignment(for id: UUID) -> CommuteMath.Assignment? { assignments()[id] }

    /// The pins a drive runs between: its hand-picked commute, else what its ends say (nil when neither).
    static func commuteEnds(_ a: Activity, pins: [CommutePin]) -> (from: CommutePin, to: CommutePin)? {
        if let x = assignment(for: a.id), let f = pins.first(where: { $0.id == x.from }),
           let t = pins.first(where: { $0.id == x.to }), f.id != t.id {
            return (f, t)
        }
        guard let t = trip(a) else { return nil }
        return CommuteMath.autoEnds(from: t.from, to: t.to, pins: pins)
    }

    /// A title Roamr gave the drive itself ("Home → Work", "To Work", "From Home"), as opposed to one you typed.
    static func isAutoTitle(_ title: String, pins: [CommutePin]) -> Bool {
        if title.isEmpty { return true }
        for a in pins {
            if title == String(localized: "To \(a.label)") || title == String(localized: "From \(a.label)") { return true }
            for b in pins where b.id != a.id && title == "\(a.label) → \(b.label)" { return true }
        }
        return false
    }

    /// Puts the drive on the commute from `from` to `to`, and names it so unless you named it yourself.
    static func assign(_ a: Activity, from: CommutePin, to: CommutePin, pins: [CommutePin]) {
        var raw = UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: [String]] ?? [:]
        raw[a.id.uuidString] = [from.id, to.id]
        UserDefaults.standard.set(raw, forKey: assignmentsKey)
        if isAutoTitle(a.title, pins: pins) { a.title = "\(from.label) → \(to.label)" }
        try? a.modelContext?.save()
        readiness.assignments += 1
    }

    /// Takes the drive off its hand-picked commute; a title Roamr gave it goes back to what its ends say.
    static func unassign(_ a: Activity, pins: [CommutePin]) {
        var raw = UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: [String]] ?? [:]
        guard raw.removeValue(forKey: a.id.uuidString) != nil else { return }
        UserDefaults.standard.set(raw, forKey: assignmentsKey)
        if isAutoTitle(a.title, pins: pins) {
            a.title = trip(a).flatMap { CommuteMath.title(from: $0.from, to: $0.to, pins: pins) } ?? ""
        }
        try? a.modelContext?.save()
        readiness.assignments += 1
    }

    /// The auto title for a trip that just finished ("Home → Work"), or nil.
    static func autoTitle(_ points: [RoutePoint]) -> String? {
        guard let f = points.first, let l = points.last else { return nil }
        return CommuteMath.title(from: f.coordinate, to: l.coordinate, pins: pins())
    }

    // MARK: "Pin this?" suggestions

    private static let dismissedKey = "roamr.pinSuggestDismissed"

    static func dismissedSpots() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    static func dismiss(_ spot: CommuteMath.Spot) {
        var s = dismissedSpots()
        s.insert(spot.id)
        UserDefaults.standard.set(Array(s), forKey: dismissedKey)
    }

    /// The most visited unpinned spot from the last 60 days of drives, if you've been there 3+ times.
    static func suggestion(_ activities: [Activity], now: Date = Date()) -> CommuteMath.Spot? {
        let since = now.addingTimeInterval(-60 * 86_400)
        let recent = driveTrips(activities.filter { $0.start > since })
        let dismissed = dismissedSpots()
        return CommuteMath.frequentSpots(recent, pins: pins()).first { !dismissed.contains($0.id) }
    }
}
