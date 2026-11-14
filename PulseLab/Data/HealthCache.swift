import Foundation

/// The raw Apple Health pull, kept on disk so the full history (2 years) is read only once.
/// Each refresh re-reads a short window (the last 3 days, or further back if late samples arrived)
/// and splices it in, so charts never miss days and late WHOOP-to-Health data still lands.
enum HealthCache {
    /// Bump to force everyone through a fresh full backfill (e.g. when new metrics are added).
    static let version = 2
    /// How far back the one-time backfill reads.
    static let historyDays = 730

    struct Snapshot: Codable {
        var version: Int
        var result: HealthPull.Result
        var backfilledFrom: Date
        var savedAt: Date
    }

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("health-cache.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.version == version else { return nil }
        return snap
    }

    static func save(_ snap: Snapshot) {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
