import Foundation
import CoreLocation

/// Posted speed limits from OpenStreetMap, matched to the road you're actually on.
///
/// The public map servers are slow (often 15–30 s per answer) and flaky, so instead of
/// asking them on every fix we download whole map tiles (~4 km squares) of roads with
/// their limits, save them on the phone, and match each GPS fix to the nearest road
/// locally. Direction of travel is used so a freeway overpass or a parallel frontage
/// road doesn't win just because it's close. Roads without a posted limit fall back to
/// the usual California default for that kind of road, marked as estimated.
@MainActor
final class SpeedLimitService {
    struct Limit: Equatable {
        var mps: Double
        var estimated: Bool
        var road: String
    }

    // MARK: Tiles

    private struct Road: Codable, Sendable {
        let hw: String
        let name: String
        let mps: Double
        let est: Bool
        let oneway: Bool
        let lat: [Double]
        let lng: [Double]
    }

    private struct TileKey: Hashable, Sendable {
        let y: Int, x: Int
        static let size = 0.04
        init(_ c: CLLocationCoordinate2D) { y = Int(floor(c.latitude / Self.size)); x = Int(floor(c.longitude / Self.size)) }
        init(y: Int, x: Int) { self.y = y; self.x = x }
        var file: String { "\(y)_\(x).json" }
        var bbox: (s: Double, w: Double, n: Double, e: Double) {
            (Double(y) * Self.size, Double(x) * Self.size, Double(y + 1) * Self.size, Double(x + 1) * Self.size)
        }
    }

    private var tiles: [TileKey: [Road]] = [:]
    private var loading: Set<TileKey> = []
    private var failedAt: [TileKey: Date] = [:]
    private var last: Limit?

    /// "looking" while the first map tile downloads, "ready" once roads are loaded, "offline" if the servers can't be reached.
    private(set) var status: String = "idle"

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("speed-tiles")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Same call shape as before: feed every fix; `onResult` fires when the limit changes.
    func update(for loc: CLLocation, speed: Double, onResult: @escaping (Limit?) -> Void) {
        let key = TileKey(loc.coordinate)
        ensureTile(key, then: { [weak self] in
            // Re-match as soon as the tile you're in arrives.
            guard let self else { return }
            let l = self.match(loc, speed: speed)
            if l != self.last { self.last = l; onResult(l) }
        })
        prefetchNeighbors(of: loc.coordinate)
        guard tiles[key] != nil else { return }
        let l = match(loc, speed: speed)
        if l != last { last = l; onResult(l) }
    }

    func reset() { last = nil }

    private func ensureTile(_ key: TileKey, then: (() -> Void)? = nil) {
        if tiles[key] != nil || loading.contains(key) { return }
        if let f = failedAt[key], Date().timeIntervalSince(f) < 20 { return }
        // From disk first (your usual area loads instantly), refreshed after 30 days.
        let url = Self.dir.appendingPathComponent(key.file)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mod = attrs[.modificationDate] as? Date, Date().timeIntervalSince(mod) < 30 * 86400,
           let data = try? Data(contentsOf: url), let roads = try? JSONDecoder().decode([Road].self, from: data) {
            tiles[key] = roads
            status = "ready"
            then?()
            return
        }
        loading.insert(key)
        if tiles.isEmpty { status = "looking" }
        Task {
            let roads = await Self.download(key)
            loading.remove(key)
            if let roads {
                tiles[key] = roads
                status = "ready"
                if let data = try? JSONEncoder().encode(roads) { try? data.write(to: url, options: .atomic) }
                then?()
            } else {
                failedAt[key] = Date()
                if tiles.isEmpty { status = "offline" }
            }
        }
    }

    /// Load the 8 surrounding tiles when you're near an edge, one at a time.
    private func prefetchNeighbors(of c: CLLocationCoordinate2D) {
        guard loading.isEmpty else { return }
        let k = TileKey(c)
        let fy = c.latitude / TileKey.size - Double(k.y), fx = c.longitude / TileKey.size - Double(k.x)
        var wanted: [TileKey] = []
        let dy = fy < 0.3 ? -1 : (fy > 0.7 ? 1 : 0), dx = fx < 0.3 ? -1 : (fx > 0.7 ? 1 : 0)
        if dy != 0 { wanted.append(TileKey(y: k.y + dy, x: k.x)) }
        if dx != 0 { wanted.append(TileKey(y: k.y, x: k.x + dx)) }
        if dy != 0 && dx != 0 { wanted.append(TileKey(y: k.y + dy, x: k.x + dx)) }
        if let next = wanted.first(where: { tiles[$0] == nil }) { ensureTile(next) }
    }

    // MARK: Matching

