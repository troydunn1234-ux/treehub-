import XCTest
import CoreLocation
@testable import Roamr

/// Spike-free top speed (TopSpeed), the one-time repair of past trips, and Roamr's kind order.
/// All routes are made up: a straight line north from an arbitrary point.
final class TopSpeedTests: XCTestCase {

    private let lat0 = 10.0, lng0 = 20.0, t0 = 1_700_000_000.0
    private let metresPerDegree = 111_195.0

    /// Readings every `dt` seconds along a straight line, at the given speeds (m/s).
    private func samples(_ speeds: [Double], dt: Double = 1, hAcc: Double? = 5, sAcc: Double? = 0.5,
                         reportSpeed: Bool = true) -> [TopSpeed.Sample] {
        var lat = lat0
        var out: [TopSpeed.Sample] = []
        for (i, v) in speeds.enumerated() {
            if i > 0 { lat += v * dt / metresPerDegree }
            out.append(TopSpeed.Sample(t: t0 + Double(i) * dt, lat: lat, lng: lng0, speed: reportSpeed ? v : -1,
                                       speedAccuracy: reportSpeed ? sAcc : -1, horizontalAccuracy: hAcc))
        }
        return out
    }

    private func route(_ speeds: [Double], dt: Double = 1, reportSpeed: Bool = true) -> [RoutePoint] {
        samples(speeds, dt: dt, reportSpeed: reportSpeed).map { s in
            RoutePoint(CLLocation(coordinate: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lng), altitude: 10,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: s.speed,
                                  timestamp: Date(timeIntervalSince1970: s.t)))
        }
    }

    // MARK: Spikes

    func testSingleSpeedSpikeOnAWalkIsIgnored() {
        var speeds = Array(repeating: 1.4, count: 120)
        speeds[60] = 40   // the GPS briefly says ~90 mph
        XCTAssertEqual(TopSpeed.compute(from: samples(speeds), kind: .walk), 1.4, accuracy: 0.01)
    }

    func testPositionJumpWithoutGPSSpeedIsIgnored() {
        var s = samples(Array(repeating: 1.4, count: 120), reportSpeed: false)
        s[50].lat += 300 / metresPerDegree   // one fix 300 m off, then back
        let top = TopSpeed.compute(from: s, kind: .walk)
        XCTAssertGreaterThan(top, 1.2)
        XCTAssertLessThan(top, 1.7)
    }

    func testShortBurstOfSpikesOnADriveIsIgnored() {
        var speeds = Array(repeating: 30.0, count: 300)
        speeds[100] = 70; speeds[101] = 68      // two wild readings in a row
        speeds[200] = 55
        XCTAssertEqual(TopSpeed.compute(from: samples(speeds), kind: .drive), 30, accuracy: 0.01)
    }

    func testRealAccelerationIsKept() {
        // 20 → 36 m/s at 2 m/s², held for 20 s, then back down.
        let speeds = Array(repeating: 20.0, count: 30) + (1...8).map { 20 + Double($0) * 2 }
            + Array(repeating: 36.0, count: 20) + Array(repeating: 25.0, count: 30)
        XCTAssertEqual(TopSpeed.compute(from: samples(speeds), kind: .drive), 36, accuracy: 0.01)
    }

    func testTopMustBeSustained() {
        // One honest-looking 2 s burst to 10 m/s on a 3 m/s run doesn't count; 10 s at 5 m/s does.
        var speeds = Array(repeating: 3.0, count: 60) + Array(repeating: 5.0, count: 10) + Array(repeating: 3.0, count: 30)
        speeds[20] = 6; speeds[21] = 6
        XCTAssertEqual(TopSpeed.compute(from: samples(speeds), kind: .run), 5, accuracy: 0.01)
    }

    func testImplausibleForTheKindIsDropped() {
        // A "walk" at 20 m/s (45 mph) has no believable readings; a bike can't do 40 m/s (90 mph) either.
        XCTAssertEqual(TopSpeed.compute(from: samples(Array(repeating: 20, count: 60)), kind: .walk), 0)
        let bike = Array(repeating: 8.0, count: 60) + Array(repeating: 40.0, count: 10) + Array(repeating: 8.0, count: 10)
        XCTAssertEqual(TopSpeed.compute(from: samples(bike), kind: .bike), 8, accuracy: 0.01)
        XCTAssertLessThanOrEqual(TopSpeed.cap(for: .walk), 6.71)
        XCTAssertLessThanOrEqual(TopSpeed.cap(for: .drive), 62.6)
    }

    // MARK: Accuracy filters

    func testFuzzyFixesAreIgnored() {
        var s = samples(Array(repeating: 2.0, count: 60))
        for i in 30..<40 { s[i].speed = 6; s[i].horizontalAccuracy = 80 }   // fast but fuzzy: skipped
        XCTAssertEqual(TopSpeed.compute(from: s, kind: .run), 2, accuracy: 0.01)
    }

    func testLooseSpeedAccuracyFallsBackToDistanceOverTime() {
        var s = samples(Array(repeating: 2.0, count: 60))
        for i in 30..<40 { s[i].speed = 9; s[i].speedAccuracy = 6 }   // GPS speed unsure: use the positions (2 m/s)
        XCTAssertEqual(TopSpeed.compute(from: s, kind: .run), 2, accuracy: 0.05)
        for i in 30..<40 { s[i].speedAccuracy = -1 }                   // invalid: same
        XCTAssertEqual(TopSpeed.compute(from: s, kind: .run), 2, accuracy: 0.05)
    }

    func testTinyTimeGapsAreIgnored() {
        var s = samples(Array(repeating: 1.5, count: 60), reportSpeed: false)
        // A near-duplicate fix 0.1 s later and 20 m away would be 200 m/s.
        var dup = s[30]; dup.t += 0.1; dup.lat += 20 / metresPerDegree
        s.insert(dup, at: 31)
        let top = TopSpeed.compute(from: s, kind: .walk)
        XCTAssertLessThan(top, 1.8)
    }

    func testTooFewReadingsGiveZero() {
        XCTAssertEqual(TopSpeed.compute(from: samples([1.4, 1.5]), kind: .walk), 0)
        XCTAssertEqual(TopSpeed.compute(from: [], kind: .drive), 0)
    }

    func testLiveAccumulatorMatchesCompute() {
        var speeds = (0..<200).map { 10 + 5 * sin(Double($0) / 15) }
        speeds[77] = 60
        let s = samples(speeds)
        var acc = TopSpeed.Accumulator(kind: .bike)
        s.forEach { acc.add($0) }
        XCTAssertEqual(acc.top, TopSpeed.compute(from: s, kind: .bike))
        XCTAssertLessThan(acc.top, 15.1)
    }

    /// Saved routes are thinned to 4000 points; a sparse route (a reading every 3 s) still works.
    func testSparseSavedRoute() {
        var speeds = Array(repeating: 25.0, count: 200)
        speeds[100] = 80
        let top = TopSpeed.compute(route: route(speeds, dt: 3), kind: .drive)
        XCTAssertEqual(top, 25, accuracy: 0.01)
    }

    // MARK: Trim and kind change use the same rules

    func testTrimNeverPicksUpASpike() {
        var speeds = Array(repeating: 1.4, count: 120)
        speeds[40] = 45
        let a = Activity()
        a.kind = .walk
        a.route = route(speeds)
        a.maxSpeed = 1.4
        a.trim(endT: t0 + 100)
        XCTAssertEqual(a.maxSpeed, 1.4, accuracy: 0.01)
    }

    func testApplyKindRecomputesForTheNewKind() {
        let a = Activity()
        a.kind = .walk
        a.route = route(Array(repeating: 1.4, count: 30) + Array(repeating: 25, count: 60) + Array(repeating: 1.4, count: 30))
        a.maxSpeed = 1.4
        a.applyKind(.drive)
        XCTAssertEqual(a.kind, .drive)
        XCTAssertEqual(a.maxSpeed, 25, accuracy: 0.01)
        a.applyKind(.walk)
        XCTAssertLessThanOrEqual(a.maxSpeed, TopSpeed.cap(for: .walk))
    }

    // MARK: Repair of past trips

    private func trip(_ kind: ActivityKind, _ speeds: [Double], recordedTop: Double, dt: Double = 1) -> Activity {
        let a = Activity()
        a.kind = kind
        a.title = "Test"
        a.notes = "keep me"
        a.distanceM = 1234
        a.route = route(speeds, dt: dt)
        a.maxSpeed = recordedTop
        return a
    }

    func testRepairLowersSpikesOnlyAndKeepsTheOriginal() {
        var spiky = Array(repeating: 30.0, count: 300); spiky[150] = 75
        let bad = trip(.drive, spiky, recordedTop: 75)
        let good = trip(.drive, Array(repeating: 30.0, count: 300), recordedTop: 30)
        let sparse = trip(.drive, [30, 75, 30, 30, 30], recordedTop: 75)
        let noRoute = Activity(); noRoute.kind = .drive; noRoute.maxSpeed = 75
        let lowerThanRoute = trip(.walk, Array(repeating: 1.4, count: 100), recordedTop: 1.0)
        let routeBefore = bad.routeData

        XCTAssertEqual(TopSpeedRepair.repair([bad, good, sparse, noRoute, lowerThanRoute]), 1)
        XCTAssertEqual(bad.maxSpeed, 30, accuracy: 0.01)
        XCTAssertEqual(bad.rawMaxSpeed, 75)
        XCTAssertEqual(bad.routeData, routeBefore)
        XCTAssertEqual(bad.distanceM, 1234)
        XCTAssertEqual(bad.notes, "keep me")
        XCTAssertEqual(bad.kind, .drive)
        // Untouched: already right, too sparse, no route, and never raised.
        XCTAssertEqual(good.maxSpeed, 30); XCTAssertNil(good.rawMaxSpeed)
        XCTAssertEqual(sparse.maxSpeed, 75); XCTAssertNil(sparse.rawMaxSpeed)
        XCTAssertEqual(noRoute.maxSpeed, 75); XCTAssertNil(noRoute.rawMaxSpeed)
        XCTAssertEqual(lowerThanRoute.maxSpeed, 1.0); XCTAssertNil(lowerThanRoute.rawMaxSpeed)
    }

    func testRepairIsIdempotent() {
        var spiky = Array(repeating: 1.4, count: 200); spiky[100] = 30
        let a = trip(.walk, spiky, recordedTop: 30)
        XCTAssertEqual(TopSpeedRepair.repair([a]), 1)
        let fixed = a.maxSpeed
        XCTAssertEqual(TopSpeedRepair.repair([a]), 0)
        XCTAssertEqual(TopSpeedRepair.repair([a]), 0)
        XCTAssertEqual(a.maxSpeed, fixed)
        XCTAssertEqual(a.rawMaxSpeed, 30)
    }

    func testRescueCopyKeepsTheOriginalTopSpeed() {
        let a = trip(.drive, Array(repeating: 30.0, count: 50), recordedTop: 30)
        a.rawMaxSpeed = 70
        XCTAssertEqual(Activity.copy(of: a).rawMaxSpeed, 70)
    }

    // MARK: Kind order

    func testKindOrderAndRawValues() {
        XCTAssertEqual(ActivityKind.allCases, [.drive, .walk, .bike, .hike, .run])
        XCTAssertEqual(ActivityKind.available, [.drive, .walk, .bike, .hike, .run])
        // Stored by name: these must never change.
        XCTAssertEqual(ActivityKind.allCases.map(\.rawValue), ["drive", "walk", "bike", "hike", "run"])
        XCTAssertEqual(ActivityKind(rawValue: "bike"), .bike)
        XCTAssertEqual(RoamrKindOption.allCases, [.drive, .walk, .ride, .hike, .run])
        XCTAssertEqual(RoamrKindOption.allCases.map(\.rawValue), ["drive", "walk", "ride", "hike", "run"])
    }
}
