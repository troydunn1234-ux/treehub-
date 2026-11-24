import Foundation
import CoreLocation

/// A pinned place: Home, Work, or a named spot (stored as Navigator's Home, Work and Favorites, so the
/// Directions sheet and the Track screen share one list).
struct CommutePin: Identifiable, Hashable {
    enum Role: String { case home, work, custom }
    var role: Role
    var place: NavPlace

    var id: String { role == .custom ? "custom:\(place.id)" : role.rawValue }
    var label: String {
        switch role {
        case .home: return String(localized: "Home")
        case .work: return String(localized: "Work")
        case .custom: return place.name
        }
    }
    var symbol: String {
        switch role {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .custom: return "mappin.circle.fill"
        }
    }
    var coordinate: CLLocationCoordinate2D { place.coordinate }
}

/// Pure commute logic: which pin a trip started/ended at, routes between pins, their stats, and spots you keep
/// stopping at that aren't pinned yet. No store, no location: tests feed it plain values.
enum CommuteMath {
    /// How close a trip's end must be to a pin to count as "at" it (parking can be a block away).
    static let pinRadius: Double = 300
    /// Endpoints closer than this are the same spot when looking for places to suggest.
    static let spotRadius: Double = 200

    struct Trip: Hashable {
        var id: UUID
        var start: Date
        var seconds: Double
        var meters: Double
        var from: CLLocationCoordinate2D
        var to: CLLocationCoordinate2D
        var fromName: String = ""
        var toName: String = ""

        static func == (a: Trip, b: Trip) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// A drive that ends at a pin counts as coming from another pin when it started within this of it (~0.5 mi):
    /// you pulled away a few houses down the street, or started the drive late.
    static let startRadius: Double = 800

