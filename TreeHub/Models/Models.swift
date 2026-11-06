import Foundation
import SwiftData
import CoreLocation

// All stored properties have defaults so the store can sync through iCloud (CloudKit).

@Model
final class Hug {
    var id: UUID = UUID()
    var date: Date = Date()

    // The tree
    var treeID: UUID = UUID()
    var treeName: String = ""
    var species: String = ""

    // Where
    var latitude: Double?
    var longitude: Double?
    var placeName: String = ""

    // Photos (stored outside the database file)
    @Attribute(.externalStorage) var treePhoto: Data?
    @Attribute(.externalStorage) var selfiePhoto: Data?
    @Attribute(.externalStorage) var garminPhoto: Data?

    // Vibe
    var tagsRaw: String = ""
    var barefoot: Bool = false
    var weather: String = ""
    var moodBefore: Int = 0
    var moodAfter: Int = 0
    var notes: String = ""

    // Breathwork (Garmin) stats
    var exercise: String = ""
    var durationMin: Double = 0
    var avgHR: Double?
    var minHR: Double?
    var maxHR: Double?
    var respRate: Double?
    var stressStart: Double?
    var stressEnd: Double?
    var bodyBattery: Double?

    // Game
    var xp: Int = 0
    var leafKey: String = ""

    init() {}

    var tags: [String] {
        get { tagsRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty } }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasStats: Bool {
        avgHR != nil || respRate != nil || stressStart != nil || stressEnd != nil || bodyBattery != nil
    }
}

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case walk, run, hike, bike, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
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

/// A tree is every hug that shares a treeID.
struct TreeSummary: Identifiable {
    let id: UUID
    var name: String
    var species: String
    var coordinate: CLLocationCoordinate2D?
    var placeName: String
    var hugs: [Hug]           // newest first
    var coverPhoto: Data?

    var hugCount: Int { hugs.count }
    var totalMinutes: Double { hugs.reduce(0) { $0 + $1.durationMin } }
    var firstHug: Date { hugs.last?.date ?? Date() }
    var lastHug: Date { hugs.first?.date ?? Date() }

    /// 1...5 hearts of friendship
    var bond: Int {
        switch hugCount {
        case 0...1: return 1
        case 2...3: return 2
        case 4...6: return 3
        case 7...11: return 4
        default: return 5
        }
    }

    static func build(from hugs: [Hug]) -> [TreeSummary] {
        let sorted = hugs.sorted { $0.date > $1.date }
        var order: [UUID] = []
        var groups: [UUID: [Hug]] = [:]
        for h in sorted {
            if groups[h.treeID] == nil { order.append(h.treeID) }
            groups[h.treeID, default: []].append(h)
        }
        return order.compactMap { id in
            guard let list = groups[id], let newest = list.first else { return nil }
            let name = list.first(where: { !$0.treeName.isEmpty })?.treeName ?? "Unnamed tree"
            let species = list.first(where: { !$0.species.isEmpty })?.species ?? ""
            let coord = list.first(where: { $0.coordinate != nil })?.coordinate
            let place = list.first(where: { !$0.placeName.isEmpty })?.placeName ?? ""
            // Cover = the oldest tree photo (the first meeting)
            let cover = list.reversed().first(where: { $0.treePhoto != nil })?.treePhoto ?? newest.selfiePhoto
            return TreeSummary(id: id, name: name, species: species, coordinate: coord,
                               placeName: place, hugs: list, coverPhoto: cover)
        }
    }
}
