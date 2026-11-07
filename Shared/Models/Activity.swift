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

    init() {}

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

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(_ loc: CLLocation) {
        lat = loc.coordinate.latitude
        lng = loc.coordinate.longitude
        alt = loc.verticalAccuracy >= 0 ? loc.altitude : .nan
        t = loc.timestamp.timeIntervalSince1970
        speed = loc.speed
    }

    // NaN is not valid JSON, so altitude is encoded as nil when unknown.
    enum CodingKeys: String, CodingKey { case lat, lng, alt, t, speed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        alt = try c.decodeIfPresent(Double.self, forKey: .alt) ?? .nan
        t = try c.decode(Double.self, forKey: .t)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? -1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        if alt.isFinite { try c.encode(alt, forKey: .alt) }
        try c.encode(t, forKey: .t)
        try c.encode(speed.isFinite ? speed : -1, forKey: .speed)
    }
}

