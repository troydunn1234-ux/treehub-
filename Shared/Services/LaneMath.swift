import Foundation

/// Pure math for telling lane changes apart from curves in the road. No CoreLocation or
/// CoreMotion types, so it can be tested with made-up roads and maneuvers.
///
/// The idea: the phone's gyro sees how fast the truck is turning (yaw rate). On a curve the
/// road itself turns at speed × curvature, so subtracting that leaves the **residual** yaw:
/// how the truck turns relative to the road. Integrate the residual once and you get the
/// truck's heading relative to the road; integrate speed × that heading and you get how far
/// it moved sideways. A lane change is a sideways move of about one lane (2–6 m) that ends
/// pointing straight down the road again. A curve leaves the residual near zero, so it never
/// adds up to a sideways move.
enum LaneMath {
    struct Vec: Equatable { var x: Double; var y: Double }   // meters, x = east, y = north

    /// a − b in degrees, wrapped to -180..<180.
    static func signedAngle(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d >= 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }

    /// Yaw rate left over after removing the road's own turning (rad/s, + = left).
    static func residualYaw(yawRate: Double, speed: Double, curvature: Double) -> Double {
        yawRate - speed * curvature
    }

    /// A road as a line of points in travel order, measured by distance along it.
    struct Polyline {
        let points: [Vec]
        let cum: [Double]
        var length: Double { cum.last ?? 0 }

        init(points: [Vec]) {
            self.points = points
            var c = [0.0]
            for i in 1..<max(1, points.count) {
                let a = points[i - 1], b = points[i]
                c.append(c[i - 1] + ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot())
            }
            cum = c
        }

        /// Distance along the line for a fractional point index (segment i, fraction t → i + t).
        func locate(index pos: Double) -> Double? {
            guard points.count > 1 else { return nil }
            let i = max(0, min(points.count - 2, Int(pos.rounded(.down))))
            let f = max(0, min(1, pos - Double(i)))
            return cum[i] + f * (cum[i + 1] - cum[i])
        }

        private func segment(at s: Double) -> Int {
            var j = 0
            while j < points.count - 2 && cum[j + 1] <= s { j += 1 }
            return j
        }

        func point(at s: Double) -> Vec {
            guard points.count > 1 else { return points.first ?? Vec(x: 0, y: 0) }
            let ss = max(0, min(length, s))
            let j = segment(at: ss)
            let len = cum[j + 1] - cum[j]
            let f = len > 0 ? (ss - cum[j]) / len : 0
            let a = points[j], b = points[j + 1]
            return Vec(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }

        /// Compass bearing (0 = north, clockwise) of the road at distance s, smoothed over ±10 m.
        func bearing(at s: Double) -> Double {
            let a = point(at: s - 10), b = point(at: s + 10)
            var dx = b.x - a.x, dy = b.y - a.y
            if dx * dx + dy * dy < 0.25 {
                let j = segment(at: max(0, min(length, s)))
                dx = points[j + 1].x - points[j].x; dy = points[j + 1].y - points[j].y
            }
            let deg = atan2(dx, dy) * 180 / .pi
            return deg < 0 ? deg + 360 : deg
        }

        /// Signed distance of `p` from the road at distance s: + = left of the travel direction.
        func crossTrack(of p: Vec, at s: Double) -> Double {
            let j = segment(at: max(0, min(length, s)))
            let a = points[j], b = points[j + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0 else { return 0 }
            let q = point(at: s)
            let ox = p.x - q.x, oy = p.y - q.y
            return (dx * oy - dy * ox) / len
        }
    }

    /// Road curvature around distance s (rad/m, + = bending left), from the turn between the
    /// chord behind and the chord ahead. 0 when there isn't enough road on either side.
    static func curvature(_ line: Polyline, around s: Double, halfSpan h: Double) -> Double {
        let a = line.point(at: s - h), m = line.point(at: s), b = line.point(at: s + h)
        let d1 = ((m.x - a.x) * (m.x - a.x) + (m.y - a.y) * (m.y - a.y)).squareRoot()
        let d2 = ((b.x - m.x) * (b.x - m.x) + (b.y - m.y) * (b.y - m.y)).squareRoot()
        guard d1 > 10, d2 > 10 else { return 0 }
        let b1 = atan2(m.x - a.x, m.y - a.y) * 180 / .pi
        let b2 = atan2(b.x - m.x, b.y - m.y) * 180 / .pi
        // Compass bearings grow clockwise, so a left bend makes the bearing go down.
        return -signedAngle(b2, b1) * .pi / 180 / ((d1 + d2) / 2)
    }

    /// Integrates a residual-yaw trace: returns the heading relative to the road at the end (rad)
    /// and the sideways move (m, + = left). `baseline` (rad/s) is subtracted first to cancel gyro
    /// bias and any small error in the map's curvature.
    static func integrate(_ samples: [(t: Double, r: Double, v: Double)], baseline: Double) -> (psi: Double, dy: Double) {
        guard samples.count > 1 else { return (0, 0) }
        var psi = 0.0, dy = 0.0
        for k in 1..<samples.count {
            let dt = max(0, min(0.25, samples[k].t - samples[k - 1].t))
            psi += (samples[k].r - baseline) * dt
            dy += samples[k].v * sin(psi) * dt
        }
        return (psi, dy)
    }
}

/// Lane-change detector that works relative to the matched road. Feed it gyro samples
/// (`add`) with the road's curvature, and GPS fixes (`addFix`) with the cross-track offset.
/// Returns the same Event type as the motion-only fallback detector.
struct RoadLaneDetector {
    struct Sample {
        var t: Double
        var yawRate: Double          // rad/s, + = turning left
        var speed: Double            // m/s
        var curvature: Double        // road, rad/m, + = left (local)
        var curvatureWide: Double    // road, sharpest bend within ±150 m
        var headingError: Double?    // degrees, course − road bearing (nil when course unknown)
    }

