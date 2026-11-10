import Foundation
import SwiftData
import CoreLocation

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case walk, run, hike, bike, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk:
            #if TRACK_APP
            return "Walk"
            #else
            return "Stroll"
            #endif
        case .run: return "Run"
        case .hike: return "Hike"
        case .bike: return "Ride"
        case .drive: return "Drive"
        }
    }

    var symbol: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .hike: return "figure.hiking"
        case .bike: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    var isOnFoot: Bool { self == .walk || self == .run || self == .hike }

    /// Which activity types this app offers.
    static var available: [ActivityKind] {
        #if TRACK_APP
        return allCases
        #else
        return [.walk, .hike]
        #endif
    }
}

@Model
final class Activity {
    var id: UUID = UUID()
    var kindRaw: String = ActivityKind.walk.rawValue
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var distanceM: Double = 0
    var movingSec: Double = 0
    var elevGainM: Double = 0
    var maxSpeed: Double = 0
    var startPlace: String = ""
    var endPlace: String = ""
    var notes: String = ""
    var avgHR: Double?
    @Attribute(.externalStorage) var routeData: Data?
    /// Lane changes spotted during a drive (JSON of [LaneChange]).
    var laneChangesData: Data? = nil
    /// Idle seconds cut off the end (or start) of this recording, by auto-finish or by hand.
    var trimmedSec: Double = 0
    /// The app finished this one on its own after you stopped moving.
    var autoFinished: Bool = false

    init() {}

    /// Cuts the recording to the points between two times (seconds since 1970) and recomputes
    /// distance, moving time, top speed and lane changes from what's left. Elevation gain is kept.
    func trim(startT: Double? = nil, endT: Double? = nil) {
        let pts = route
        guard pts.count > 1 else { return }
        let lo = startT ?? pts.first!.t
        let hi = endT ?? pts.last!.t
        let kept = pts.filter { $0.t >= lo && $0.t <= hi }
        guard kept.count > 1 else { return }
        let cutHead = max(0, kept.first!.t - pts.first!.t)
        let cutTail = max(0, pts.last!.t - kept.last!.t)
        trimmedSec += cutHead + cutTail
        route = kept
        laneChanges = laneChanges.filter { $0.t >= lo && $0.t <= hi }
        let s = Self.stats(kept)
        distanceM = s.distance
        movingSec = s.moving
        maxSpeed = s.maxSpeed
        if cutHead > 0 { start = Date(timeIntervalSince1970: kept.first!.t) }
        end = Date(timeIntervalSince1970: kept.last!.t)
        if end <= start { end = start.addingTimeInterval(1) }
    }

    /// Distance, moving time and top speed from a run of points, the same way the tracker counts them.
    static func stats(_ pts: [RoutePoint]) -> (distance: Double, moving: Double, maxSpeed: Double) {
        var d = 0.0, moving = 0.0, top = 0.0
        for i in 1..<max(1, pts.count) {
            let a = pts[i - 1], b = pts[i]
            let dt = b.t - a.t
            guard dt > 0 else { continue }
            let step = CLLocation(latitude: a.lat, longitude: a.lng).distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
            let v = step / dt
            if v > 95 { continue }
            d += step
            if v > 0.5 && dt < 300 { moving += dt }
            let sp = b.speed >= 0 ? b.speed : v
            if sp < 95 { top = max(top, sp) }
        }
        return (d, moving, top)
    }

    var laneChanges: [LaneChange] {
        get { laneChangesData.flatMap { try? JSONDecoder().decode([LaneChange].self, from: $0) } ?? [] }
        set { laneChangesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .walk }
        set { kindRaw = newValue.rawValue }
    }

    var elapsedSec: Double { max(0, end.timeIntervalSince(start)) }

    var route: [RoutePoint] {
        get {
            guard let routeData, let pts = try? JSONDecoder().decode([RoutePoint].self, from: routeData) else { return [] }
            return pts
        }
        set { routeData = try? JSONEncoder().encode(newValue) }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return "\(Format.partOfDay(start)) \(kind.title)"
    }
}

struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lng: Double
    var alt: Double
    var t: Double      // seconds since 1970
    var speed: Double  // m/s, -1 if unknown
    var limit: Double = -1  // posted speed limit in m/s while driving, -1 if unknown

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(_ loc: CLLocation) {
        lat = loc.coordinate.latitude
        lng = loc.coordinate.longitude
        alt = loc.verticalAccuracy >= 0 ? loc.altitude : .nan
        t = loc.timestamp.timeIntervalSince1970
        speed = loc.speed
    }

    // NaN is not valid JSON, so altitude is encoded as nil when unknown.
    enum CodingKeys: String, CodingKey { case lat, lng, alt, t, speed, lim }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        alt = try c.decodeIfPresent(Double.self, forKey: .alt) ?? .nan
        t = try c.decode(Double.self, forKey: .t)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? -1
        limit = try c.decodeIfPresent(Double.self, forKey: .lim) ?? -1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        if alt.isFinite { try c.encode(alt, forKey: .alt) }
        try c.encode(t, forKey: .t)
        try c.encode(speed.isFinite ? speed : -1, forKey: .speed)
        if limit > 0 { try c.encode(limit, forKey: .lim) }
    }
}