    /// The closest pin within `radius` (`pinRadius` unless given).
    static func pin(near c: CLLocationCoordinate2D, in pins: [CommutePin], radius: Double = pinRadius) -> CommutePin? {
        pins.map { ($0, meters($0.coordinate, c)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    /// A drive put on a commute by hand ("Count as commute…"): the pins it ran from and to, by pin id.
    struct Assignment: Hashable {
        var from: String
        var to: String
    }

    /// The two pins a trip ran between, or nil. A hand-picked assignment wins (when both of its pins still exist);
    /// otherwise the end must be at a pin and the start at another pin, or within `startRadius` of one.
    static func ends(of t: Trip, pins: [CommutePin], assignments: [UUID: Assignment] = [:]) -> (from: CommutePin, to: CommutePin)? {
        if let a = assignments[t.id], let f = pins.first(where: { $0.id == a.from }), let to = pins.first(where: { $0.id == a.to }),
           f.id != to.id {
            return (f, to)
        }
        return autoEnds(from: t.from, to: t.to, pins: pins)
    }

    /// Ends worked out from where the drive started and stopped (no hand-picked assignment).
    static func autoEnds(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, pins: [CommutePin]) -> (from: CommutePin, to: CommutePin)? {
        guard let b = pin(near: to, in: pins) else { return nil }
        let a = pin(near: from, in: pins) ?? pin(near: from, in: pins.filter { $0.id != b.id }, radius: startRadius)
        guard let a, a.id != b.id else { return nil }
        return (a, b)
    }

    /// "Home → Work" when both ends are pins (the start may be up to `startRadius` from its pin), "To Work" /
    /// "From Home" when one is, nil otherwise (and nil for a loop that starts and ends at the same pin).
    static func title(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, pins: [CommutePin]) -> String? {
        if let e = autoEnds(from: from, to: to, pins: pins) { return "\(e.from.label) → \(e.to.label)" }
        let a = pin(near: from, in: pins), b = pin(near: to, in: pins)
        switch (a, b) {
        case let (a?, b?) where a.id != b.id: return "\(a.label) → \(b.label)"
        case (_?, _?): return nil
        case (nil, let b?): return String(localized: "To \(b.label)")
        case (let a?, nil): return String(localized: "From \(a.label)")
        default: return nil
        }
    }

    // MARK: Routes between pins

    struct Leg: Identifiable, Hashable {
        var trip: Trip
        var from: CommutePin
        var to: CommutePin
        var id: UUID { trip.id }
    }

    /// Every trip between two pins, both directions together ("Home ⇄ Work").
    struct Route: Identifiable, Hashable {
        var a: CommutePin
        var b: CommutePin
        /// Newest first.
        var legs: [Leg]
        var id: String { CommuteMath.routeKey(a, b) }
        var title: String { "\(a.label) ⇄ \(b.label)" }

        func legs(from x: CommutePin) -> [Leg] { legs.filter { $0.from.id == x.id } }
        func stats(now: Date = Date(), calendar: Calendar = .current) -> Stats { Stats(legs, now: now, calendar: calendar) }
    }

    struct Stats: Hashable {
        var count: Int
        var thisWeek: Int
        var avgSeconds: Double?
        var bestSeconds: Double?
        var avgMeters: Double?
        var weekMeters: Double

        init(_ legs: [Leg], now: Date = Date(), calendar: Calendar = .current) {
            count = legs.count
            let week = calendar.dateInterval(of: .weekOfYear, for: now)
            let inWeek = legs.filter { week?.contains($0.trip.start) ?? false }
            thisWeek = inWeek.count
            weekMeters = inWeek.reduce(0) { $0 + $1.trip.meters }
            let timed = legs.map(\.trip.seconds).filter { $0 > 0 }
            avgSeconds = timed.isEmpty ? nil : timed.reduce(0, +) / Double(timed.count)
            bestSeconds = timed.min()
            avgMeters = legs.isEmpty ? nil : legs.reduce(0) { $0 + $1.trip.meters } / Double(legs.count)
        }
    }

    static func routeKey(_ a: CommutePin, _ b: CommutePin) -> String {
        [a.id, b.id].sorted().joined(separator: "⇄")
    }

    /// Trips grouped by the pair of pins they ran between, busiest route first.
    static func routes(_ trips: [Trip], pins: [CommutePin], assignments: [UUID: Assignment] = [:]) -> [Route] {
        var byKey: [String: Route] = [:]
        for t in trips {
            guard let e = ends(of: t, pins: pins, assignments: assignments) else { continue }
            let a = e.from, b = e.to
            let key = routeKey(a, b)
            let leg = Leg(trip: t, from: a, to: b)
            if byKey[key] == nil {
                // Home (then Work) first, so it reads "Home ⇄ Work" whichever way the first trip went.
                let order: (CommutePin, CommutePin) = rank(a) <= rank(b) ? (a, b) : (b, a)
                byKey[key] = Route(a: order.0, b: order.1, legs: [])
            }
            byKey[key]?.legs.append(leg)
        }
        return byKey.values
            .map { r in var r = r; r.legs.sort { $0.trip.start > $1.trip.start }; return r }
            .sorted { ($0.legs.count, $0.legs.first?.trip.start ?? .distantPast) > ($1.legs.count, $1.legs.first?.trip.start ?? .distantPast) }
    }

    private static func rank(_ p: CommutePin) -> Int {
        switch p.role { case .home: return 0; case .work: return 1; case .custom: return 2 }
    }

    /// Fuel cost of a distance, from the vehicle's MPG and the last price per gallon.
    static func fuelCost(meters: Double, mpg: Double, pricePerGallon: Double) -> Double? {
        guard mpg > 0, pricePerGallon > 0, meters > 0 else { return nil }
        return meters / 1609.344 / mpg * pricePerGallon
    }

    // MARK: Spots worth pinning

    struct Spot: Identifiable, Hashable {
        var lat: Double
        var lng: Double
        var count: Int
        var name: String
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        /// Stable for "Not now" (rounded to ~100 m).
        var id: String { String(format: "%.3f,%.3f", lat, lng) }
    }

    /// Places where trips keep starting or ending (at least `minCount` times) that aren't near a pin yet,
    /// most visited first.
    static func frequentSpots(_ trips: [Trip], pins: [CommutePin], minCount: Int = 3) -> [Spot] {
        struct Cluster { var lat: Double; var lng: Double; var n: Int; var names: [String: Int] }
        var clusters: [Cluster] = []
        let ends = trips.flatMap { [($0.from, $0.fromName), ($0.to, $0.toName)] }
        for (c, name) in ends where pin(near: c, in: pins) == nil {
            if let i = clusters.firstIndex(where: { meters(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng), c) <= spotRadius }) {
                let n = Double(clusters[i].n)
                clusters[i].lat = (clusters[i].lat * n + c.latitude) / (n + 1)
                clusters[i].lng = (clusters[i].lng * n + c.longitude) / (n + 1)
                clusters[i].n += 1
                if !name.isEmpty { clusters[i].names[name, default: 0] += 1 }
            } else {
                clusters.append(Cluster(lat: c.latitude, lng: c.longitude, n: 1, names: name.isEmpty ? [:] : [name: 1]))
            }
        }
        return clusters.filter { $0.n >= minCount }
            .sorted { $0.n > $1.n }
            .map { c in
                Spot(lat: c.lat, lng: c.lng, count: c.n, name: c.names.max { $0.value < $1.value }?.key ?? "")
            }
    }
}
