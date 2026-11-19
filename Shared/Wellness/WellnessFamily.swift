import Foundation

// The family connections that need more than one feed part (all pure, so they're testable):
//  • which Roamr trips passed which Rootbound trees (Rootbound works it out: it alone knows where its trees are,
//    and it publishes only ids and names; Roamr shows "Trees along this walk")
//  • "From your other apps": the few newest things the sibling apps shared, each with a deep link back
//  • calm time and time on foot per day across the apps, and how next-morning HRV looked after calmer days
//    (Pulse Lab's "Stress & recovery across apps")
// Read-only on every app's data, like WellnessConnect.swift.

extension WellnessConnect {
    // MARK: - Trees a trip passed (Rootbound -> rootbound.json tripTrees -> Roamr)

    /// One of Rootbound's trees, as the matcher needs it. Coordinates stay in Rootbound (never published).
    struct TreeSpot {
        var id: UUID
        var name: String
        var species: String
        var lat: Double?
        var lng: Double?
        var hugTimes: [(start: Date, minutes: Double)]
    }

    /// For every on-foot trip that passed at least one tree: the trees (hugged on the trip first, then by name),
    /// at most `maxPerTrip`. Same rules as a tree page's "Walks past this tree" (`tripsPassing`). Trips keep the
    /// feed's order (newest first).
    static func tripTrees(trees: [TreeSpot], trips: [WellnessBridge.Trip], radius: Double = 250,
                          maxPerTrip: Int = 8) -> [WellnessBridge.TripTrees] {
        guard !trips.isEmpty, !trees.isEmpty else { return [] }
        var byTrip: [UUID: [WellnessBridge.NearTree]] = [:]
        for tree in trees {
            for p in tripsPassing(treeLat: tree.lat, treeLng: tree.lng, hugTimes: tree.hugTimes, in: trips, radius: radius) {
                let name = tree.name.trimmingCharacters(in: .whitespacesAndNewlines)
                byTrip[p.trip.id, default: []].append(.init(treeID: tree.id, name: name.isEmpty ? "Unnamed tree" : name,
                                                            species: tree.species, hugged: p.reason == .hugged))
            }
        }
        return trips.compactMap { t in
            guard let list = byTrip[t.id], !list.isEmpty else { return nil }
            let sorted = list.sorted { a, b in
                if a.hugged != b.hugged { return a.hugged }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return WellnessBridge.TripTrees(tripID: t.id, trees: Array(sorted.prefix(maxPerTrip)))
        }
    }

    /// The trees Rootbound says a trip passed (empty when Rootbound is older, isn't installed or found none).
    static func trees(onTrip id: UUID, in part: WellnessBridge.RootboundPart?) -> [WellnessBridge.NearTree] {
        part?.tripTrees?.first(where: { $0.tripID == id })?.trees ?? []
    }

    // MARK: - From your other apps

    /// One thing a sibling app shared, with the link that opens it there.
    struct FamilyItem: Identifiable, Equatable {
        var id: String
        var peer: Peer
        var symbol: String
        var title: String
        var detail: String
        var date: Date
        var url: URL
    }

    /// The newest things the other apps shared in the last `within` (default two days), newest first, at most
    /// `perApp` from one app and `limit` in all. `me` is left out; so is any app `installed` says isn't there.
    static func familyItems(for me: Peer, now: Date = Date(), within: TimeInterval = 48 * 3600, limit: Int = 4,
                            perApp: Int = 2, metric: Bool, installed: (Peer) -> Bool = { _ in true },
                            stillPoint: WellnessBridge.StillPointPart?, rootbound: WellnessBridge.RootboundPart?,
                            roamr: WellnessBridge.RoamrPart?, pulseLab: WellnessBridge.PulseLabPart?) -> [FamilyItem] {
        let since = now.addingTimeInterval(-within)
        let future = now.addingTimeInterval(10 * 60)   // a little clock skew between apps
        func fresh(_ d: Date) -> Bool { d >= since && d <= future }
        var all: [FamilyItem] = []

        if me != Self.rootbound, installed(Self.rootbound), let rb = rootbound {
            for h in rb.hugs where fresh(h.date) {
                let tree = h.tree.trimmingCharacters(in: .whitespacesAndNewlines)
                var parts: [String] = []
                if h.minutes >= 1 { parts.append(minutes(h.minutes)) }
                // In Still Pointz a hug of a minute or more counts as calm time (StillPointWellness.sync).
                parts.append(me == Self.stillPoint && h.minutes >= 1 ? "counts as grounding time here" : "grounding")
                all.append(FamilyItem(id: "rb-" + h.id.uuidString, peer: Self.rootbound, symbol: "tree.fill",
                                      title: tree.isEmpty ? "Tree hug" : "Hugged \(tree)",
                                      detail: parts.joined(separator: " · "), date: h.date,
                                      url: h.treeID.map(rootboundTree) ?? rootboundHome))
            }
        }

        if me != Self.stillPoint, installed(Self.stillPoint), let sp = stillPoint {
            for s in sp.sessions where fresh(s.date) && s.minutes >= 1 {
                var title = practiceName(s.practice) ?? s.kind.capitalized
                if let tree = s.treeName?.trimmingCharacters(in: .whitespacesAndNewlines), !tree.isEmpty {
                    title += " with \(tree)"
                }
                var parts = [minutes(s.minutes)]
                if let drop = s.hrDrop, drop >= 1 { parts.append("heart rate down \(Int(drop.rounded())) bpm") }
                else if !s.isCalm { parts.append("heat") }
                all.append(FamilyItem(id: "sp-" + s.id.uuidString, peer: Self.stillPoint,
                                      symbol: s.isCalm ? "wind" : "flame", title: title,
                                      detail: parts.joined(separator: " · "), date: s.date, url: stillPointSession(s.id)))
            }
        }

        if me != Self.roamr, installed(Self.roamr), let r = roamr {
            for t in r.trips where t.kind != "drive" && fresh(t.end) {
                let near = trees(onTrip: t.id, in: rootbound)
                var detail = minutes(max(t.movingSec, 0) / 60) + " moving"
                if let first = near.first {
                    detail = near.count == 1 ? "passed \(first.name)" : "passed \(first.name) +\(near.count - 1)"
                } else if t.elevGainM >= 30 {
                    detail += metric ? " · \(Int(t.elevGainM.rounded())) m climb" : " · \(Int((t.elevGainM * 3.28084).rounded())) ft climb"
                }
                all.append(FamilyItem(id: "rr-" + t.id.uuidString, peer: Self.roamr, symbol: tripSymbol(t.kind),
                                      title: tripNoun(t.kind) + ", " + distance(t.distanceM, metric: metric),
                                      detail: detail, date: t.end, url: roamrTrip(t.id)))
            }
        }

        if me != Self.pulseLab, installed(Self.pulseLab), let p = pulseLab, p.date == WellnessBridge.dayKey(now), fresh(p.updated) {
            var title: String?
            if let v = p.readiness { title = "Readiness \(Int(v.rounded()))" }
            else if let v = p.whoopRecovery { title = "WHOOP recovery \(Int(v.rounded()))%" }
            if let title {
                var parts: [String] = []
                if let m = p.sleepMinutes, m > 0 { parts.append("slept " + minutes(m)) }
                if let h = p.hrv { parts.append("HRV \(Int(h.rounded())) ms") }
                all.append(FamilyItem(id: "pl-" + p.date, peer: Self.pulseLab, symbol: "waveform.path.ecg", title: title,
                                      detail: parts.isEmpty ? "today" : parts.joined(separator: " · "),
                                      date: p.updated, url: pulseLabToday))
            }
        }

        var counts: [String: Int] = [:]
        var out: [FamilyItem] = []
        for item in all.sorted(by: { $0.date > $1.date }) where out.count < limit {
            let n = counts[item.peer.scheme, default: 0]
            guard n < perApp else { continue }
            counts[item.peer.scheme] = n + 1
            out.append(item)
        }
        return out
    }

    /// Screenshot rows for "-demo" runs (every sibling of `me`).
    static func sampleFamilyItems(for me: Peer, now: Date = Date(), metric: Bool) -> [FamilyItem] {
        let id = UUID(uuidString: "6E1F1C1A-0000-4000-8000-00000000D3E0")!
        let all = [
            FamilyItem(id: "demo-rb", peer: rootbound, symbol: "tree.fill", title: "Hugged Grandpa Oak",
                       detail: me == stillPoint ? "6 min · counts as grounding time here" : "6 min · grounding",
                       date: now.addingTimeInterval(-40 * 60), url: rootboundTree(id)),
            FamilyItem(id: "demo-sp", peer: stillPoint, symbol: "wind", title: "Rooted Breath with Grandpa Oak",
                       detail: "5 min · heart rate down 9 bpm", date: now.addingTimeInterval(-35 * 60), url: stillPointSession(id)),
            FamilyItem(id: "demo-rr", peer: roamr, symbol: "figure.hiking", title: "Hike, " + distance(3860, metric: metric),
                       detail: "passed Grandpa Oak +1", date: now.addingTimeInterval(-2 * 3600), url: roamrTrip(id)),
            FamilyItem(id: "demo-pl", peer: pulseLab, symbol: "waveform.path.ecg", title: "Readiness 74",
                       detail: "slept 7 h 20 min · HRV 58 ms", date: now.addingTimeInterval(-25 * 60), url: pulseLabToday),
        ]
        return all.filter { $0.peer != me }.sorted { $0.date > $1.date }
    }

    static func tripNoun(_ kind: String) -> String {
        switch kind {
        case "run": return "Run"
        case "hike": return "Hike"
        case "bike": return "Ride"
        case "drive": return "Drive"
        default: return "Walk"
        }
    }

    static func tripSymbol(_ kind: String) -> String {
        switch kind {
        case "run": return "figure.run"
        case "hike": return "figure.hiking"
        case "bike": return "figure.outdoor.cycle"
        case "drive": return "car.fill"
        default: return "figure.walk"
        }
    }

    // MARK: - Calm time and time on foot per day (Pulse Lab)

    struct DayLoad: Identifiable, Equatable {
        var day: Date
        /// Still Pointz guided practice (not sauna / steam).
        var calmMin: Double = 0
        /// Rootbound hugs not already linked to one of those Still Pointz sessions (no double counting).
        var hugMin: Double = 0
        /// Roamr walks, runs and hikes: moving time and distance.
        var onFootMin: Double = 0
        var onFootM: Double = 0
        var id: Date { day }
        var groundedMin: Double { calmMin + hugMin }
    }

    /// The last `count` days ending with `endingOn` (oldest first), from whichever parts there are.
    static func dayLoads(_ count: Int, endingOn end: Date, stillPoint: WellnessBridge.StillPointPart?,
                         rootbound: WellnessBridge.RootboundPart?, roamr: WellnessBridge.RoamrPart?) -> [DayLoad] {
        let cal = Calendar.current
        let last = cal.startOfDay(for: end)
        let days = (0..<max(0, count)).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: last) }
        var loads = Dictionary(uniqueKeysWithValues: days.map { ($0, DayLoad(day: $0)) })
        let spIDs = Set(stillPoint?.sessions.map(\.id) ?? [])
        for s in stillPoint?.sessions ?? [] where s.isCalm {
            let d = cal.startOfDay(for: s.date)
            loads[d]?.calmMin += max(0, s.minutes)
        }
        for h in rootbound?.hugs ?? [] {
            if let linked = h.sessionIDs, linked.contains(where: spIDs.contains) { continue }
            let d = cal.startOfDay(for: h.date)
            loads[d]?.hugMin += max(0, h.minutes)
        }
        for t in roamr?.trips ?? [] where t.isOnFoot {
            let d = cal.startOfDay(for: t.start)
            loads[d]?.onFootMin += max(0, t.movingSec) / 60
            loads[d]?.onFootM += max(0, t.distanceM)
        }
        return days.compactMap { loads[$0] }
    }

    struct CalmEffect: Equatable {
        /// Average HRV the morning after a day with at least `threshold` grounded minutes, and after the others.
        var afterCalm: Double
        var afterOther: Double
        var calmDays: Int
        var otherDays: Int
        var threshold: Double
    }

    /// Next-morning HRV after calmer days vs the other days. `hrv` is keyed by start of day. Nil until each side
    /// has at least `minDays` days with a next-morning reading (a handful of days says nothing).
    static func calmEffect(_ loads: [DayLoad], hrv: [Date: Double], threshold: Double = 10,
                           minDays: Int = 3) -> CalmEffect? {
        let cal = Calendar.current
        var calm: [Double] = [], other: [Double] = []
        for l in loads {
            guard let next = cal.date(byAdding: .day, value: 1, to: l.day),
                  let v = hrv[cal.startOfDay(for: next)], v > 0 else { continue }
            if l.groundedMin >= threshold { calm.append(v) } else { other.append(v) }
        }
        guard calm.count >= minDays, other.count >= minDays else { return nil }
        return CalmEffect(afterCalm: calm.reduce(0, +) / Double(calm.count),
                          afterOther: other.reduce(0, +) / Double(other.count),
                          calmDays: calm.count, otherDays: other.count, threshold: threshold)
    }

    /// Screenshot week for "-demo" runs (oldest first).
    static func sampleDayLoads(endingOn end: Date = Date()) -> [DayLoad] {
        let cal = Calendar.current
        let last = cal.startOfDay(for: end)
        let calm: [Double] = [12, 0, 18, 9, 22, 6, 18]
        let hugs: [Double] = [0, 5, 0, 0, 8, 0, 6]
        let foot: [Double] = [35, 62, 0, 28, 80, 15, 48]
        return (0..<7).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: i - 6, to: last) else { return nil }
            return DayLoad(day: d, calmMin: calm[i], hugMin: hugs[i], onFootMin: foot[i], onFootM: foot[i] * 80)
        }
    }
}