    // Tuning
    var minSpeed = 6.7               // 15 mph
    var maxHeadingError = 25.0       // more than this vs the road = turn or ramp, not a lane change
    var lobePeak = 0.022             // rad/s of residual yaw needed in each half of the S
    var lobeMin = 0.3, lobeMax = 3.5
    var maxGap = 1.5                 // seconds between the two halves
    var minShift = 1.6, maxShift = 7.0
    var maxEndHeading = 0.07         // rad (~4°): must end up pointing down the road again
    var curvyK = 1.0 / 700           // tighter than a ~700 m radius = "curvy"
    var debounce = 3.0

    private struct Lobe { var sign: Int; var start: Double; var end: Double; var peak: Double }
    private struct Pending { var event: LaneChangeDetector.Event; var start: Double; var end: Double; var deadline: Double }

    private var buf: [(t: Double, r: Double, v: Double)] = []
    private var fixes: [(t: Double, xt: Double)] = []
    private var smoothed = 0.0
    private var current: Lobe?
    private var lastLobe: Lobe?
    private var lastEventT = -Double.infinity
    private var suppressedUntil = 0.0
    private var pending: Pending?

    /// Phone moved in the mount / was picked up: ignore a couple of seconds.
    mutating func handled(at t: Double) {
        suppressedUntil = t + 2
        current = nil; lastLobe = nil
    }

    /// A GPS fix's distance from the road centerline (only fixes accurate to 15 m count).
    mutating func addFix(t: Double, crossTrack: Double, accuracy: Double) -> LaneChangeDetector.Event? {
        if accuracy <= 15 {
            fixes.append((t, crossTrack))
            fixes.removeAll { t - $0.t > 20 }
        }
        return resolvePending(now: t)
    }

