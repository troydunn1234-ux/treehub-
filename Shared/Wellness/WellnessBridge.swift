import Foundation
import UIKit

// Rootbound <-> Still Pointz (and Roamr -> Rootbound): a tiny shared "activity feed" plus the deep links between the apps.
// Compiled into all three (project.yml: Rootbound and Roamr get Shared/, Still Point gets Shared/Wellness).
//
// The feed lives in the shared App Group `group.com.troydunn.wellness` as two small JSON files, one per app,
// so each app only ever writes its own file (no races) and reads the other's:
//   rootbound.json   recent tree hugs (date, minutes, tree name, species; never coordinates) + hug streak
//   stillpoint.json  recent Still Pointz sessions (date, kind, minutes) + practice streak
//   pulselab.json    Pulse Lab's daily summary (WHOOP recovery / strain / sleep performance, readiness, HRV,
//                    resting HR) so Still Pointz can suggest one practice from it. Numbers only, today's day.
//   roamr.json       recent Roamr trips (last 60 days: kind, times, distance, climb, speeds, avg HR, start/end
//                    rounded to ~100 m; never the route itself). Rootbound attaches the walks to tree hugs.
// Apple Health is NOT touched here: each app keeps writing only its own data there, so nothing is counted twice.
// When the other app isn't installed (or the group isn't provisioned) the feed is simply empty.

enum WellnessBridge {
    static let groupID = "group.com.troydunn.wellness"
    /// How far back each app publishes (keeps the files small).
    static let keepDays = 120
    static let maxItems = 300

    struct TreeHug: Codable, Hashable, Identifiable {
        var id: UUID
        var date: Date
        var minutes: Double
        var tree: String
        var species: String
        /// The tree's stable id in Rootbound (every hug of one tree shares it).
        var treeID: UUID? = nil
        /// Still Pointz sessions (feed ids) and Roamr trips linked to this hug in Rootbound. Optional: older feeds
        /// don't have them. Still Pointz shows the tree on a linked session; Roamr shows the hug on a linked walk.
        var sessionIDs: [UUID]? = nil
        var walkIDs: [UUID]? = nil
    }

    struct Session: Codable, Hashable, Identifiable {
        var id: UUID
        var date: Date
        /// breath, mantra, movement, sauna, steam … (Still Pointz' own kind names).
        var kind: String
        var minutes: Double

        // A breath "with a tree" (Rootbound -> Still Pointz -> back): which tree, and how the body settled.
        // All optional so older feeds still decode. Heart data comes from Apple Health (read-only here).
        var treeID: String? = nil
        var treeName: String? = nil
        var end: Date? = nil
        var avgHR: Double? = nil
        var minHR: Double? = nil
        var startHR: Double? = nil
        /// Start -> lowest heart rate (bpm); positive = calmer.
        var hrDrop: Double? = nil
        /// Average HRV (SDNN, ms) in the window, when a Watch took one.
        var hrv: Double? = nil
        var practice: String? = nil
        /// Added with Still Pointz' session stats (all optional): end heart rate, breathing rate from Apple Health,
        /// seconds below the starting heart rate, and the paced breaths per minute.
        var endHR: Double? = nil
        var respRate: Double? = nil
        var calmSeconds: Double? = nil
        var breathsPerMin: Double? = nil

        /// Guided practice (anything but sauna / steam): what Rootbound shows as "Calm minutes".
        var isCalm: Bool { !["sauna", "steam"].contains(kind.lowercased()) }
    }

    /// One Roamr recording (walk, run, hike, ride or drive). Only what Rootbound shows under a hug.
    struct Trip: Codable, Hashable, Identifiable {
        var id: UUID
        /// ActivityKind raw value: walk, run, hike, bike, drive.
        var kind: String
        var start: Date
        var end: Date
        var distanceM: Double
        /// Moving time (s).
        var movingSec: Double
        var elevGainM: Double
        /// m/s
        var avgSpeed: Double
        var topSpeed: Double
        var avgHR: Double? = nil
        /// Coarse start / end (rounded to 0.001°, ~100 m). Optional so a trip without GPS still decodes.
        var startLat: Double? = nil
        var startLng: Double? = nil
        var endLat: Double? = nil
        var endLng: Double? = nil

        var isOnFoot: Bool { ["walk", "run", "hike"].contains(kind) }
    }

    struct RoamrPart: Codable {
        var updated = Date()
        var trips: [Trip] = []
    }

    /// Roamr publishes this many days of trips.
    static let roamrKeepDays = 60

    /// ~100 m grid for the coarse start / end points.
    static func coarse(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    struct RootboundPart: Codable {
        var updated = Date()
        var streak = 0
        var hugs: [TreeHug] = []
    }

    struct StillPointPart: Codable {
        var updated = Date()
        var streak = 0
        var sessions: [Session] = []
    }

    // MARK: Files

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Wellness", isDirectory: true)
    }

    private static func url(_ name: String) -> URL? { folder?.appendingPathComponent(name) }

