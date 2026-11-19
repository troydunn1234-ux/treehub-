import XCTest
@testable import StillPoint

/// Still Pointz reads rootbound.json: the optional tripTrees field (newer Rootbound) must decode, and an older
/// file without it must too.
final class FamilyFeedTests: XCTestCase {
    private func decode(_ json: String) throws -> WellnessBridge.RootboundPart {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
    }

    func testRootboundFeedDecodesWithAndWithoutTripTrees() throws {
        let old = try decode(#"{"updated":1794700000,"streak":2,"hugs":[]}"#)
        XCTAssertNil(old.tripTrees)
        let new = try decode(#"{"updated":1794700000,"streak":2,"hugs":[],"tripTrees":[{"tripID":"6E1F1C1A-0000-4000-8000-000000000010","trees":[{"treeID":"6E1F1C1A-0000-4000-8000-000000000011","name":"Elm","species":"","hugged":true}]}]}"#)
        XCTAssertEqual(new.tripTrees?.first?.trees.first?.hugged, true)
    }

    /// In Still Pointz a recent tree hug shows under "From your other apps" with a link back to its tree.
    func testHugShowsAsGroundingWithLinkBack() {
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        let tree = UUID()
        let rb = WellnessBridge.RootboundPart(updated: now, streak: 1, hugs: [
            .init(id: UUID(), date: now.addingTimeInterval(-300), minutes: 4, tree: "Grandpa Oak", species: "", treeID: tree),
        ])
        let items = WellnessConnect.familyItems(for: WellnessConnect.stillPoint, now: now, metric: true,
                                                stillPoint: nil, rootbound: rb, roamr: nil, pulseLab: nil)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, WellnessConnect.rootboundTree(tree))
        XCTAssertEqual(items[0].detail, "4 min · counts as grounding time here")
    }
}
