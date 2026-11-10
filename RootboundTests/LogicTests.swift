import XCTest
import CoreLocation
@testable import Rootbound

final class GeoTests: XCTestCase {
    func testPlainCoordinates() {
        let c = Geo.parseCoordinates("37.2872, -121.9500")
        XCTAssertEqual(c?.latitude ?? 0, 37.2872, accuracy: 1e-6)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-6)
    }

    func testAppleMapsLink() {
        let c = Geo.parseCoordinates("https://maps.apple.com/?ll=37.28,-121.95&q=Dropped%20Pin")
        XCTAssertEqual(c?.latitude ?? 0, 37.28, accuracy: 1e-6)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-6)
    }

    func testGoogleMapsLinks() {
        XCTAssertEqual(Geo.parseCoordinates("https://www.google.com/maps/@37.2801,-121.9502,17z")?.latitude ?? 0, 37.2801, accuracy: 1e-6)
        XCTAssertEqual(Geo.parseCoordinates("https://maps.google.com/?q=37.1,-122.2")?.longitude ?? 0, -122.2, accuracy: 1e-6)
        XCTAssertEqual(Geo.parseCoordinates("https://www.google.com/maps/search/?api=1&query=37.5%2C-122.1")?.latitude ?? 0, 37.5, accuracy: 1e-6)
    }

    func testDMS() {
        let c = Geo.parseCoordinates("37°17'13.9\"N 121°57'00.0\"W")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.latitude ?? 0, 37.28719, accuracy: 1e-4)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-4)
    }

    func testRejectsJunk() {
        XCTAssertNil(Geo.parseCoordinates("https://maps.app.goo.gl/AbCdEf"))
        XCTAssertNil(Geo.parseCoordinates("hello"))
        XCTAssertNil(Geo.parseCoordinates("0, 0"))
        XCTAssertNil(Geo.parseCoordinates("95, 10"))
    }
}

final class DriveCorrectionTests: XCTestCase {
    func testTrimsTimestampedRouteAndInterpolatesCutBoundaries() {
        let points = [
            RoutePoint(lat: 0, lng: 0, alt: 10, t: 100),
            RoutePoint(lat: 0, lng: 0.001, alt: 12, t: 200),
            RoutePoint(lat: 0, lng: 0.002, alt: 11, t: 300),
            RoutePoint(lat: 0, lng: 0.003, alt: 14, t: 400),
        ]
        let result = DriveCorrection.trim(points, start: Date(timeIntervalSince1970: 150), end: Date(timeIntervalSince1970: 350))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.route.count, 4)
        XCTAssertEqual(result?.route.first?.t ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(result?.route.last?.t ?? 0, 350, accuracy: 0.001)
        XCTAssertEqual(result?.distanceM ?? 0, 222, accuracy: 3)
        XCTAssertEqual(result?.averageSpeedMPS ?? 0, (result?.distanceM ?? 0) / 200, accuracy: 0.001)
    }

    func testOlderRouteWithoutTimestampsCannotBeTrimmed() {
        let points = [RoutePoint(lat: 0, lng: 0, t: 0), RoutePoint(lat: 0, lng: 0.001, t: 0)]
        XCTAssertNil(DriveCorrection.trim(points, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)))
    }

    func testInvalidTimeRangeCannotBeTrimmed() {
        let points = [RoutePoint(lat: 0, lng: 0, t: 100), RoutePoint(lat: 0, lng: 0.001, t: 200)]
        XCTAssertNil(DriveCorrection.trim(points, start: Date(timeIntervalSince1970: 200), end: Date(timeIntervalSince1970: 100)))
    }
}

final class GameTests: XCTestCase {
    func testLevelCurve() {
        XCTAssertEqual(GameEngine.level(for: 0).level, 1)
        XCTAssertEqual(GameEngine.level(for: 149).level, 1)
        XCTAssertEqual(GameEngine.level(for: 150).level, 2)
        XCTAssertEqual(GameEngine.level(for: 450).level, 3)
        let l = GameEngine.level(for: 600)
        XCTAssertEqual(l.level, 3)
        XCTAssertEqual(l.xpIntoLevel, 150)
        XCTAssertEqual(l.xpForNext, 450)
        XCTAssertEqual(GameEngine.level(for: 1_000_000).title, "Ancient One")
    }

    private func hug(daysAgo: Int, tree: UUID = UUID(), minutes: Double = 12, barefoot: Bool = false) -> Hug {
        let h = Hug()
        h.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        h.treeID = tree
        h.durationMin = minutes
        h.barefoot = barefoot
        return h
    }

