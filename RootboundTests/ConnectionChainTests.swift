import XCTest
import UIKit
@testable import Rootbound

/// The hops of the owner's routine that Rootbound handles, as pure logic: a camera-roll photo's time picks the
/// Still Pointz sessions for a hug, a tree's cover photo, and the photo cache the screens draw from.
final class ConnectionChainTests: XCTestCase {
    private let photoTime = Date(timeIntervalSince1970: 1_794_700_000)

    private func session(_ offsetMin: Double, minutes: Double = 3, kind: String = "breath",
                         tree: String? = nil) -> WellnessBridge.Session {
        var s = WellnessBridge.Session(id: UUID(), date: photoTime.addingTimeInterval(offsetMin * 60), kind: kind, minutes: minutes)
        s.practice = "rooted-breath"
        s.treeName = tree
        s.treeID = tree.map { _ in UUID().uuidString }
        s.avgHR = 64; s.startHR = 71; s.minHR = 60; s.hrDrop = 11; s.hrv = 48
        return s
    }

    /// Breath sessions within an hour of the photo are offered, nearest first, with their heart data; sauna,
    /// steam, sessions under a minute and ones further than an hour away are not.
    func testPhotoTimePicksTheNearbyBreathSessions() {
        let tree = session(8, tree: "Grandpa Oak")
        let earlier = session(-50)
        let feed = [session(-70), earlier, tree, session(5, kind: "sauna"), session(2, minutes: 0.5), session(65)]
        let picked = HugSessions.feedCandidates(near: photoTime, in: feed)
        XCTAssertEqual(picked.map(\.feedID), [tree.id, earlier.id])
        XCTAssertEqual(picked.first?.source, "Still Pointz")
        XCTAssertEqual(picked.first?.hrDrop, 11)
        XCTAssertEqual(picked.first?.hrv, 48)
        XCTAssertEqual(picked.first?.practiceName, "Rooted Breath")
    }

    /// A photo taken nowhere near a session finds nothing (so the hug logger drops what it linked on open).
    func testPhotoFarFromAnySessionFindsNone() {
        let feed = [session(-180), session(240)]
        XCTAssertTrue(HugSessions.feedCandidates(near: photoTime, in: feed).isEmpty)
    }

    /// A tree's cover is its oldest tree photo (the first meeting), else its newest selfie; none without photos.
    func testTreeCoverPhoto() {
        let tree = UUID()
        func hug(_ day: Double, tree photo: Data? = nil, selfie: Data? = nil) -> Hug {
            let h = Hug()
            h.treeID = tree
            h.treeName = "Grandpa Oak"
            h.date = photoTime.addingTimeInterval(day * 86400)
            h.treePhoto = photo
            h.selfiePhoto = selfie
            return h
        }
        let first = Data("first".utf8), later = Data("later".utf8), selfie = Data("selfie".utf8)
        let withPhotos = TreeSummary.build(from: [hug(0, tree: first), hug(3, tree: later), hug(5, selfie: selfie)])
        XCTAssertEqual(withPhotos.count, 1)
        XCTAssertEqual(withPhotos.first?.coverPhoto, first)
        XCTAssertEqual(withPhotos.first?.hugCount, 3)

        let selfieOnly = TreeSummary.build(from: [hug(0), hug(4, selfie: selfie)])
        XCTAssertEqual(selfieOnly.first?.coverPhoto, selfie)
        XCTAssertNil(TreeSummary.build(from: [hug(0)]).first?.coverPhoto)
    }

    private func jpeg(_ size: CGSize, _ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.8) { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: size.width / 3, y: size.height / 3, width: size.width / 4, height: size.height / 5))
        }
    }

    /// Photos are decoded at the size they're shown, never bigger.
    func testPhotoDownsamplesToTheShownSize() throws {
        let data = jpeg(CGSize(width: 1800, height: 1200), .systemGreen)
        let small = try XCTUnwrap(RBPhotoCache.downsample(data, maxPixel: 168))
        XCTAssertLessThanOrEqual(max(small.size.width * small.scale, small.size.height * small.scale), 168)
        XCTAssertGreaterThan(small.size.width, small.size.height, "keeps the landscape shape")
        XCTAssertNil(RBPhotoCache.downsample(Data("not a photo".utf8), maxPixel: 100))
    }

    /// The cache key tells photos (and sizes) apart, and is stable for the same photo.
    func testPhotoCacheKeys() {
        let a = jpeg(CGSize(width: 600, height: 400), .systemGreen)
        let b = jpeg(CGSize(width: 600, height: 400), .systemBrown)
        XCTAssertEqual(RBPhotoCache.key(a, maxPixel: 200), RBPhotoCache.key(Data(a), maxPixel: 200))
        XCTAssertNotEqual(RBPhotoCache.key(a, maxPixel: 200), RBPhotoCache.key(b, maxPixel: 200))
        XCTAssertNotEqual(RBPhotoCache.key(a, maxPixel: 200), RBPhotoCache.key(a, maxPixel: 600))
        XCTAssertEqual(RBPhotoCache.key(Data(), maxPixel: 10), RBPhotoCache.key(Data(), maxPixel: 10))
        // A slice of a bigger buffer (non-zero start index) works too.
        let padded = Data([0, 1, 2]) + a
        XCTAssertEqual(RBPhotoCache.key(padded.dropFirst(3), maxPixel: 200), RBPhotoCache.key(a, maxPixel: 200))
    }
}
