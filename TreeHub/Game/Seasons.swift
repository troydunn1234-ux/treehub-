import Foundation
import SwiftUI

// MARK: - Seasonal events

/// A time-limited event, picked from today's date: bonus XP for every hug during it, extra for its featured
/// trees, and an event badge for hugging a featured tree while it runs.
struct SeasonalEvent: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String
    let colors: [Color]
    /// Inclusive month/day window. A window that wraps the new year (Dec → Feb) works too.
    let start: (month: Int, day: Int)
    let end: (month: Int, day: Int)
    let bonusXP: Int
    let featuredBonusXP: Int
    /// Lower-case keywords: a hug on a tree whose species contains one of these is "featured".
    let featured: [String]
    let featuredLabel: String
    let badgeName: String
    let badgeSymbol: String

    static func == (a: SeasonalEvent, b: SeasonalEvent) -> Bool { a.id == b.id }

    static let all: [SeasonalEvent] = [
        SeasonalEvent(id: "spring-blossoms", name: "Spring Blossoms", tagline: "Flowering trees are waking up. Go find one in bloom.",
                      symbol: "camera.macro", colors: [Color(red: 1.0, green: 0.62, blue: 0.78), Color(red: 0.86, green: 0.36, blue: 0.62)],
                      start: (3, 1), end: (5, 31), bonusXP: 25, featuredBonusXP: 40,
                      featured: ["cherry", "plum", "magnolia", "dogwood", "redbud", "jacaranda", "apple", "pear", "almond", "peach",
                                 "crabapple", "blossom", "wisteria", "tulip tree", "catalpa", "lilac"],
                      featuredLabel: "flowering trees", badgeName: "Blossom Chaser", badgeSymbol: "camera.macro"),
        SeasonalEvent(id: "summer-shade", name: "Summer Shade", tagline: "Big canopies, cool shade. Rest under a giant.",
                      symbol: "sun.max.fill", colors: [Color(red: 1.0, green: 0.82, blue: 0.30), Color(red: 0.36, green: 0.72, blue: 0.42)],
                      start: (6, 1), end: (9, 21), bonusXP: 25, featuredBonusXP: 40,
                      featured: ["oak", "sycamore", "plane", "maple", "elm", "linden", "walnut", "chestnut", "fig", "banyan",
                                 "cottonwood", "poplar", "willow", "beech", "shade"],
                      featuredLabel: "big shade trees", badgeName: "Shade Seeker", badgeSymbol: "sun.max.fill"),
        SeasonalEvent(id: "autumn-leaves", name: "Autumn Leaves", tagline: "The color is turning. Hug a tree mid-change.",
                      symbol: "leaf.fill", colors: [Color(red: 1.0, green: 0.58, blue: 0.20), Color(red: 0.80, green: 0.25, blue: 0.15)],
                      start: (9, 22), end: (11, 30), bonusXP: 25, featuredBonusXP: 40,
                      featured: ["maple", "oak", "ginkgo", "birch", "aspen", "sycamore", "elm", "beech", "sweetgum", "liquidambar",
                                 "hickory", "tupelo", "dogwood", "larch", "pistache", "persimmon"],
                      featuredLabel: "trees that change color", badgeName: "Leaf Peeper", badgeSymbol: "leaf.fill"),
        SeasonalEvent(id: "winter-evergreens", name: "Winter Evergreens", tagline: "Green through the cold. Find a tree that never lets go.",
                      symbol: "snowflake", colors: [Color(red: 0.55, green: 0.85, blue: 1.0), Color(red: 0.18, green: 0.48, blue: 0.40)],
                      start: (12, 1), end: (2, 29), bonusXP: 25, featuredBonusXP: 40,
                      featured: ["pine", "fir", "spruce", "cedar", "redwood", "sequoia", "cypress", "juniper", "hemlock", "yew",
                                 "holly", "live oak", "eucalyptus", "olive", "bay", "laurel", "evergreen", "magnolia"],
                      featuredLabel: "evergreens", badgeName: "Evergreen Heart", badgeSymbol: "snowflake"),
    ]

    private static func ordinal(_ m: Int, _ d: Int) -> Int { m * 100 + d }

    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        let v = Self.ordinal(c.month ?? 1, c.day ?? 1)
        let s = Self.ordinal(start.month, start.day), e = Self.ordinal(end.month, end.day)
        return s <= e ? (v >= s && v <= e) : (v >= s || v <= e)
    }

    static func active(on date: Date = Date(), calendar: Calendar = .current) -> SeasonalEvent? {
        all.first { $0.isActive(on: date, calendar: calendar) }
    }

    func features(species: String) -> Bool {
        let s = species.lowercased()
        return !s.isEmpty && featured.contains { s.contains($0) }
    }

    /// The last day of this event's current run, from `date` (which should be inside it).
    func endDate(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        var year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if start.month > end.month && month >= start.month { year += 1 }   // Dec → Feb wraps into next year
        var c = DateComponents(year: year, month: end.month, day: 1)
        let first = calendar.date(from: c) ?? date
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        c.day = min(end.day, days)
        let last = calendar.date(from: c) ?? date
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: last) ?? last
    }

    func daysLeft(from date: Date = Date(), calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: date), b = calendar.startOfDay(for: endDate(from: date, calendar: calendar))
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

// MARK: - Species rarity

/// How rare a tree species is to find, for the grove's card frames and the rare-find celebration.
/// Matched by keywords in the species name; anything unknown (or no species) is Common.
enum SpeciesRarity {
    private static let table: [(Rarity, [String])] = [
        (.legendary, ["giant sequoia", "sierra redwood", "bristlecone", "baobab", "dragon", "wollemi", "general sherman",
                      "rainbow eucalyptus", "socotra", "kauri", "methuselah", "angel oak", "tule"]),
        (.epic, ["redwood", "sequoia", "ginkgo", "monkey puzzle", "joshua", "banyan", "cork oak", "madrone", "madrona",
                 "arbutus", "jacaranda", "bald cypress", "baldcypress", "japanese maple", "weeping willow", "camphor",
                 "torrey pine", "monterey cypress", "dawn redwood", "kapok", "moreton bay fig", "silk floss"]),
        (.rare, ["magnolia", "cherry", "dogwood", "sycamore", "plane", "birch", "beech", "cedar", "cypress", "live oak",
                 "valley oak", "blue oak", "black oak", "olive", "chestnut", "walnut", "aspen", "larch", "yew", "holly",
                 "redbud", "tulip", "catalpa", "persimmon", "fig", "hemlock", "juniper", "spruce", "buckeye", "tupelo",
                 "sweetgum", "liquidambar", "pistache", "linden", "mulberry", "laurel", "bay"]),
    ]

    static func rarity(for species: String) -> Rarity {
        let s = species.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return .common }
        for (r, words) in table where words.contains(where: { s.contains($0) }) { return r }
        return .common
    }

    /// Bonus XP the first time you hug a species of this rarity.
    static func firstFindXP(_ r: Rarity) -> Int {
        switch r {
        case .common: return 0
        case .rare: return 20
        case .epic: return 50
        case .legendary: return 100
        }
    }
}