    func testStreaks() {
        let hugs = [hug(daysAgo: 0), hug(daysAgo: 1), hug(daysAgo: 2), hug(daysAgo: 5)]
        XCTAssertEqual(GameEngine.currentStreak(hugs), 3)
        XCTAssertEqual(GameEngine.bestStreak(hugs), 3)
        XCTAssertEqual(GameEngine.currentStreak([hug(daysAgo: 1), hug(daysAgo: 2)]), 2, "yesterday still counts")
        XCTAssertEqual(GameEngine.currentStreak([hug(daysAgo: 3)]), 0)
        XCTAssertEqual(GameEngine.currentStreak([]), 0)
    }

    func testXPRewardsNewTreeAndBreathwork() {
        let tree = UUID()
        let first = hug(daysAgo: 0, tree: tree, minutes: 12, barefoot: true)
        let xp1 = GameEngine.xp(for: first, existing: [])
        XCTAssertTrue(xp1.lines.contains { $0.0 == "New tree friend" })
        XCTAssertTrue(xp1.lines.contains { $0.0 == "Barefoot grounding" })
        XCTAssertEqual(xp1.lines.first { $0.0.hasPrefix("Breathwork") }?.1, 60)
        let second = hug(daysAgo: 0, tree: tree, minutes: 0)
        let xp2 = GameEngine.xp(for: second, existing: [first])
        XCTAssertFalse(xp2.lines.contains { $0.0 == "New tree friend" })
        XCTAssertGreaterThan(xp1.total, xp2.total)
    }

    func testLeafDropIsStablePerHug() {
        let h = hug(daysAgo: 0)
        let a = GameEngine.rollLeaf(for: h).id
        for _ in 0..<5 { XCTAssertEqual(GameEngine.rollLeaf(for: h).id, a) }
        XCTAssertNotNil(LeafType.find(a))
    }

    func testLeafOddsAreSane() {
        var counts: [Rarity: Int] = [:]
        for _ in 0..<4000 { counts[GameEngine.rollLeaf(for: hug(daysAgo: 0)).rarity, default: 0] += 1 }
        XCTAssertGreaterThan(counts[.common] ?? 0, counts[.rare] ?? 0)
        XCTAssertGreaterThan(counts[.rare] ?? 0, counts[.epic] ?? 0)
        XCTAssertGreaterThan(counts[.epic] ?? 0, counts[.legendary] ?? 0)
        XCTAssertGreaterThan(counts[.legendary] ?? 0, 0)
    }

    func testBadgesUnlock() {
        let tree = UUID()
        let hugs = (0..<3).map { hug(daysAgo: $0, tree: tree, barefoot: true) }
        let badges = GameEngine.badges(hugs: hugs, activities: [])
        func earned(_ id: String) -> Bool { badges.first { $0.id == id }?.earned ?? false }
        XCTAssertTrue(earned("first-hug"))
        XCTAssertTrue(earned("barefoot"))
        XCTAssertTrue(earned("same-3"))
        XCTAssertTrue(earned("streak-3"))
        XCTAssertTrue(earned("twelve"))
        XCTAssertFalse(earned("hugs-25"))
        XCTAssertEqual(Set(badges.map(\.id)).count, badges.count, "badge ids must be unique")
    }
}

final class TrackingTests: XCTestCase {
    func testRoutePointSurvivesUnknownAltitude() throws {
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122), altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date())
        let p = RoutePoint(loc)
        XCTAssertTrue(p.alt.isNaN)
        let data = try JSONEncoder().encode([p])
        let back = try JSONDecoder().decode([RoutePoint].self, from: data)
        XCTAssertEqual(back.first?.lat, 37)
        XCTAssertTrue(back.first?.alt.isNaN ?? false)
    }

    func testSimplifyKeepsEnds() {
        let pts = (0..<10_000).map { i in
            RoutePoint(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37 + Double(i) * 1e-5, longitude: -122),
                                  altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                                  timestamp: Date(timeIntervalSince1970: Double(i))))
        }
        let s = RouteTracker.simplify(pts, maxCount: 4000)
        XCTAssertEqual(s.count, 4000)
        XCTAssertEqual(s.first, pts.first)
        XCTAssertEqual(s.last, pts.last)
        XCTAssertEqual(RouteTracker.simplify(Array(pts.prefix(10)), maxCount: 4000).count, 10)
    }

    func testFormatting() {
        UserDefaults.standard.set(false, forKey: "useMetric")
        XCTAssertEqual(Format.distance(1609.344), "1.00 mi")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.duration(65), "1:05")
        XCTAssertEqual(Format.paceOrSpeed(distance: 1609.344, seconds: 480, kind: .run), "8:00 /mi")
        XCTAssertEqual(Format.minutes(12), "12 min")
        XCTAssertEqual(Format.minutes(75), "1h 15m")
    }
}

