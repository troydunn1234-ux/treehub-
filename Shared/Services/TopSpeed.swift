import Foundation
import CoreLocation

/// Roamr's top speed, worked out the same way for a live recording and for a saved route.
///
/// GPS throws the odd spike (a fix that jumps 200 m, a reacquired signal reporting 90 mph on a walk), and a plain
/// "fastest reading" picks those up. Here a reading only counts when:
/// - the fix is sharp enough (horizontal accuracy known and within 25–30 m),
/// - the speed is trustworthy: the GPS's own Doppler speed when its speed accuracy is good, otherwise distance over
///   time between two sharp fixes at least 1 s apart (tiny time gaps are ignored),
/// - it's plausible for the kind of trip (a walk can't do 40 mph) and isn't an impossible jump from the last reading,
/// - and it's sustained: the top speed is the highest *median* of a rolling ~5 s window (at least 3 readings),
///   so a single wild reading can't win.
enum TopSpeed {
    /// One GPS reading. `speedAccuracy` / `horizontalAccuracy` are nil when unknown (saved routes don't keep them);
    /// negative means the GPS said it's invalid. `speed` is -1 when unknown.
    struct Sample: Equatable {
        var t: Double
        var lat: Double
        var lng: Double
        var speed: Double
        var speedAccuracy: Double? = nil
        var horizontalAccuracy: Double? = nil

        init(t: Double, lat: Double, lng: Double, speed: Double, speedAccuracy: Double? = nil, horizontalAccuracy: Double? = nil) {
            self.t = t; self.lat = lat; self.lng = lng; self.speed = speed
            self.speedAccuracy = speedAccuracy; self.horizontalAccuracy = horizontalAccuracy
        }

        init(_ loc: CLLocation) {
            self.init(t: loc.timestamp.timeIntervalSince1970, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                      speed: loc.speed, speedAccuracy: loc.speedAccuracy, horizontalAccuracy: loc.horizontalAccuracy)
        }

        init(_ p: RoutePoint) {
            self.init(t: p.t, lat: p.lat, lng: p.lng, speed: p.speed.isFinite ? p.speed : -1)
        }
    }

    private static let mph = 0.44704

    /// Fastest believable speed for a kind of trip (m/s).
    static func cap(for kind: ActivityKind) -> Double {
        switch kind {
        case .walk, .hike: return 15 * mph
        case .run: return 25 * mph
        case .bike: return 60 * mph
        case .drive: return 140 * mph
        }
    }

    /// Biggest believable change in speed per second (m/s²), speeding up or braking.
    static func maxAccel(for kind: ActivityKind) -> Double {
        switch kind {
        case .drive: return 8      // ~0.8 g
        case .bike: return 4
        case .walk, .run, .hike: return 4
        }
    }

    /// Fixes fuzzier than this (metres) are ignored.
    static func maxHorizontalAccuracy(for kind: ActivityKind) -> Double { kind == .drive ? 30 : 25 }

    static let window: Double = 5        // seconds of readings the median is taken over
    static let sparseWindow: Double = 15 // on a thinned-out saved route, 3 readings may span up to this
    static let minReadings = 3

    /// Feeds readings one at a time (the live recorder) and keeps the top speed so far.
    struct Accumulator {
        let kind: ActivityKind
        private(set) var top: Double
        private var lastFix: Sample?
        private var lastSpeed: (t: Double, v: Double)?
        private var recent: [(t: Double, v: Double)] = []

        init(kind: ActivityKind, top: Double = 0) {
            self.kind = kind
            self.top = max(0, top.isFinite ? top : 0)
        }

        mutating func add(_ s: Sample) {
            guard s.t.isFinite, s.lat.isFinite, s.lng.isFinite else { return }
            if let h = s.horizontalAccuracy, h < 0 || h > TopSpeed.maxHorizontalAccuracy(for: kind) { return }
            let prev = lastFix
            if let prev, s.t - prev.t < 0.5 { return }   // duplicate / tiny time gap
            lastFix = s

            guard let v = speed(of: s, after: prev), v.isFinite, v >= 0 else { return }
            guard v <= TopSpeed.cap(for: kind) else { return }
            if let last = lastSpeed {
                let dt = max(1, s.t - last.t)
                if abs(v - last.v) > TopSpeed.maxAccel(for: kind) * dt { return }
            }
            lastSpeed = (s.t, v)

            recent.append((s.t, v))
            recent.removeAll { $0.t < s.t - TopSpeed.sparseWindow }
            var w = recent.filter { $0.t >= s.t - TopSpeed.window }
            if w.count < TopSpeed.minReadings, recent.count >= TopSpeed.minReadings {
                w = Array(recent.suffix(TopSpeed.minReadings))
            }
            guard w.count >= TopSpeed.minReadings else { return }
            let sorted = w.map(\.v).sorted()
            top = max(top, sorted[(sorted.count - 1) / 2])   // lower median: a lone spike never wins
        }

