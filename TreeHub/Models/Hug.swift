import Foundation
import SwiftData
import CoreLocation

// All stored properties have defaults so the store can sync through iCloud (CloudKit).

@Model
final class Hug {
    var id: UUID = UUID()
    var date: Date = Date()

    // The tree
    var treeID: UUID = UUID()
    var treeName: String = ""
    var species: String = ""

    // Where
    var latitude: Double?
    var longitude: Double?
    var placeName: String = ""

    // Photos (stored outside the database file)
    @Attribute(.externalStorage) var treePhoto: Data?
    @Attribute(.externalStorage) var selfiePhoto: Data?
    /// Legacy third photo slot (an old watch-app screenshot). No longer offered for new hugs; kept so old hugs keep it.
    @Attribute(.externalStorage) var garminPhoto: Data?

    // Vibe
    var tagsRaw: String = ""
    var barefoot: Bool = false
    /// Feet in a creek, lake or the ocean during the hug.
    var feetInWater: Bool = false
    /// Where the tree stands: "" (not set), "land", "edge" (water's edge / roots in water) or "water" (the whole tree is in water).
    var waterSetting: String = ""
    var weather: String = ""
    var moodBefore: Int = 0
    var moodAfter: Int = 0
    var notes: String = ""

    // Breathwork stats (Apple Watch heart data via Apple Health)
    var exercise: String = ""
    var durationMin: Double = 0
    var avgHR: Double?
    var minHR: Double?
    var maxHR: Double?
    var respRate: Double?
    // Legacy fields from an older third-party-watch flow. Not shown or edited any more; kept so the store
    // (and its iCloud schema) stays compatible.
    var stressStart: Double?
    var stressEnd: Double?
    var bodyBattery: Double?

    // Apple Watch calm metrics: first and last heart rate of the hug (start -> end drop) and average HRV (ms).
    var hrStart: Double?
    var hrEnd: Double?
    var hrv: Double?
    /// Logged from the Rootbound Watch app's "Start hug" timer.
    var fromWatch: Bool = false

    /// Breath / mindful sessions linked to this hug (JSON of [LinkedSession]).
    /// nil = an older hug from before multi-linking (its sessions are found by time overlap instead);
    /// an empty array = the user linked none.
    var linkedSessionsData: Data?

    // The stroll or hike this hug happened on (Activity.id), if any
    var strollID: UUID?

    // Game
    var xp: Int = 0
    var leafKey: String = ""

    init() {}

    var tags: [String] {
        get { tagsRaw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty } }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasStats: Bool {
        avgHR != nil || respRate != nil || hrv != nil || hrStart != nil
    }

    /// Start -> end heart-rate drop during the hug (bpm; positive = calmer).
    var hrDrop: Double? {
        guard let a = hrStart, let b = hrEnd else { return nil }
        return a - b
    }

    /// Breath sessions linked to this hug, oldest first.
    var linkedSessions: [LinkedSession] {
        get {
            guard let linkedSessionsData,
                  let list = try? JSONDecoder().decode([LinkedSession].self, from: linkedSessionsData) else { return [] }
            return list.sorted { $0.start < $1.start }
        }
        set { linkedSessionsData = try? JSONEncoder().encode(newValue.sorted { $0.start < $1.start }) }
    }

    /// True once the user picked sessions for this hug (even none); older hugs fall back to time overlap.
    var hasLinkList: Bool { linkedSessionsData != nil }

    /// Breathwork minutes for this hug: its linked sessions when there are any, else the hug's own length.
    var breathMinutes: Double {
        let linked = linkedSessions.reduce(0) { $0 + $1.minutes }
        return linked > 0 ? linked : durationMin
    }
}