    private static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(T.self, from: d)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let dir = folder, let u = url(name) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(value) else { return }
        try? d.write(to: u, options: .atomic)
        announceChange()
    }

    /// Darwin notification posted after an app rewrites its part, so the family apps that are running re-read the
    /// feed right away (WellnessFeed in WellnessConnect.swift) instead of at their next foreground. No payload.
    static let changedNotification = "com.troydunn.wellness.changed"

    private static func announceChange() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(changedNotification as CFString), nil, nil, true)
    }

    private static var cutoff: Date { Date().addingTimeInterval(-Double(keepDays) * 86400) }

    // MARK: Rootbound side

    /// Rootbound: replace its half of the feed.
    static func publishRootbound(hugs: [TreeHug], streak: Int) {
        let kept = hugs.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.prefix(maxItems)
        save(RootboundPart(updated: Date(), streak: streak, hugs: Array(kept)), "rootbound.json")
    }

    /// Still Pointz reads this.
    static func rootbound() -> RootboundPart? { load("rootbound.json", as: RootboundPart.self) }

    // MARK: Still Pointz side

    /// Still Pointz: replace its half of the feed.
    static func publishStillPoint(sessions: [Session], streak: Int) {
        let kept = sessions.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.prefix(maxItems)
        save(StillPointPart(updated: Date(), streak: streak, sessions: Array(kept)), "stillpoint.json")
    }

    /// Rootbound reads this.
    static func stillPoint() -> StillPointPart? { load("stillpoint.json", as: StillPointPart.self) }

    // MARK: Roamr side

    /// Roamr: replace its part of the feed (last 60 days, newest first).
    static func publishRoamr(trips: [Trip]) {
        let since = Date().addingTimeInterval(-Double(roamrKeepDays) * 86400)
        let kept = trips.filter { $0.start >= since }.sorted { $0.start > $1.start }.prefix(maxItems)
        save(RoamrPart(updated: Date(), trips: Array(kept)), "roamr.json")
    }

    /// Rootbound reads this.
    static func roamr() -> RoamrPart? { load("roamr.json", as: RoamrPart.self) }

    // MARK: Pulse Lab side

    /// Pulse Lab's summary of today (one record, replaced on every refresh). Every number optional.
    struct PulseLabPart: Codable, Hashable {
        var updated = Date()
        /// dayKey of the day these numbers belong to ("2026-11-15").
        var date: String
        /// WHOOP recovery % (0–100) for this morning.
        var whoopRecovery: Double? = nil
        /// WHOOP day strain (0–21), today's cycle or yesterday's when today's hasn't started.
        var whoopStrain: Double? = nil
        /// WHOOP sleep performance % for last night.
        var sleepPerformance: Double? = nil
        /// Pulse Lab readiness (0–100) built from the Watch.
        var readiness: Double? = nil
        /// HRV (ms) and resting heart rate (bpm) behind the numbers above.
        var hrv: Double? = nil
        var rhr: Double? = nil
        /// Last night's sleep (minutes asleep).
        var sleepMinutes: Double? = nil
        /// Where the numbers came from.
        var fromWhoopAPI = false
        var fromWhoopManual = false
        var fromWhoopHealth = false
        var fromWatch = false

        /// True when these numbers are for today (local calendar).
        var isToday: Bool { date == WellnessBridge.dayKey(Date()) }
    }

    /// Pulse Lab: replace its summary.
    static func publishPulseLab(_ part: PulseLabPart) {
        save(part, "pulselab.json")
    }

    /// Still Pointz reads this (nil when Pulse Lab isn't installed or hasn't published yet).
    static func pulseLab() -> PulseLabPart? { load("pulselab.json", as: PulseLabPart.self) }

    // MARK: Helpers

    /// Days (start of day) in `items` dates.
    static func days(_ dates: [Date]) -> Set<Date> {
        let cal = Calendar.current
        return Set(dates.map { cal.startOfDay(for: $0) })
    }

    /// "2026-11-15" in the local calendar (stable key for a day).
    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Deep links between the two apps

@MainActor
enum WellnessLinks {
    static let rootboundBundleID = "com.troydunn.rootbound"
    static let stillPointBundleID = "com.troydunn.stillpoint"
    static let roamrBundleID = "com.troydunn.roamr"

    /// Roamr, just opened (its History tab shows the walk).
    static let roamrHome = URL(string: "roamr://history")!
    static var roamrInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: "roamr://")!) }

    /// Still Pointz: a short grounding breath with a tree. `treeID` lets the session sync back under that tree.
    static func breatheWithTree(_ name: String, treeID: UUID? = nil, practice: String = "resonance", minutes: Int = 3) -> URL {
        var c = URLComponents()
        c.scheme = "stillpoint"
        c.host = "session"
        c.queryItems = [
            URLQueryItem(name: "practice", value: practice),
            URLQueryItem(name: "minutes", value: "\(minutes)"),
            URLQueryItem(name: "context", value: "tree"),
            URLQueryItem(name: "name", value: name),
        ] + (treeID.map { [URLQueryItem(name: "tree", value: $0.uuidString)] } ?? [])
        return c.url ?? URL(string: "stillpoint://session")!
    }

    /// Still Pointz' Journey tab (Rootbound Home "calm minutes" card).
    static let stillPointJourney = URL(string: "stillpoint://journey")!

    /// Rootbound's hug logger.
    static let hugLogger = URL(string: "rootbound://hug")!
    /// Rootbound, just opened.
    static let rootboundHome = URL(string: "rootbound://home")!

    /// Rootbound's page for one tree (its Breath sessions show the session just finished).
    static func rootboundTree(_ id: String) -> URL {
        var c = URLComponents()
        c.scheme = "rootbound"
        c.host = "tree"
        c.queryItems = [URLQueryItem(name: "id", value: id)]
        return c.url ?? rootboundHome
    }

    static var stillPointInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: "stillpoint://")!) }
    static var rootboundInstalled: Bool { UIApplication.shared.canOpenURL(URL(string: "rootbound://")!) }

    /// Opens `url` if the other app is there. Returns false (and opens nothing) when it isn't.
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    /// The other app's App Store page (IDs from MoreApps.all).
    static func storeURL(bundleID: String) -> URL? {
        guard let id = MoreApps.all.first(where: { $0.bundleID == bundleID })?.appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }
}