final class SplitTests: XCTestCase {
    func testSplitBoundaries() {
        let mile = 1609.344
        XCTAssertEqual(SplitAnnouncer.splitsCrossed(previous: 1600, current: 1610, unit: mile), [1])
        XCTAssertEqual(SplitAnnouncer.splitsCrossed(previous: 1610, current: 1700, unit: mile), [])
        XCTAssertEqual(SplitAnnouncer.splitsCrossed(previous: 900, current: 3300, unit: 1000), [1, 2, 3])
        XCTAssertEqual(SplitAnnouncer.splitsCrossed(previous: 500, current: 400, unit: 1000), [])
    }

    func testSpokenPhrase() {
        XCTAssertEqual(SplitAnnouncer.phrase(split: 2, metric: false, splitTime: 581, total: 1143),
                       "Mile 2. Split 9 minutes 41 seconds. Total 19 minutes 3 seconds.")
        XCTAssertEqual(SplitAnnouncer.spoken(3720), "1 hour 2 minutes")
        XCTAssertEqual(SplitAnnouncer.spoken(60), "1 minute")
    }

    func testAutoPauseThresholds() {
        XCTAssertNil(RouteTracker.autoPauseThreshold(for: .drive))
        XCTAssertEqual(RouteTracker.autoPauseThreshold(for: .run), 1.0)
        XCTAssertEqual(RouteTracker.autoPauseThreshold(for: .hike), 0.4)
    }
}

final class SpeciesTests: XCTestCase {
    func testMapsLabelsWordByWord() {
        let r = SpeciesGuesser.interpret([("palm_tree", 0.8), ("cashew", 0.6), ("tree", 0.9)])
        XCTAssertEqual(r.guesses.first?.name, "Palm")
        XCTAssertFalse(r.guesses.contains { $0.name == "Ash" })
        XCTAssertTrue(r.looksLikeTree)
    }

    func testGenericTreeHasNoSpecies() {
        let r = SpeciesGuesser.interpret([("tree", 0.7), ("sky", 0.5)])
        XCTAssertTrue(r.guesses.isEmpty)
        XCTAssertTrue(r.looksLikeTree)
    }

    func testFactsMatchLoosely() {
        XCTAssertNotNil(TreeFacts.fact(for: "Coast Live Oak"))
        XCTAssertNotNil(TreeFacts.fact(for: "Giant Sequoia"))
        XCTAssertNil(TreeFacts.fact(for: ""))
    }

    /// Prints the classifier's plant-ish labels so the species map can be checked against them.
    func testListClassifierLabels() {
        let labels = SpeciesGuesser.supportedLabels()
        let plant = labels.filter { l in
            ["tree", "palm", "oak", "maple", "pine", "conifer", "birch", "willow", "redwood", "sequoia", "cypress", "cedar",
             "fir", "spruce", "blossom", "plant", "forest", "eucalyptus", "bonsai", "bamboo", "cactus", "fig", "olive",
             "citrus", "ginkgo", "magnolia", "leaf", "bark", "wood"].contains { l.contains($0) }
        }
        print("CLASSIFIER_LABELS total=\(labels.count) plant=\(plant.joined(separator: ","))")
    }
}

final class LaneChangeTests: XCTestCase {
    /// Feeds yaw-rate samples at 20 Hz; returns detected events.
    private func run(_ yaw: (Double) -> Double, seconds: Double, speed: Double = 28, course: (Double) -> Double = { _ in 90 }) -> [LaneChangeDetector.Event] {
        var d = LaneChangeDetector()
        var out: [LaneChangeDetector.Event] = []
        var t = 0.0
        while t < seconds {
            if let e = d.add(t: t, yawRate: yaw(t), speed: speed, course: course(t)) { out.append(e) }
            t += 0.05
        }
        return out
    }

