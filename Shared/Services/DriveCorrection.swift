import Foundation
import CoreLocation

struct TrimmedDrive {
    let route: [RoutePoint]
    let distanceM: Double
    let averageSpeedMPS: Double
    let elevationGainM: Double
    let maxSpeedMPS: Double
}

enum DriveCorrection {
    /// Returns nil unless there are at least two GPS points with real timestamps.
    static func trim(_ points: [RoutePoint], start: Date, end: Date) -> TrimmedDrive? {
        guard end > start, points.count >= 2,
              points.allSatisfy({ $0.t.isFinite && $0.t > 0 }) else { return nil }

        let sorted = points.sorted { $0.t < $1.t }
        let lower = start.timeIntervalSince1970
        let upper = end.timeIntervalSince1970
        var kept = sorted.filter { $0.t >= lower && $0.t <= upper }

        if let boundary = interpolatedPoint(in: sorted, at: lower), !kept.contains(where: { $0.t == lower }) {
            kept.insert(boundary, at: 0)
        }
        if let boundary = interpolatedPoint(in: sorted, at: upper), !kept.contains(where: { $0.t == upper }) {
            kept.append(boundary)
        }
        kept.sort { $0.t < $1.t }
        guard kept.count >= 2 else { return nil }

        var distance = 0.0
        var elevationGain = 0.0
        var maxSpeed = 0.0
        for pair in zip(kept, kept.dropFirst()) {
            let a = pair.0, b = pair.1
            let meters = CLLocation(latitude: a.lat, longitude: a.lng)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
            distance += meters
            if a.alt.isFinite && b.alt.isFinite { elevationGain += max(0, b.alt - a.alt) }
            let dt = b.t - a.t
            if dt > 0 { maxSpeed = max(maxSpeed, meters / dt) }
        }
        let seconds = max(1, end.timeIntervalSince(start))
        return TrimmedDrive(route: kept, distanceM: distance, averageSpeedMPS: distance / seconds,
                           elevationGainM: elevationGain, maxSpeedMPS: maxSpeed)
    }

    private static func interpolatedPoint(in points: [RoutePoint], at t: Double) -> RoutePoint? {
        guard let pair = zip(points, points.dropFirst()).first(where: { $0.0.t <= t && t <= $0.1.t }),
              pair.1.t > pair.0.t else { return nil }
        let a = pair.0, b = pair.1
        let f = (t - a.t) / (b.t - a.t)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return RoutePoint(lat: mix(a.lat, b.lat), lng: mix(a.lng, b.lng), alt: mix(a.alt, b.alt), t: t,
                          speed: mix(a.speed, b.speed), limit: a.limit > 0 && b.limit > 0 ? mix(a.limit, b.limit) : -1)
    }
}
