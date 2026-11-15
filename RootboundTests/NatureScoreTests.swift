import XCTest
@testable import Rootbound

/// Nature Roll scoring with made-up Vision labels (no photos needed).
final class NatureScoreTests: XCTestCase {
    func testSunsetLandscapeIsASunset() {
        let s = NatureSignals(labels: ["sunset_sunrise": 0.9, "sky": 0.95, "outdoor": 0.8, "clouds": 0.6, "mountain": 0.4],
                              faceFraction: 0, textFraction: 0, aesthetic: 0.5, sunElevation: 3)
        let v = NatureScore.evaluate(s, strictness: .strict)
        XCTAssertTrue(v.included, "excluded: \(v.excluded ?? "")")
        XCTAssertNotNil(v.categories[.sunrises])
    }

    func testBackyardBushCloseUpIsExcluded() {
        let s = NatureSignals(labels: ["plant": 0.92, "shrub": 0.85, "foliage": 0.7, "hedge": 0.5, "grass": 0.45,
                                       "yard": 0.4, "outdoor": 0.5, "tree": 0.3],
                              faceFraction: 0, textFraction: 0, aesthetic: 0.1, kmFromHome: 0.1)
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .strict).included)
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .balanced).included)
    }

    func testIndoorHousePlantIsExcluded() {
        let s = NatureSignals(labels: ["houseplant": 0.8, "plant": 0.9, "interior_room": 0.7, "furniture": 0.5,
                                       "flowerpot": 0.6, "flower": 0.4])
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .strict).included)
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .everything).included)
    }

    func testDogOnCouchIsExcluded() {
        let s = NatureSignals(labels: ["dog": 0.95, "animal": 0.9, "canine": 0.9, "couch": 0.7, "furniture": 0.6,
                                       "indoor": 0.6, "mammal": 0.9])
        let v = NatureScore.evaluate(s, strictness: .strict)
        XCTAssertFalse(v.included)
        XCTAssertNil(v.categories[.wildlife])
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .everything).included)
    }

    func testTrailWithSmallPersonIsATrail() {
        let s = NatureSignals(labels: ["outdoor": 0.9, "path": 0.75, "hiking": 0.55, "forest": 0.6, "tree": 0.8,
                                       "people": 0.5, "adult": 0.45, "sky": 0.4],
                              faceFraction: 0.01, textFraction: 0.002, aesthetic: 0.3)
        let v = NatureScore.evaluate(s, strictness: .strict)
        XCTAssertTrue(v.included, "excluded: \(v.excluded ?? "")")
        XCTAssertNotNil(v.categories[.trails])
    }

    func testSelfieInFrontOfViewIsExcluded() {
        let s = NatureSignals(labels: ["mountain": 0.8, "sky": 0.9, "outdoor": 0.9, "people": 0.9],
                              faceFraction: 0.2, textFraction: 0, aesthetic: 0.4)
        XCTAssertFalse(NatureScore.evaluate(s, strictness: .strict).included)
    }

    func testSunElevation() {
        // March equinox, noon UTC on the equator at Greenwich: sun nearly overhead; midnight side: far below.
        let noon = Date(timeIntervalSince1970: 1_710_936_000) // 2024-03-20 12:00 UTC
        XCTAssertGreaterThan(SunPosition.elevation(latitude: 0, longitude: 0, date: noon), 85)
        XCTAssertLessThan(SunPosition.elevation(latitude: 0, longitude: 180, date: noon), -85)
    }
}
