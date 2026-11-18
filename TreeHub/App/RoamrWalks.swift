import Foundation
import SwiftData

/// One walk, hike or run attached to a hug: from Roamr's feed (Shared/Wellness/WellnessBridge.swift, roamr.json)
/// or, before Roamr shares one, from any app's walking / hiking / running workout in Apple Health.
struct LinkedWalk: Codable, Hashable, Identifiable {
    /// The Roamr trip's id, or the Health workout's uuid.
    var id: UUID
    /// walk, hike or run.
    var kind: String
    var start: Date
    var end: Date
    var distanceM: Double
    /// Moving time (s); 0 when only the start / end are known.
    var movingSec: Double
    var elevGainM: Double
    /// m/s
    var avgSpeed: Double?
    var topSpeed: Double?
    var avgHR: Double?
    /// "Roamr", or the app that saved the Health workout.
    var source: String
    var fromRoamr: Bool

    var title: String {
        switch kind {
        case "hike": return "Hike"
        case "run": return "Run"
        default: return "Walk"
        }
    }

    var symbol: String {
        switch kind {
        case "hike": return "figure.hiking"
        case "run": return "figure.run"
        default: return "figure.walk"
        }
    }

    var seconds: Double { movingSec > 0 ? movingSec : max(0, end.timeIntervalSince(start)) }

    /// "2.3 mi"
    var distanceText: String { Self.distance(distanceM) }
    /// "48 min"
    var timeText: String { Format.minutes((seconds / 60).rounded()) }
    /// "+410 ft"
    var climbText: String? { elevGainM >= 1 ? "+" + Format.elevation(elevGainM) : nil }

    /// "Walk · 2.3 mi · 48 min · +410 ft"
    var summary: String {
        ([title] + (distanceM > 0 ? [distanceText] : []) + [timeText] + (climbText.map { [$0] } ?? [])).joined(separator: " · ")
    }

    func sameWalk(as o: LinkedWalk) -> Bool {
        id == o.id || (abs(start.timeIntervalSince(o.start)) < 180 && abs(end.timeIntervalSince(o.end)) < 600)
    }

    static func distance(_ m: Double) -> String {
        if Units.metric { return m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000) }
        let mi = m / 1609.344
        return mi < 0.1 ? "\(Int((m * 3.28084).rounded())) ft" : String(format: "%.1f mi", mi)
    }
}

extension LinkedWalk {
    /// Lenient like LinkedSession: a walk saved on a hug by any other build always loads. One field that doesn't
    /// decode must not empty the hug's whole list (editing the hug would then save it empty).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "walk"
        start = (try? c.decodeIfPresent(Date.self, forKey: .start)) ?? Date(timeIntervalSince1970: 0)
        end = (try? c.decodeIfPresent(Date.self, forKey: .end)) ?? start
        distanceM = (try? c.decodeIfPresent(Double.self, forKey: .distanceM)) ?? 0
        movingSec = (try? c.decodeIfPresent(Double.self, forKey: .movingSec)) ?? 0
        elevGainM = (try? c.decodeIfPresent(Double.self, forKey: .elevGainM)) ?? 0
        avgSpeed = try? c.decodeIfPresent(Double.self, forKey: .avgSpeed)
        topSpeed = try? c.decodeIfPresent(Double.self, forKey: .topSpeed)
        avgHR = try? c.decodeIfPresent(Double.self, forKey: .avgHR)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? ""
        fromRoamr = (try? c.decodeIfPresent(Bool.self, forKey: .fromRoamr)) ?? false
    }
}

/// Finds the walks that go with a hug and keeps them in sync. Read-only on Roamr and Apple Health.
@MainActor
enum RoamrWalks {
    /// Walks overlapping the hug or within this long of it are offered.
    static let window: TimeInterval = 2 * 3600
    /// Auto-sync looks this far back.
    static let syncDays = 60

    private static func fromTrip(_ t: WellnessBridge.Trip) -> LinkedWalk {
        LinkedWalk(id: t.id, kind: t.kind, start: t.start, end: t.end, distanceM: t.distanceM, movingSec: t.movingSec,
                   elevGainM: t.elevGainM, avgSpeed: t.avgSpeed > 0 ? t.avgSpeed : nil,
                   topSpeed: t.topSpeed > 0 ? t.topSpeed : nil, avgHR: t.avgHR, source: "Roamr", fromRoamr: true)
    }

    /// Roamr has shared trips at least once (it's installed and updated).
    static var roamrShares: Bool { WellnessBridge.roamr() != nil }

