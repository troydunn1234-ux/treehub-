import XCTest
import CoreLocation
@testable import Roamr

/// Pure logic behind recording, the trip page and the Rootbound feed (no GPS, no store).
final class LogicTests: XCTestCase {

    private func point(_ i: Int, lat: Double = 37.77, lng: Double = -122.45, step: Double = 0.0002, speed: Double = 1.4,
                       t0: Double = 1_700_000_000, dt: Double = 5) -> RoutePoint {
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat + Double(i) * step, longitude: lng),
                             altitude: 20 + Double(i), horizontalAccuracy: 5, verticalAccuracy: 5,
                             course: 0, speed: speed, timestamp: Date(timeIntervalSince1970: t0 + Double(i) * dt))
        return RoutePoint(loc)
    }

    private func walk(_ n: Int) -> [RoutePoint] { (0..<n).map { point($0) } }

    // MARK: Route ends for the Rootbound feed

    func testRouteEndsMatchFullDecode() throws {
        let pts = walk(500)
        let data = try JSONEncoder().encode(pts)
        let ends = try XCTUnwrap(RoamrWellness.routeEnds(data))
        XCTAssertEqual(ends.first, pts.first)
        XCTAssertEqual(ends.last, pts.last)
    }

    func testRouteEndsOfOnePointAndOfNothing() throws {
        let one = [point(0)]
        let ends = try XCTUnwrap(RoamrWellness.routeEnds(try JSONEncoder().encode(one)))
        XCTAssertEqual(ends.first, one[0])
        XCTAssertEqual(ends.last, one[0])
        XCTAssertNil(RoamrWellness.routeEnds(try JSONEncoder().encode([RoutePoint]())))
        XCTAssertNil(RoamrWellness.routeEnds(Data("not json".utf8)))
    }

    /// Unknown altitude and a speed limit are encoded differently; the partial read still gets them right.
    func testRouteEndsWithMissingAltitudeAndLimit() throws {
        var pts = walk(3)
        pts[0].alt = .nan
        pts[2].limit = 29
        let ends = try XCTUnwrap(RoamrWellness.routeEnds(try JSONEncoder().encode(pts)))
        XCTAssertTrue(ends.first.alt.isNaN)
        XCTAssertEqual(ends.first.lat, pts[0].lat)
        XCTAssertEqual(ends.last.limit, 29)
    }

    // MARK: Trim sheet

    @MainActor
    func testTrimDistanceMatchesActivityStats() {
        var pts = walk(200)
        // A GPS jump (> 95 m/s) that stats skips.
        pts[100].lat += 0.05
        let cum = TrimSheet.cumulativeDistance(pts)
        XCTAssertEqual(cum.count, pts.count)
        XCTAssertEqual(cum.last ?? -1, Activity.stats(pts).distance, accuracy: 0.001)
        let sub = Array(pts[40...160])
        XCTAssertEqual(cum[160] - cum[40], Activity.stats(sub).distance, accuracy: 0.001)
    }

    // MARK: Recording

    @MainActor
    func testSimplifyKeepsEndsAndLimit() {
        let pts = walk(10_000)
        let s = RouteTracker.simplify(pts, maxCount: 4000)
        XCTAssertEqual(s.count, 4000)
        XCTAssertEqual(s.first, pts.first)
        XCTAssertEqual(s.last, pts.last)
        XCTAssertEqual(RouteTracker.simplify(walk(10), maxCount: 4000).count, 10)
    }

    @MainActor
    func testIdleTailStartFindsTheParkedEnd() throws {
        // 60 points moving, then 40 standing still.
        var pts = walk(60)
        let last = pts[59]
        for i in 1...40 {
            pts.append(point(59, speed: 0, t0: last.t + Double(i) * 5 - 59 * 5, dt: 5))
        }
        let cut = try XCTUnwrap(RouteTracker.idleTailStart(pts, kind: .walk))
        XCTAssertEqual(cut, last.t, accuracy: 0.001)
        XCTAssertNil(RouteTracker.idleTailStart(walk(60), kind: .walk))
    }

    // MARK: Drive prompt

    func testOldStartDrivePromptDoesNotStartADrive() {
        let now = Date()
        XCTAssertTrue(DriveDetector.promptStillFresh(sentAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(DriveDetector.promptStillFresh(sentAt: now.addingTimeInterval(-2 * 3600), now: now))
    }

    // MARK: List thumbnails

    func testThumbnailThinningKeepsStartAndFinish() {
        let all = walk(2501).map(\.coordinate)
        let thin = RouteThumbCache.thinned(all)
        XCTAssertLessThanOrEqual(thin.count, 302)
        XCTAssertEqual(thin.first?.latitude, all.first?.latitude)
        XCTAssertEqual(thin.last?.latitude, all.last?.latitude)
        XCTAssertEqual(RouteThumbCache.thinned(Array(all.prefix(20))).count, 20)
    }

    /// List rows no longer decode a route while they're drawn: the outline is loaded in the background, then cached
    /// until a trim changes the route.
    @MainActor
    func testRouteOutlineLoadsInTheBackgroundAndFollowsATrim() async {
        let pts = walk(1000)
        let a = Activity()
        a.kind = .walk
        a.route = pts
        a.end = Date(timeIntervalSince1970: pts[999].t)
        a.distanceM = 1234
        XCTAssertNil(RouteThumbCache.cached(for: a), "nothing is decoded just to draw a row")
        let outline = await RouteThumbCache.load(for: a)
        XCTAssertEqual(outline.first?.latitude, pts[0].lat)
        XCTAssertEqual(outline.last?.latitude, pts[999].lat)
        XCTAssertLessThanOrEqual(outline.count, 302)
        XCTAssertEqual(RouteThumbCache.cached(for: a)?.count, outline.count)

        a.trim(endT: pts[499].t)
        XCTAssertNil(RouteThumbCache.cached(for: a), "a trim needs a new outline")
        let trimmed = await RouteThumbCache.load(for: a)
        XCTAssertEqual(trimmed.last?.latitude, pts[499].lat)

        let none = await RouteThumbCache.load(for: Activity())
        XCTAssertTrue(none.isEmpty, "no route: no outline")
    }

    // MARK: Map geometry caches

    @MainActor
    func testLiveRouteCacheRebuildsOnlyForNewPoints() {
        let cache = LiveRouteCache()
        var pts = walk(10)
        XCTAssertEqual(cache.update(pts, drive: false).coords.count, 10)
        XCTAssertTrue(cache.segments.isEmpty)
        pts.append(point(10))
        XCTAssertEqual(cache.update(pts, drive: false).coords.count, 11)
        XCTAssertFalse(cache.update(pts, drive: true).segments.isEmpty, "a drive gets speed-colored segments")
    }

    @MainActor
    func testTripRouteCacheFollowsATrim() {
        let a = Activity()
        a.kind = .walk
        a.route = walk(100)
        a.end = Date(timeIntervalSince1970: a.route.last!.t)
        let cache = TripRouteCache()
        cache.load(a)
        let v = cache.version
        XCTAssertEqual(cache.coords.count, 100)
        cache.load(a)
        XCTAssertEqual(cache.version, v, "same route: nothing rebuilt")
        a.trim(endT: a.route[49].t)
        cache.load(a)
        XCTAssertEqual(cache.coords.count, 50)
        XCTAssertGreaterThan(cache.version, v)
    }
}
