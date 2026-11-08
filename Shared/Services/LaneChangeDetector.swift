import Foundation

/// One lane change during a drive.
struct LaneChange: Codable, Hashable {
    var t: Double          // seconds since 1970
    var lat: Double
    var lng: Double
    var left: Bool         // moved into the lane on the left
    var speed: Double      // m/s
    var quick: Bool        // a fast "cut": whole swerve in under 2.5 s above ~45 mph
}

/// Spots lane changes from the phone's rotation. GPS can't see lanes (it's off by a car width
/// or more), but a lane change is a quick S-shaped swerve: the car yaws one way, then back the
/// other way, and ends up pointing the same direction. A curve or a turn yaws one way only.
///
/// Feed it yaw rate around gravity (rad/s, + = turning left), speed and GPS course.
/// Pure logic, so it can be unit tested with made-up swerves.
struct LaneChangeDetector {
    struct Event: Equatable { let t: Double; let left: Bool; let quick: Bool; let speed: Double }

    // Tuning
    var minSpeed = 11.0            // ~25 mph
    var lobePeak = 0.05            // rad/s needed in each half of the S
    var lobeMin = 0.35, lobeMax = 3.0
    var maxGap = 3.0               // seconds between the two halves
    var maxHeadingChange = 8.0     // degrees: more than this is a curve, not a lane change

    private struct Lobe { var sign: Int; var start: Double; var end: Double; var peak: Double }
    private var current: Lobe?
    private var lastLobe: Lobe?
    private var history: [(t: Double, course: Double)] = []
    private var suppressedUntil = 0.0
    private var smoothed = 0.0

    /// Ignore a couple of seconds after the phone itself was moved around (picked up, bumped).
    mutating func handled(at t: Double) {
        suppressedUntil = t + 2
        current = nil
        lastLobe = nil
    }

    mutating func add(t: Double, yawRate raw: Double, speed: Double, course: Double) -> Event? {
        smoothed = smoothed * 0.6 + raw * 0.4
        if course >= 0 {
            history.append((t, course))
            history.removeAll { t - $0.t > 10 }
        }
        guard speed >= minSpeed, t >= suppressedUntil else { current = nil; return nil }

        let w = smoothed
        let sign = abs(w) < lobePeak * 0.35 ? 0 : (w > 0 ? 1 : -1)
        var finished: Lobe?
        if var c = current {
            if sign == c.sign {
                c.end = t
                c.peak = max(c.peak, abs(w))
                current = c
            } else {
                finished = c
                current = sign == 0 ? nil : Lobe(sign: sign, start: t, end: t, peak: abs(w))
            }
        } else if sign != 0 {
            current = Lobe(sign: sign, start: t, end: t, peak: abs(w))
        }

        guard let lobe = finished else { return nil }
        let dur = lobe.end - lobe.start
        guard lobe.peak >= lobePeak, dur >= lobeMin, dur <= lobeMax else { return nil }
        if let first = lastLobe, first.sign == -lobe.sign, lobe.start - first.end <= maxGap, headingSteady(from: first.start - 1, to: lobe.end + 0.5) {
            lastLobe = nil
            // First swerve to the left (+) means moving into the left lane.
            return Event(t: lobe.end, left: first.sign > 0, quick: lobe.end - first.start < 2.5 && speed > 20, speed: speed)
        }
        lastLobe = lobe
        return nil
    }

    /// Net heading about the same before and after (a curve or turn changes it).
    private func headingSteady(from a: Double, to b: Double) -> Bool {
        guard let before = course(at: a), let after = course(at: b) ?? history.last?.course else { return true }
        var d = abs(after - before).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d <= maxHeadingChange
    }

    private func course(at t: Double) -> Double? {
        history.min { abs($0.t - t) < abs($1.t - t) }.flatMap { abs($0.t - t) < 2 ? $0.course : nil }
    }
}