/// One Still Pointz / Apple Health breath session linked to a hug. Every field but the times decodes with a
/// default, so older or partial records always load.
struct LinkedSession: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// The Still Pointz feed session's id, when it came from there.
    var feedID: UUID? = nil
    var start: Date
    var end: Date
    /// "Still Pointz" or the Health source name.
    var source: String = ""
    var practice: String? = nil
    var avgHR: Double? = nil
    var minHR: Double? = nil
    var startHR: Double? = nil
    var hrDrop: Double? = nil
    var hrv: Double? = nil
    var maxHR: Double? = nil
    var endHR: Double? = nil
    /// Breaths per minute, when Health has it for the window.
    var respRate: Double? = nil

    var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }

    /// "Rooted Breath" from "rooted-breath".
    var practiceName: String? {
        practice.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
    }

    init(id: UUID = UUID(), feedID: UUID? = nil, start: Date, end: Date, source: String, practice: String? = nil,
         avgHR: Double? = nil, minHR: Double? = nil, startHR: Double? = nil, hrDrop: Double? = nil, hrv: Double? = nil,
         respRate: Double? = nil) {
        self.id = id; self.feedID = feedID; self.start = start; self.end = end; self.source = source
        self.practice = practice; self.avgHR = avgHR; self.minHR = minHR; self.startHR = startHR
        self.hrDrop = hrDrop; self.hrv = hrv; self.respRate = respRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        feedID = try c.decodeIfPresent(UUID.self, forKey: .feedID)
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date(timeIntervalSince1970: 0)
        end = try c.decodeIfPresent(Date.self, forKey: .end) ?? start
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        practice = try c.decodeIfPresent(String.self, forKey: .practice)
        avgHR = try c.decodeIfPresent(Double.self, forKey: .avgHR)
        minHR = try c.decodeIfPresent(Double.self, forKey: .minHR)
        startHR = try c.decodeIfPresent(Double.self, forKey: .startHR)
        hrDrop = try c.decodeIfPresent(Double.self, forKey: .hrDrop)
        hrv = try c.decodeIfPresent(Double.self, forKey: .hrv)
        maxHR = try c.decodeIfPresent(Double.self, forKey: .maxHR)
        endHR = try c.decodeIfPresent(Double.self, forKey: .endHR)
        respRate = try c.decodeIfPresent(Double.self, forKey: .respRate)
    }

    /// Practice name, else where it came from ("Mindfulness", "Still Pointz"…).
    var title: String { practiceName ?? (source.isEmpty ? "Breath session" : source) }

    /// Same session (within 90 s), whichever list it came from.
    func sameSession(as other: LinkedSession) -> Bool {
        if let a = feedID, let b = other.feedID { return a == b }
        return abs(start.timeIntervalSince(other.start)) < 90
    }
}

extension Array where Element == LinkedSession {
    var totalMinutes: Double { reduce(0) { $0 + $1.minutes } }
    private static func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    var avgHR: Double? { Self.avg(compactMap(\.avgHR)) }
    var avgDrop: Double? { Self.avg(compactMap(\.hrDrop)) }
    var avgHRV: Double? { Self.avg(compactMap(\.hrv)) }
    var avgResp: Double? { Self.avg(compactMap(\.respRate)) }
    var lowestHR: Double? { compactMap(\.minHR).min() }
}

/// A tree is every hug that shares a treeID.
struct TreeSummary: Identifiable {
    let id: UUID
    var name: String
    var species: String
    var coordinate: CLLocationCoordinate2D?
    var placeName: String
    var hugs: [Hug]           // newest first
    var coverPhoto: Data?

    var hugCount: Int { hugs.count }
    var totalMinutes: Double { hugs.reduce(0) { $0 + $1.durationMin } }
    /// Breathwork minutes with this tree (linked sessions, or each hug's length when it has none).
    var breathMinutes: Double { hugs.reduce(0) { $0 + $1.breathMinutes } }
    var firstHug: Date { hugs.last?.date ?? Date() }
    var lastHug: Date { hugs.first?.date ?? Date() }

    /// 1...5 hearts of friendship
    var bond: Int {
        switch hugCount {
        case 0...1: return 1
        case 2...3: return 2
        case 4...6: return 3
        case 7...11: return 4
        default: return 5
        }
    }

    static func build(from hugs: [Hug]) -> [TreeSummary] {
        let sorted = hugs.sorted { $0.date > $1.date }
        var order: [UUID] = []
        var groups: [UUID: [Hug]] = [:]
        for h in sorted {
            if groups[h.treeID] == nil { order.append(h.treeID) }
            groups[h.treeID, default: []].append(h)
        }
        return order.compactMap { id in
            guard let list = groups[id], let newest = list.first else { return nil }
            let name = list.first(where: { !$0.treeName.isEmpty })?.treeName ?? "Unnamed tree"
            let species = list.first(where: { !$0.species.isEmpty })?.species ?? ""
            let coord = list.first(where: { $0.coordinate != nil })?.coordinate
            let place = list.first(where: { !$0.placeName.isEmpty })?.placeName ?? ""
            // Cover = the oldest tree photo (the first meeting)
            let cover = list.reversed().first(where: { $0.treePhoto != nil })?.treePhoto ?? newest.selfiePhoto
            return TreeSummary(id: id, name: name, species: species, coordinate: coord,
                               placeName: place, hugs: list, coverPhoto: cover)
        }
    }
}
