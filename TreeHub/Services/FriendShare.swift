import Foundation
import CoreLocation
import CoreImage.CIFilterBuiltins
import UIKit

/// Friends map, with no server: you pick which trees to share, Rootbound packs them into a short code
/// (in a rootbound:// link and a QR code), and your friend imports it to see your trees on their map.
/// Only the tree's name, species and a location rounded to about 1 km go in the code. No photos, no dates,
/// nothing else. Friends' trees are kept on this phone only.
struct SharedTree: Codable, Hashable {
    var n: String        // name
    var s: String        // species
    var la: Double       // latitude, rounded to 0.01° (~1.1 km)
    var lo: Double       // longitude, rounded to 0.01°

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: la, longitude: lo) }
}

struct SharePack: Codable {
    var v: Int = 1
    var from: String
    var t: [SharedTree]
}

struct FriendGrove: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var trees: [SharedTree]
    var importedAt: Date = Date()
}

enum FriendShare {
    static let scheme = "rootbound"
    static let prefix = "RB1-"
    private static let sharedKey = "friends.sharedTreeIDs"
    private static let friendsKey = "friends.groves"
    static let nameKey = "friends.myName"

    // MARK: Which of my trees are shared (opt-in per tree)

    static var sharedTreeIDs: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: sharedKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: sharedKey) }
    }

    static func setShared(_ id: UUID, _ on: Bool) {
        var s = sharedTreeIDs
        if on { s.insert(id) } else { s.remove(id) }
        sharedTreeIDs = s
    }

    /// About 1 km: two decimal places of a degree.
    static func coarse(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // MARK: Encode / decode

    static func pack(from name: String, trees: [TreeSummary]) -> SharePack {
        let ids = sharedTreeIDs
        let list = trees.filter { ids.contains($0.id) }.compactMap { t -> SharedTree? in
            guard let c = t.coordinate else { return nil }
            return SharedTree(n: String(t.name.prefix(40)), s: String(t.species.prefix(40)), la: coarse(c.latitude), lo: coarse(c.longitude))
        }
        return SharePack(from: String(name.prefix(30)), t: Array(list.prefix(150)))
    }

    static func code(for pack: SharePack) -> String? {
        guard let json = try? JSONEncoder().encode(pack) else { return nil }
        let body = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        let b64 = body.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return prefix + b64
    }

    static func link(for code: String) -> URL? { URL(string: "\(scheme)://friends?c=\(code)") }

    /// Accepts a bare code, a rootbound:// link, or text with either somewhere in it.
    static func decode(_ text: String) -> SharePack? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = raw
        if let r = raw.range(of: prefix) {
            code = String(raw[r.lowerBound...]).components(separatedBy: CharacterSet(charactersIn: " \n&\"'<>")).first ?? ""
        }
        guard code.hasPrefix(prefix) else { return nil }
        var b64 = String(code.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        let json = (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        guard var pack = try? JSONDecoder().decode(SharePack.self, from: json) else { return nil }
        // Keep it sane whatever was pasted: valid coordinates, still coarse, short strings.
        pack.t = pack.t.prefix(300).compactMap { t in
            guard (-90...90).contains(t.la), (-180...180).contains(t.lo) else { return nil }
            return SharedTree(n: String(t.n.prefix(40)), s: String(t.s.prefix(40)), la: coarse(t.la), lo: coarse(t.lo))
        }
        pack.from = String(pack.from.prefix(30))
        return pack
    }

    // MARK: Friends' groves (on this phone only)

    static var friends: [FriendGrove] {
        get {
            guard let d = UserDefaults.standard.data(forKey: friendsKey) else { return [] }
            return (try? JSONDecoder().decode([FriendGrove].self, from: d)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: friendsKey) }
    }

    /// Adds a friend's grove, replacing an earlier import with the same name. Returns the saved grove.
    @discardableResult
    static func importPack(_ pack: SharePack) -> FriendGrove {
        let name = pack.from.trimmingCharacters(in: .whitespaces).isEmpty ? "A friend" : pack.from
        var list = friends.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
        let g = FriendGrove(name: name, trees: pack.t)
        list.insert(g, at: 0)
        friends = list
        NotificationCenter.default.post(name: changed, object: nil)
        return g
    }

    static func remove(_ id: UUID) {
        friends = friends.filter { $0.id != id }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static let changed = Notification.Name("friends.changed")
    /// A rootbound://friends link was opened: the Grove's Friends sheet shows the import.
    static let incoming = Notification.Name("friends.incoming")
    static var pendingCode: String?

    // MARK: QR

    static func qrImage(for text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
