import XCTest
@testable import Roamr

/// Roamr reads rootbound.json for "Trees along this walk": the optional tripTrees field must decode, and an older
/// file without it must too (then the card stays hidden).
final class FamilyFeedTests: XCTestCase {
    private func decode(_ json: String) throws -> WellnessBridge.RootboundPart {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
    }

    func testTripTreesLookup() throws {
        let old = try decode(#"{"updated":1794700000,"streak":2,"hugs":[]}"#)
        XCTAssertTrue(WellnessConnect.trees(onTrip: UUID(), in: old).isEmpty)
        let trip = UUID(uuidString: "6E1F1C1A-0000-4000-8000-000000000010")!
        let new = try decode(#"{"updated":1794700000,"streak":2,"hugs":[],"tripTrees":[{"tripID":"6E1F1C1A-0000-4000-8000-000000000010","trees":[{"treeID":"6E1F1C1A-0000-4000-8000-000000000011","name":"Elm"}]}]}"#)
        XCTAssertEqual(WellnessConnect.trees(onTrip: trip, in: new).map(\.name), ["Elm"])
        XCTAssertTrue(WellnessConnect.trees(onTrip: UUID(), in: new).isEmpty)
    }
}