    /// Walks, hikes and runs touching `from...to`: Roamr's feed first, then Health workouts it doesn't already list.
    /// `ask` shows the Health permission sheet if it was never shown (only from a button tap).
    static func all(from: Date, to: Date, ask: Bool) async -> [LinkedWalk] {
        var out = (WellnessBridge.roamr()?.trips ?? [])
            .filter { $0.isOnFoot && $0.end >= from && $0.start <= to }
            .map(fromTrip)
        let hs = HealthService.shared
        if hs.isAvailable && !DemoData.isOn {
            if ask { _ = await hs.requestAccess() }
            let workouts = await hs.footWorkouts(from: from, to: to)
            for w in workouts where !w.bundleID.hasPrefix("com.troydunn.rootbound") {
                let fromRoamr = w.bundleID.hasPrefix(WellnessLinks.roamrBundleID)
                let secs = max(1, w.end.timeIntervalSince(w.start))
                let walk = LinkedWalk(id: w.id, kind: w.kind.rawValue, start: w.start, end: w.end, distanceM: w.distanceM,
                                      movingSec: 0, elevGainM: w.elevGainM, avgSpeed: w.distanceM > 0 ? w.distanceM / secs : nil,
                                      topSpeed: nil, avgHR: w.avgHR, source: fromRoamr ? "Roamr" : w.source, fromRoamr: false)
                if let i = out.firstIndex(where: { $0.sameWalk(as: walk) }) {
                    // Same walk in both: keep Roamr's numbers, borrow the Watch's heart rate.
                    if out[i].avgHR == nil { out[i].avgHR = walk.avgHR }
                } else {
                    out.append(walk)
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// The hug's time span widened by the ±2 h window.
    static func span(start: Date, minutes: Double) -> (Date, Date) {
        (start.addingTimeInterval(-window), start.addingTimeInterval(max(minutes, 1) * 60 + window))
    }

    /// Walks overlapping, or within ±2 h of, a hug starting at `start`. Nearest first.
    static func candidates(start: Date, minutes: Double) async -> [LinkedWalk] {
        let (a, b) = span(start: start, minutes: minutes)
        return await all(from: a, to: b, ask: true)
            .sorted { distance($0, to: start) < distance($1, to: start) }
    }

    private static func distance(_ w: LinkedWalk, to date: Date) -> TimeInterval {
        if w.start <= date && w.end >= date { return 0 }
        return min(abs(w.start.timeIntervalSince(date)), abs(w.end.timeIntervalSince(date)))
    }

    static func matches(_ hug: Hug, in walks: [LinkedWalk]) -> [LinkedWalk] {
        let (a, b) = span(start: hug.date, minutes: hug.durationMin)
        return walks.filter { $0.end >= a && $0.start <= b }
    }

    /// App open / "Sync Roamr": hugs of the last 60 days that never had walks looked at get the walks around them
    /// (no prompt); walks already attached get Roamr's latest numbers (a trim, late heart rate).
    /// Returns how many walks were newly attached.
    /// An automatic sync is already running (app open and becoming active both start one at launch).
    private static var autoSyncRunning = false

    @discardableResult
    static func sync(_ hugs: [Hug], context: ModelContext, ask: Bool = false) async -> Int {
        guard !DemoData.isOn else { return 0 }
        // Automatic syncs don't pile up; "Sync Roamr" (ask) always runs.
        if !ask {
            guard !autoSyncRunning else { return 0 }
            autoSyncRunning = true
        }
        defer { if !ask { autoSyncRunning = false } }
        let since = Date().addingTimeInterval(-Double(syncDays) * 86400)
        let recent = hugs.filter { $0.date >= since }
        let open = recent.filter { !$0.hasWalkList }
        let linked = recent.filter { !$0.linkedWalks.isEmpty }
        guard !open.isEmpty || !linked.isEmpty || ask else { return 0 }
        let first = recent.map(\.date).min() ?? since
        let walks = await all(from: first.addingTimeInterval(-window), to: Date(), ask: ask)
        guard !walks.isEmpty else { return 0 }
        var added = 0
        var changed = false
        // A hug deleted while Health was answering is left alone.
        for h in open where !h.isDeleted && h.modelContext != nil && !h.hasWalkList {
            let m = matches(h, in: walks)
            guard !m.isEmpty else { continue }
            h.linkedWalks = m
            added += m.count
            changed = true
        }
        for h in linked where !h.isDeleted && h.modelContext != nil {
            let fresh = h.linkedWalks.map { w in walks.first(where: { $0.id == w.id }) ?? w }
            if fresh != h.linkedWalks { h.linkedWalks = fresh; changed = true }
        }
        if changed { try? context.save() }
        return added
    }
}
