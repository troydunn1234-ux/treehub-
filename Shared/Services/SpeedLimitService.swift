import Foundation
import CoreLocation

/// Looks up the posted speed limit of the road you're on from OpenStreetMap.
/// When a road has no posted limit in the map data, it falls back to the usual
/// California default for that kind of road and marks the result as estimated.
@MainActor
final class SpeedLimitService {
    struct Limit: Equatable {
        var mps: Double
        var estimated: Bool
        var road: String
    }

    private var cache: [String: Limit?] = [:]
    private var lastLookupAt: Date = .distantPast
    private var lastLookupLoc: CLLocation?
    private var inFlight = false

    /// Calls back on the main actor when a new limit is known. Throttled so the
    /// public map server sees at most one request every ~15 s.
    func update(for loc: CLLocation, speed: Double, onResult: @escaping (Limit?) -> Void) {
        if inFlight { return }
        if let last = lastLookupLoc {
            let moved = loc.distance(from: last)
            let since = Date().timeIntervalSince(lastLookupAt)
            guard (moved > 350 && since > 8) || (moved > 80 && since > 25) else { return }
        }
        let key = Self.cell(loc.coordinate)
        if let hit = cache[key] {
            lastLookupLoc = loc; lastLookupAt = Date()
            onResult(hit)
            return
        }
        inFlight = true
        lastLookupLoc = loc
        lastLookupAt = Date()
        let coord = loc.coordinate
        Task {
            let result = await Self.fetch(coord, preferFast: speed > 22)
            self.inFlight = false
            if self.cache.count > 400 { self.cache.removeAll() }
            self.cache[key] = result
            onResult(result)
        }
    }

    func reset() {
        lastLookupAt = .distantPast
        lastLookupLoc = nil
    }

    // ~110 m grid cells
    private static func cell(_ c: CLLocationCoordinate2D) -> String {
        "\(Int((c.latitude * 1000).rounded())),\(Int((c.longitude * 1000).rounded()))"
    }

    private static let roadRank: [String: Int] = [
        "motorway": 9, "trunk": 8, "motorway_link": 7, "trunk_link": 7, "primary": 6, "primary_link": 5,
        "secondary": 5, "secondary_link": 4, "tertiary": 4, "tertiary_link": 3, "unclassified": 2,
        "residential": 2, "living_street": 1, "service": 0]

    /// California defaults (mph) when a road has no posted limit in the map data.
    private static let defaultMph: [String: Double] = [
        "motorway": 65, "trunk": 55, "motorway_link": 45, "trunk_link": 40, "primary": 45, "primary_link": 35,
        "secondary": 40, "secondary_link": 30, "tertiary": 35, "tertiary_link": 25, "unclassified": 30,
        "residential": 25, "living_street": 15, "service": 15]

    private static func fetch(_ c: CLLocationCoordinate2D, preferFast: Bool) async -> Limit? {
        let types = roadRank.keys.sorted().joined(separator: "|")
        let q = "[out:json][timeout:8];way(around:30,\(c.latitude),\(c.longitude))[highway~\"^(\(types))$\"];out tags;"
        // Public OpenStreetMap servers; if one is busy, try the next.
        let servers = ["https://overpass-api.de/api/interpreter",
                       "https://overpass.kumi.systems/api/interpreter",
                       "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
        var elements: [[String: Any]]?
        for server in servers {
            var req = URLRequest(url: URL(string: server)!, timeoutInterval: 8)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("Roamr iOS app (personal route tracker)", forHTTPHeaderField: "User-Agent")
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? q
            req.httpBody = Data("data=\(encoded)".utf8)
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let els = obj["elements"] as? [[String: Any]] {
                elements = els
                break
            }
        }
        guard let elements else { return nil }
        let ways: [(rank: Int, tags: [String: String])] = elements.compactMap { e in
            guard let tags = e["tags"] as? [String: String], let hw = tags["highway"], let r = roadRank[hw] else { return nil }
            return (r, tags)
        }
        guard !ways.isEmpty else { return nil }
        // Fast → you're most likely on the biggest road nearby; slow → the smallest.
        let pick = preferFast ? ways.max { $0.rank < $1.rank }! : ways.min { $0.rank < $1.rank }!
        let hw = pick.tags["highway"] ?? ""
        let name = pick.tags["ref"] ?? pick.tags["name"] ?? hw.replacingOccurrences(of: "_", with: " ").capitalized
        if let raw = pick.tags["maxspeed"], let mps = parse(raw) {
            return Limit(mps: mps, estimated: false, road: name)
        }
        if let mph = defaultMph[hw] {
            return Limit(mps: mph * 0.44704, estimated: true, road: name)
        }
        return nil
    }

    /// "65 mph" → 29.06 m/s, "50" → km/h, "none"/"signals" → nil.
    nonisolated static func parse(_ raw: String) -> Double? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let first = s.split(separator: ";").first.map(String.init) ?? s
        let digits = first.prefix { $0.isNumber || $0 == "." }
        guard let n = Double(digits), n > 0 else { return nil }
        return first.contains("mph") ? n * 0.44704 : n / 3.6
    }
}