        /// GPS speed when it's trustworthy, otherwise distance over time from the previous sharp fix.
        private func speed(of s: Sample, after prev: Sample?) -> Double? {
            if s.speed >= 0 {
                if let acc = s.speedAccuracy {
                    if acc >= 0 && acc <= max(2, s.speed * 0.2) { return s.speed }
                    // Invalid or loose speed accuracy: fall through to distance over time.
                } else {
                    return s.speed
                }
            }
            guard let prev else { return nil }
            let dt = s.t - prev.t
            guard dt >= 1, dt <= 30 else { return nil }
            let d = CLLocation(latitude: prev.lat, longitude: prev.lng).distance(from: CLLocation(latitude: s.lat, longitude: s.lng))
            return d / dt
        }
    }

    /// Top speed (m/s) of a run of readings; 0 when there aren't enough good ones.
    static func compute(from samples: [Sample], kind: ActivityKind) -> Double {
        var acc = Accumulator(kind: kind)
        for s in samples.sorted(by: { $0.t < $1.t }) { acc.add(s) }
        return acc.top
    }

    /// Top speed (m/s) of a saved route.
    static func compute(route: [RoutePoint], kind: ActivityKind) -> Double {
        compute(from: route.map(Sample.init), kind: kind)
    }

    /// A saved route has enough readings, close enough together, to recompute its top speed.
    static func routeIsDense(_ route: [RoutePoint]) -> Bool {
        guard route.count >= 20 else { return false }
        let gaps = zip(route.dropFirst(), route).map { $0.t - $1.t }.filter { $0 > 0 }.sorted()
        guard !gaps.isEmpty else { return false }
        return gaps[gaps.count / 2] <= 10
    }
}

extension Activity {
    /// Sets the kind and refreshes the top speed from the saved route for that kind (a walk can't keep a drive's
    /// top speed). Leaves the top speed alone when the route is too sparse to tell.
    func applyKind(_ k: ActivityKind) {
        guard k != kind else { return }
        kind = k
        let pts = route
        guard TopSpeed.routeIsDense(pts) else {
            if maxSpeed > TopSpeed.cap(for: k) { maxSpeed = TopSpeed.cap(for: k) }
            return
        }
        maxSpeed = TopSpeed.compute(route: pts, kind: k)
    }
}

/// Once per install: past trips whose top speed was a GPS spike get the cleaned-up top speed from their own route.
/// Only ever lowers the value, keeps the original in `rawMaxSpeed`, and skips trips without a dense enough route.
enum TopSpeedRepair {
    static let doneKey = "roamr.topSpeedRepair.v1"

    /// Smallest drop worth fixing (m/s, ~1 mph): smaller differences are just rounding between the two methods.
    static let minDrop = 0.45

    /// The corrected top speed for a trip, or nil to leave it as it is.
    static func corrected(maxSpeed: Double, route: [RoutePoint], kind: ActivityKind) -> Double? {
        guard maxSpeed.isFinite, maxSpeed > 0, TopSpeed.routeIsDense(route) else { return nil }
        let clean = TopSpeed.compute(route: route, kind: kind)
        guard clean > 0, clean < maxSpeed - minDrop else { return nil }
        return clean
    }

    /// The same from a trip's stored route bytes (`Activity.routeData`), so the decoding and checking can run off
    /// the main thread. Nil (leave the trip alone) when there's no route or it can't be read.
    static func corrected(maxSpeed: Double, routeData: Data?, kind: ActivityKind) -> Double? {
        guard maxSpeed.isFinite, maxSpeed > 0, let routeData,
              let route = try? JSONDecoder().decode([RoutePoint].self, from: routeData) else { return nil }
        return corrected(maxSpeed: maxSpeed, route: route, kind: kind)
    }

    /// Fixes the given trips in place. Returns how many changed. Safe to run more than once.
    @discardableResult
    static func repair(_ trips: [Activity]) -> Int {
        var changed = 0
        for a in trips where a.rawMaxSpeed == nil {
            guard let fixed = corrected(maxSpeed: a.maxSpeed, route: a.route, kind: a.kind) else { continue }
            a.rawMaxSpeed = a.maxSpeed
            a.maxSpeed = fixed
            changed += 1
        }
        return changed
    }
}
