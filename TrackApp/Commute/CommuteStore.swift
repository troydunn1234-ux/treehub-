import Foundation
import CoreLocation

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

    private struct Ends { var size: Int; var from: CLLocationCoordinate2D; var to: CLLocationCoordinate2D }
    private static var cache: [UUID: Ends] = [:]

    /// The trip's two ends (cached; re-read when its route changes size, e.g. after a trim).
    static func trip(_ a: Activity) -> CommuteMath.Trip? {
        guard let data = a.routeData else { return nil }
        var ends = cache[a.id]
        if ends?.size != data.count {
            if let e = RoamrWellness.routeEnds(data) {
                ends = Ends(size: data.count, from: e.first.coordinate, to: e.last.coordinate)
            } else {
                let pts = a.route
                guard let f = pts.first, let l = pts.last else { return nil }
                ends = Ends(size: data.count, from: f.coordinate, to: l.coordinate)
            }
            cache[a.id] = ends
        }
        guard let ends else { return nil }
        return CommuteMath.Trip(id: a.id, start: a.start, seconds: a.elapsedSec, meters: a.distanceM,
                                from: ends.from, to: ends.to, fromName: a.startPlace, toName: a.endPlace)
    }

    /// Drives, as commute trips (routes between pins are about the car: they carry a fuel estimate).
    static func driveTrips(_ activities: [Activity]) -> [CommuteMath.Trip] {
        activities.filter { $0.kind == .drive }.compactMap(trip)
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
