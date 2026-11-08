import SwiftUI
import CoreLocation

/// Colors a drive by how fast you went compared with the speed limit.
enum SpeedBand: Int {
    case slow, cruise, fast, over, wayOver

    var color: Color {
        switch self {
        case .slow: return Color(red: 0.25, green: 0.85, blue: 1.0)    // cyan
        case .cruise: return Color(red: 0.24, green: 1.0, blue: 0.58)  // neon green
        case .fast: return Color(red: 1.0, green: 0.86, blue: 0.2)     // yellow
        case .over: return Color(red: 1.0, green: 0.52, blue: 0.15)    // orange
        case .wayOver: return Color(red: 1.0, green: 0.2, blue: 0.32)  // red
        }
    }

    /// Thresholds in mph over the limit: up to 0 → cruise, 0–10 → fast, 10–20 → over, 20+ → way over.
    static func of(speed: Double, limit: Double) -> SpeedBand {
        guard speed >= 0 else { return .cruise }
        if limit > 0 {
            let overMph = (speed - limit) * 2.236936
            if overMph <= 0 { return speed < 6 ? .slow : .cruise }
            if overMph <= 10 { return .fast }
            if overMph <= 20 { return .over }
            return .wayOver
        }
        let mph = speed * 2.236936
        if mph < 25 { return .slow }
        if mph < 60 { return .cruise }
        if mph < 75 { return .fast }
        if mph < 90 { return .over }
        return .wayOver
    }
}

struct SpeedSegment: Identifiable {
    let id: Int
    let band: SpeedBand
    let coords: [CLLocationCoordinate2D]
}

struct OverZone: Identifiable {
    let id: Int
    let peak: CLLocationCoordinate2D
    let peakOverMph: Double
    let seconds: Double
}

enum SpeedZones {
    /// Splits a route into runs of the same band (each run shares its first point with the previous one).
    static func segments(_ pts: [RoutePoint]) -> [SpeedSegment] {
        guard pts.count > 1 else { return [] }
        var out: [SpeedSegment] = []
        var cur: [CLLocationCoordinate2D] = [pts[0].coordinate]
        var band = SpeedBand.of(speed: pts[1].speed, limit: pts[1].limit)
        for i in 1..<pts.count {
            let b = SpeedBand.of(speed: pts[i].speed, limit: pts[i].limit)
            if b != band && cur.count > 1 {
                out.append(SpeedSegment(id: out.count, band: band, coords: cur))
                cur = [cur.last!]
                band = b
            }
            cur.append(pts[i].coordinate)
        }
        if cur.count > 1 { out.append(SpeedSegment(id: out.count, band: band, coords: cur)) }
        return out
    }

    /// Stretches where you were more than 5 mph over a known limit for at least 4 seconds.
    static func overZones(_ pts: [RoutePoint]) -> [OverZone] {
        var zones: [OverZone] = []
        var start: Double?
        var peakIdx = -1
        var peak = 0.0
        func close(at t: Double) {
            if let s = start, t - s >= 4, peakIdx >= 0 {
                zones.append(OverZone(id: zones.count, peak: pts[peakIdx].coordinate, peakOverMph: peak, seconds: t - s))
            }
            start = nil; peakIdx = -1; peak = 0
        }
        for (i, p) in pts.enumerated() {
            let over = p.limit > 0 && p.speed >= 0 ? (p.speed - p.limit) * 2.236936 : -1
            if over > 5 {
                if start == nil { start = p.t }
                if over > peak { peak = over; peakIdx = i }
            } else {
                close(at: p.t)
            }
        }
        close(at: pts.last?.t ?? 0)
        return zones
    }
}