    mutating func add(_ s: Sample) -> LaneChangeDetector.Event? {
        let r = LaneMath.residualYaw(yawRate: s.yawRate, speed: s.speed, curvature: s.curvature)
        buf.append((s.t, r, s.speed))
        buf.removeAll { s.t - $0.t > 14 }
        smoothed = smoothed * 0.8 + r * 0.2   // ~0.25 s at 20 Hz: calms road vibration

        if let pendingEvent = resolvePending(now: s.t) { return pendingEvent }

        let offRoad: Bool
        if let he = s.headingError { offRoad = abs(he) > maxHeadingError } else { offRoad = false }
        if s.speed < minSpeed || s.t < suppressedUntil || offRoad {
            current = nil; lastLobe = nil
            if offRoad { pending = nil }
            return nil
        }

        let w = smoothed
        let sign = abs(w) < lobePeak * 0.35 ? 0 : (w > 0 ? 1 : -1)
        var finished: Lobe?
        if var c = current {
            if sign == c.sign {
                c.end = s.t; c.peak = max(c.peak, abs(w)); current = c
            } else {
                finished = c
                current = sign == 0 ? nil : Lobe(sign: sign, start: s.t, end: s.t, peak: abs(w))
            }
        } else if sign != 0 {
            current = Lobe(sign: sign, start: s.t, end: s.t, peak: abs(w))
        }

        guard let lobe = finished else { return nil }
        let dur = lobe.end - lobe.start
        guard lobe.peak >= lobePeak, dur >= lobeMin, dur <= lobeMax else { return nil }
        guard let first = lastLobe, first.sign == -lobe.sign, lobe.start - first.end <= maxGap else {
            lastLobe = lobe
            return nil
        }
        lastLobe = nil
        guard s.t - lastEventT >= debounce else { return nil }

        // Peaks roughly balanced (a real S, not a long sweep with a wobble).
        let ratio = max(first.peak, lobe.peak) / max(0.001, min(first.peak, lobe.peak))
        guard ratio <= 3 else { return nil }
        let total = lobe.end - first.start
        guard total >= 0.8, total <= 7 else { return nil }

        // Baseline: average residual over the few seconds before the maneuver.
        let before = buf.filter { $0.t >= first.start - 4 && $0.t < first.start - 0.3 }
        let baseline = before.isEmpty ? 0 : before.reduce(0) { $0 + $1.r } / Double(before.count)
        let window = buf.filter { $0.t >= first.start - 0.3 && $0.t <= lobe.end + 0.3 }
        let (psi, dy) = LaneMath.integrate(window, baseline: baseline)
        guard abs(psi) <= maxEndHeading, abs(dy) >= minShift, abs(dy) <= maxShift else { return nil }
        // The sideways move must go the way the first swerve pointed.
        guard (dy > 0) == (first.sign > 0) else { return nil }

        // Smoothing stretches the measured swerve by ~0.4 s, so 2.4 s measured ≈ a real change under 2 s.
        let event = LaneChangeDetector.Event(t: lobe.end, left: dy > 0, quick: total < 2.4 && s.speed > 20.1, speed: s.speed)
        let curvy = abs(s.curvatureWide) > curvyK
        if curvy {
            // On a bend, the map's curvature can be a little off, so ask for a stronger swerve
            // and wait for GPS to confirm the sideways move.
            guard min(first.peak, lobe.peak) >= lobePeak * 1.7 else { return nil }
            pending = Pending(event: event, start: first.start, end: lobe.end, deadline: lobe.end + 4)
            return nil
        }
        // Straight road: accept now unless GPS clearly says you went the other way.
        if let shift = gpsShift(start: first.start, end: lobe.end), abs(shift) > 2.5, (shift > 0) != event.left {
            return nil
        }
        lastEventT = s.t
        return event
    }

    /// Change in cross-track offset from before the maneuver to after it (m, + = moved left).
    private func gpsShift(start: Double, end: Double) -> Double? {
        let pre = fixes.filter { $0.t >= start - 4 && $0.t <= start }
        let post = fixes.filter { $0.t >= end + 0.5 && $0.t <= end + 4 }
        guard !pre.isEmpty, !post.isEmpty else { return nil }
        let a = pre.reduce(0) { $0 + $1.xt } / Double(pre.count)
        let b = post.reduce(0) { $0 + $1.xt } / Double(post.count)
        return b - a
    }

    private mutating func resolvePending(now: Double) -> LaneChangeDetector.Event? {
        guard let p = pending else { return nil }
        if let shift = gpsShift(start: p.start, end: p.end), abs(shift) >= 1.5, (shift > 0) == p.event.left {
            pending = nil
            lastEventT = now
            return p.event
        }
        if now > p.deadline { pending = nil }
        return nil
    }
}