    private func match(_ loc: CLLocation, speed: Double) -> Limit? {
        let c = loc.coordinate
        let k = TileKey(c)
        let course = loc.course >= 0 && speed > 3 ? loc.course : -1
        var best: (score: Double, road: Road)?
        let mPerLat = 111_320.0, mPerLng = 111_320.0 * cos(c.latitude * .pi / 180)
        for ty in (k.y - 1)...(k.y + 1) {
            for tx in (k.x - 1)...(k.x + 1) {
                guard let roads = tiles[TileKey(y: ty, x: tx)] else { continue }
                for r in roads {
                    guard r.lat.count > 1 else { continue }
                    for i in 0..<(r.lat.count - 1) {
                        // Local flat coordinates in meters around the fix.
                        let ax = (r.lng[i] - c.longitude) * mPerLng, ay = (r.lat[i] - c.latitude) * mPerLat
                        let bx = (r.lng[i + 1] - c.longitude) * mPerLng, by = (r.lat[i + 1] - c.latitude) * mPerLat
                        let vx = bx - ax, vy = by - ay
                        let len2 = vx * vx + vy * vy
                        guard len2 > 0.01 else { continue }
                        // Quick reject: segment bounding box farther than 40 m.
                        if min(ax, bx) > 40 || max(ax, bx) < -40 || min(ay, by) > 40 || max(ay, by) < -40 { continue }
                        let t = max(0, min(1, -(ax * vx + ay * vy) / len2))
                        let px = ax + t * vx, py = ay + t * vy
                        let d = (px * px + py * py).squareRoot()
                        guard d < 35 else { continue }
                        var score = d
                        if course >= 0 {
                            let segBearing = atan2(vx, vy) * 180 / .pi   // 0 = north
                            var diff = abs((segBearing - course).truncatingRemainder(dividingBy: 360))
                            if diff > 180 { diff = 360 - diff }
                            if !r.oneway { diff = min(diff, 180 - diff) }
                            score += diff > 40 ? 60 : diff * 0.3
                        }
                        // Fast → favor bigger roads; slow → don't.
                        if speed > 22 && (r.hw == "residential" || r.hw == "service") { score += 25 }
                        if best == nil || score < best!.score { best = (score, r) }
                    }
                }
            }
        }
        guard let b = best?.road else { return nil }
        return Limit(mps: b.mps, estimated: b.est, road: b.name)
    }

    // MARK: Download

    nonisolated private static let roadTypes = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link|living_street"

    /// California defaults (mph) when a road has no posted limit in the map data.
    nonisolated private static let defaultMph: [String: Double] = [
        "motorway": 65, "trunk": 55, "motorway_link": 45, "trunk_link": 40, "primary": 45, "primary_link": 35,
        "secondary": 40, "secondary_link": 30, "tertiary": 35, "tertiary_link": 25, "unclassified": 30,
        "residential": 25, "living_street": 15]

    nonisolated private static let servers = ["https://overpass-api.de/api/interpreter",
                                  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
                                  "https://overpass.kumi.systems/api/interpreter"]

    nonisolated private static func download(_ key: TileKey) async -> [Road]? {
        let b = key.bbox
        let q = "[out:json][timeout:60];way[highway~\"^(\(roadTypes))$\"](\(b.s),\(b.w),\(b.n),\(b.e));out tags geom;"
        // Ask all servers at once; first good answer wins.
        return await withTaskGroup(of: [Road]?.self) { group in
            for s in servers { group.addTask { await fetch(server: s, query: q) } }
            for await r in group where r != nil {
                group.cancelAll()
                return r
            }
            return nil
        }
    }

    nonisolated private static func fetch(server: String, query: String) async -> [Road]? {
        guard let url = URL(string: server) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 75)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Roamr/1.0 (iOS route tracker; personal use)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        req.httpBody = Data("data=\(encoded)".utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = obj["elements"] as? [[String: Any]] else { return nil }
        return elements.compactMap { e in
            guard let tags = e["tags"] as? [String: String], let hw = tags["highway"],
                  let geom = e["geometry"] as? [[String: Double]], geom.count > 1 else { return nil }
            let name = tags["ref"] ?? tags["name"] ?? hw.replacingOccurrences(of: "_", with: " ").capitalized
            let oneway = tags["oneway"] == "yes" || hw == "motorway" || hw.hasSuffix("_link") && tags["oneway"] != "no"
            var mps: Double, est: Bool
            if let raw = tags["maxspeed"], let v = parse(raw) { mps = v; est = false }
            else if let mph = defaultMph[hw] { mps = mph * 0.44704; est = true }
            else { return nil }
            return Road(hw: hw, name: name, mps: mps, est: est, oneway: oneway,
                        lat: geom.compactMap { $0["lat"] }, lng: geom.compactMap { $0["lon"] })
        }
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