    func testQuickLeftLaneChangeIsDetected() {
        // Left swerve 1–2 s, right swerve 2–3 s, heading unchanged.
        let events = run({ t in t >= 1 && t < 2 ? 0.12 : (t >= 2 && t < 3 ? -0.12 : 0) }, seconds: 6)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.left, true)
    }

    func testRightLaneChangeIsDetected() {
        let events = run({ t in t >= 1 && t < 2.2 ? -0.1 : (t >= 2.2 && t < 3.4 ? 0.1 : 0) }, seconds: 6)
        XCTAssertEqual(events.first?.left, false)
    }

    func testCurveIsNotALaneChange() {
        // One long yaw one way while the GPS course swings 40°.
        let events = run({ t in t >= 1 && t < 5 ? 0.15 : 0 }, seconds: 7, course: { t in 90 + min(40, max(0, (t - 1) * 10)) })
        XCTAssertTrue(events.isEmpty)
    }

    func testSlowTrafficIsIgnored() {
        let events = run({ t in t >= 1 && t < 2 ? 0.12 : (t >= 2 && t < 3 ? -0.12 : 0) }, seconds: 6, speed: 5)
        XCTAssertTrue(events.isEmpty)
    }

    func testNoiseIsIgnored() {
        let events = run({ t in 0.02 * sin(t * 13) }, seconds: 20)
        XCTAssertTrue(events.isEmpty)
    }
}

final class RoadLaneTests: XCTestCase {
    /// Cycloid lane change: W meters sideways in T seconds starting at t0 (+ = left).
    private func laneChangeYaw(_ t: Double, t0: Double, T: Double, W: Double, v: Double) -> Double {
        guard t >= t0, t <= t0 + T else { return 0 }
        return W / (v * T) * (2 * .pi / T) * sin(2 * .pi * (t - t0) / T)
    }

    /// 20 Hz gyro + 1 Hz GPS cross-track (centered on 0 before, `shiftAfter` after `shiftAt`).
    private func run(seconds: Double, v: Double = 30, curvature: (Double) -> Double,
                     extraYaw: (Double) -> Double, shiftAt: Double = .infinity, shiftAfter: Double = 0) -> [LaneChangeDetector.Event] {
        var d = RoadLaneDetector()
        var out: [LaneChangeDetector.Event] = []
        var t = 0.0, nextFix = 0.0
        while t < seconds {
            let k = curvature(t)
            if let e = d.add(RoadLaneDetector.Sample(t: t, yawRate: v * k + extraYaw(t) + 0.004, speed: v,
                                                     curvature: k, curvatureWide: k, headingError: 0)) { out.append(e) }
            if t >= nextFix {
                if let e = d.addFix(t: t, crossTrack: t > shiftAt ? shiftAfter : 0, accuracy: 6) { out.append(e) }
                nextFix += 1
            }
            t += 0.05
        }
        return out
    }

    private func bend(_ t: Double) -> Double {
        if t > 10 && t < 15 { return (t - 10) / 5 / 500 }
        if t >= 15 && t < 30 { return 1.0 / 500 }
        if t >= 30 && t < 35 { return (35 - t) / 5 / 500 }
        return 0
    }

    func testSteadyCurveIsNotALaneChange() {
        XCTAssertTrue(run(seconds: 45, curvature: bend, extraYaw: { _ in 0 }).isEmpty)
    }

    func testStraightRoadLaneChangeCountsOnce() {
        let e = run(seconds: 30, curvature: { _ in 0 }, extraYaw: { self.laneChangeYaw($0, t0: 10, T: 4, W: 3.6, v: 30) })
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.first?.left, true)
        XCTAssertEqual(e.first?.quick, false)
    }

    func testLaneChangeInACurveNeedsGPSToAgree() {
        let yaw: (Double) -> Double = { self.laneChangeYaw($0, t0: 20, T: 3, W: -3.6, v: 30) }
        XCTAssertEqual(run(seconds: 35, curvature: bend, extraYaw: yaw, shiftAt: 23.5, shiftAfter: -3.5).count, 1)
        XCTAssertTrue(run(seconds: 35, curvature: bend, extraYaw: yaw).isEmpty)
    }

    func testCurvatureSign() {
        // North then bending west (left).
        var pts: [LaneMath.Vec] = []
        for i in 0..<40 { let a = Double(i) * 0.02; pts.append(LaneMath.Vec(x: -300 * (1 - cos(a)), y: 300 * sin(a))) }
        let line = LaneMath.Polyline(points: pts)
        XCTAssertGreaterThan(LaneMath.curvature(line, around: line.length / 2, halfSpan: 40), 0)
        XCTAssertEqual(LaneMath.signedAngle(350, 10), -20, accuracy: 1e-9)
    }
}
