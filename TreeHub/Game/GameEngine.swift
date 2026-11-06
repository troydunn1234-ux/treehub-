import Foundation
import SwiftUI
import CoreLocation

enum Rarity: Int, CaseIterable, Comparable {
    case common, rare, epic, legendary

    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .common: return "Common"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    var color: Color {
        switch self {
        case .common: return Color(red: 0.55, green: 0.76, blue: 0.60)
        case .rare: return Color(red: 0.31, green: 0.70, blue: 1.0)
        case .epic: return Color(red: 0.72, green: 0.48, blue: 1.0)
        case .legendary: return Color(red: 1.0, green: 0.72, blue: 0.24)
        }
    }
}

// MARK: - Hug tags

struct HugTag: Identifiable, Hashable {
    let id: String
    let label: String
    let symbol: String

    static let all: [HugTag] = [
        HugTag(id: "hike", label: "Hike", symbol: "figure.hiking"),
        HugTag(id: "chill", label: "Chill", symbol: "cloud.sun.fill"),
        HugTag(id: "park", label: "Park", symbol: "tree.fill"),
        HugTag(id: "sober", label: "Sober", symbol: "drop.fill"),
        HugTag(id: "solo", label: "Solo", symbol: "person.fill"),
        HugTag(id: "company", label: "With someone", symbol: "person.2.fill"),
        HugTag(id: "sunrise", label: "Sunrise", symbol: "sunrise.fill"),
        HugTag(id: "sunset", label: "Sunset", symbol: "sunset.fill"),
        HugTag(id: "trail", label: "Trail", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill"),
        HugTag(id: "beach", label: "Beach", symbol: "water.waves"),
    ]

    static func label(_ id: String) -> String { all.first { $0.id == id }?.label ?? id.capitalized }
    static func symbol(_ id: String) -> String { all.first { $0.id == id }?.symbol ?? "tag.fill" }
}

// MARK: - Leaves (random collectible dropped by every hug)

enum LeafShape { case oval, heart, ginkgo, maple, oak, needle }

struct LeafType: Identifiable {
    let id: String
    let name: String
    let rarity: Rarity
    let shape: LeafShape
    let colors: [Color]
    let blurb: String

    static let all: [LeafType] = [
        LeafType(id: "oak", name: "Oak Leaf", rarity: .common, shape: .oak,
                 colors: [Color(red: 0.49, green: 0.70, blue: 0.26), Color(red: 0.30, green: 0.52, blue: 0.20)],
                 blurb: "Steady, strong, always there."),
        LeafType(id: "maple", name: "Maple Leaf", rarity: .common, shape: .maple,
                 colors: [Color(red: 0.95, green: 0.50, blue: 0.22), Color(red: 0.80, green: 0.25, blue: 0.15)],
                 blurb: "Turns brighter when it lets go."),
        LeafType(id: "birch", name: "Birch Leaf", rarity: .common, shape: .oval,
                 colors: [Color(red: 0.80, green: 0.86, blue: 0.32), Color(red: 0.52, green: 0.66, blue: 0.20)],
                 blurb: "Light as a first breath."),
        LeafType(id: "bay", name: "Bay Laurel", rarity: .common, shape: .oval,
                 colors: [Color(red: 0.38, green: 0.58, blue: 0.32), Color(red: 0.22, green: 0.40, blue: 0.24)],
                 blurb: "Smells like a California hillside."),
        LeafType(id: "ginkgo", name: "Ginkgo Fan", rarity: .rare, shape: .ginkgo,
                 colors: [Color(red: 1.0, green: 0.84, blue: 0.30), Color(red: 0.93, green: 0.64, blue: 0.12)],
                 blurb: "From a tree older than the dinosaurs."),
        LeafType(id: "redwood", name: "Redwood Sprig", rarity: .rare, shape: .needle,
                 colors: [Color(red: 0.26, green: 0.55, blue: 0.33), Color(red: 0.14, green: 0.36, blue: 0.22)],
                 blurb: "A piece of the tallest beings alive."),
        LeafType(id: "heart", name: "Heart Leaf", rarity: .rare, shape: .heart,
                 colors: [Color(red: 1.0, green: 0.52, blue: 0.58), Color(red: 0.86, green: 0.28, blue: 0.40)],
                 blurb: "The tree hugged you back."),
        LeafType(id: "eucalyptus", name: "Silver Eucalyptus", rarity: .rare, shape: .oval,
                 colors: [Color(red: 0.72, green: 0.83, blue: 0.80), Color(red: 0.47, green: 0.62, blue: 0.60)],
                 blurb: "Cool, clear air in a leaf."),
        LeafType(id: "crystal", name: "Crystal Leaf", rarity: .epic, shape: .oval,
                 colors: [Color(red: 0.55, green: 0.95, blue: 1.0), Color(red: 0.60, green: 0.45, blue: 1.0)],
                 blurb: "Forms only in total stillness."),
        LeafType(id: "ember", name: "Ember Maple", rarity: .epic, shape: .maple,
                 colors: [Color(red: 1.0, green: 0.80, blue: 0.20), Color(red: 0.95, green: 0.20, blue: 0.20)],
                 blurb: "Still warm from the sunset."),
        LeafType(id: "moonlit", name: "Moonlit Leaf", rarity: .legendary, shape: .heart,
                 colors: [Color(red: 0.85, green: 0.92, blue: 1.0), Color(red: 0.35, green: 0.45, blue: 0.85)],
                 blurb: "Glows faintly. Nobody knows why."),
        LeafType(id: "elder", name: "Golden Elder Leaf", rarity: .legendary, shape: .oak,
                 colors: [Color(red: 1.0, green: 0.92, blue: 0.55), Color(red: 0.85, green: 0.58, blue: 0.10)],
                 blurb: "Said to fall once a century."),
    ]

    static func find(_ id: String) -> LeafType? { all.first { $0.id == id } }
}

// MARK: - Levels

struct LevelInfo {
    let level: Int
    let title: String
    let xpIntoLevel: Int
    let xpForNext: Int
    var progress: Double { xpForNext == 0 ? 1 : Double(xpIntoLevel) / Double(xpForNext) }
}

// MARK: - Badges

struct BadgeState: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let rarity: Rarity
    let progress: Double   // 0...1
    let progressText: String
    var earned: Bool { progress >= 1 }
}

struct XPBreakdown {
    var lines: [(String, Int)] = []
    var total: Int { lines.reduce(0) { $0 + $1.1 } }
    mutating func add(_ label: String, _ v: Int) { if v > 0 { lines.append((label, v)) } }
}

enum GameEngine {

    // MARK: XP

    static func xp(for hug: Hug, existing: [Hug]) -> XPBreakdown {
        var b = XPBreakdown()
        b.add("Tree hug", 50)
        if hug.durationMin > 0 { b.add("Breathwork \(Format.minutes(hug.durationMin))", min(Int(hug.durationMin.rounded()) * 5, 150)) }
        if hug.barefoot { b.add("Barefoot grounding", 25) }
        if hug.treePhoto != nil { b.add("Tree photo", 10) }
        if hug.selfiePhoto != nil { b.add("Tree selfie", 10) }
        if hug.hasStats || hug.garminPhoto != nil { b.add("Garmin stats", 15) }
        if hug.coordinate != nil { b.add("Pinned on the map", 5) }
        let others = existing.filter { $0.id != hug.id }
        if !others.contains(where: { $0.treeID == hug.treeID }) { b.add("New tree friend", 40) }
        let sp = hug.species.lowercased().trimmingCharacters(in: .whitespaces)
        if !sp.isEmpty && !others.contains(where: { $0.species.lowercased().trimmingCharacters(in: .whitespaces) == sp }) {
            b.add("New species", 30)
        }
        let streak = currentStreak(others + [hug])
        if streak >= 2 { b.add("\(streak)-day streak", min(streak * 10, 70)) }
        return b
    }

    static func xp(for activity: Activity) -> Int {
        let miles = activity.distanceM / 1609.344
        switch activity.kind {
        case .walk, .hike, .run: return 20 + Int(miles * 20) + Int(activity.elevGainM / 30)
        case .bike: return 20 + Int(miles * 6)
        case .drive: return 10 + Int(min(miles, 300))
        }
    }

    static func totalXP(hugs: [Hug], activities: [Activity]) -> Int {
        hugs.reduce(0) { $0 + $1.xp } + activities.reduce(0) { $0 + xp(for: $1) }
    }

    /// Level n starts at 75·n·(n−1) XP: 0, 150, 450, 900, 1500…
    static func level(for xp: Int) -> LevelInfo {
        var n = 1
        while 75 * (n + 1) * n <= xp { n += 1 }
        let start = 75 * n * (n - 1)
        let next = 75 * (n + 1) * n
        return LevelInfo(level: n, title: rankTitle(n), xpIntoLevel: xp - start, xpForNext: next - start)
    }

    static func rankTitle(_ level: Int) -> String {
        switch level {
        case 1: return "Seedling"
        case 2: return "Sprout"
        case 3...4: return "Sapling"
        case 5...7: return "Young Grove"
        case 8...11: return "Deep Rooted"
        case 12...15: return "Canopy Keeper"
        case 16...19: return "Old Growth"
        case 20...24: return "Forest Elder"
        default: return "Ancient One"
        }
    }

    // MARK: Leaf drop

    /// Deterministic per hug id, with better odds for a deeper session.
    static func rollLeaf(for hug: Hug) -> LeafType {
        var rng = SeededRNG(seed: hug.id.uuidString)
        var weights: [Rarity: Double] = [.common: 60, .rare: 28, .epic: 9, .legendary: 3]
        var boost = 1.0
        if hug.barefoot { boost += 0.35 }
        if hug.durationMin >= 12 { boost += 0.35 }
        if hug.durationMin >= 20 { boost += 0.3 }
        if hug.selfiePhoto != nil { boost += 0.1 }
        weights[.epic]! *= boost
        weights[.legendary]! *= boost
        weights[.rare]! *= (1 + (boost - 1) / 2)
        let total = weights.values.reduce(0, +)
        var roll = rng.next() * total
        var rarity: Rarity = .common
        for r in Rarity.allCases.reversed() {
            let w = weights[r] ?? 0
            if roll < w { rarity = r; break }
            roll -= w
        }
        let pool = LeafType.all.filter { $0.rarity == rarity }
        return pool[Int(rng.next() * Double(pool.count)) % pool.count]
    }

    // MARK: Streaks

    static func currentStreak(_ hugs: [Hug]) -> Int {
        let cal = Calendar.current
        let days = Set(hugs.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let y = cal.date(byAdding: .day, value: -1, to: day), days.contains(y) else { return 0 }
            day = y
        }
        var n = 0
        while days.contains(day) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    static func bestStreak(_ hugs: [Hug]) -> Int {
        let cal = Calendar.current
        let days = Set(hugs.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    // MARK: Badges

    static func badges(hugs: [Hug], activities: [Activity]) -> [BadgeState] {
        let cal = Calendar.current
        let trees = TreeSummary.build(from: hugs)
        let species = Set(hugs.map { $0.species.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let totalMin = hugs.reduce(0) { $0 + $1.durationMin }
        let longest = hugs.map(\.durationMin).max() ?? 0
        let maxSameTree = trees.map(\.hugCount).max() ?? 0
        let best = bestStreak(hugs)
        let hours = hugs.map { cal.component(.hour, from: $0.date) }
        let seasons = Set(hugs.map { season(of: $0.date) })
        let tagCount: (String) -> Int = { tag in hugs.filter { $0.tags.contains(tag) }.count }
        let stressDrop = hugs.compactMap { h -> Double? in
            guard let a = h.stressStart, let b = h.stressEnd else { return nil }
            return a - b
        }.max() ?? 0

        // Farthest apart two trees (km)
        let coords = trees.compactMap(\.coordinate)
        var farthest = 0.0
        if coords.count > 1 {
            for i in 0..<coords.count { for j in (i + 1)..<coords.count { farthest = max(farthest, Geo.distance(coords[i], coords[j])) } }
        }

        let onFoot = activities.filter { $0.kind.isOnFoot }
        let movedMiles = activities.filter { $0.kind != .drive }.reduce(0) { $0 + $1.distanceM } / 1609.344
        let longestRunKm = activities.filter { $0.kind == .run }.map(\.distanceM).max().map { $0 / 1000 } ?? 0
        let bestClimbFt = onFoot.map(\.elevGainM).max().map { $0 * 3.28084 } ?? 0
        let longestDriveMi = activities.filter { $0.kind == .drive }.map(\.distanceM).max().map { $0 / 1609.344 } ?? 0
        let rideMiles = activities.filter { $0.kind == .bike }.reduce(0) { $0 + $1.distanceM } / 1609.344
        let hikeDays = Set(activities.filter { $0.kind == .hike || $0.kind == .walk }.map { cal.startOfDay(for: $0.start) })
        let trailHugs = hugs.filter { $0.tags.contains("hike") && hikeDays.contains(cal.startOfDay(for: $0.date)) }.count

        func b(_ id: String, _ name: String, _ detail: String, _ symbol: String, _ r: Rarity, _ value: Double, _ goal: Double, unit: String = "") -> BadgeState {
            let p = goal <= 0 ? 0 : min(1, value / goal)
            let v = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
            let g = goal == goal.rounded() ? "\(Int(goal))" : String(format: "%.1f", goal)
            return BadgeState(id: id, name: name, detail: detail, symbol: symbol, rarity: r, progress: p,
                              progressText: "\(min(value, goal) == goal ? g : v) / \(g)\(unit)")
        }
        func flag(_ id: String, _ name: String, _ detail: String, _ symbol: String, _ r: Rarity, _ done: Bool) -> BadgeState {
            BadgeState(id: id, name: name, detail: detail, symbol: symbol, rarity: r, progress: done ? 1 : 0,
                       progressText: done ? "Unlocked" : "Locked")
        }

        return [
            // Hugging
            b("first-hug", "First Embrace", "Hug your first tree", "heart.fill", .common, Double(hugs.count), 1),
            b("hugs-5", "Tree Whisperer", "Hug 5 times", "leaf.fill", .common, Double(hugs.count), 5),
            b("hugs-25", "Grove Keeper", "Hug 25 times", "tree.fill", .rare, Double(hugs.count), 25),
            b("hugs-100", "Forest Guardian", "Hug 100 times", "shield.lefthalf.filled", .legendary, Double(hugs.count), 100),
            flag("barefoot", "Grounded", "Hug a tree barefoot", "shoeprints.fill", .common, hugs.contains { $0.barefoot }),
            b("barefoot-10", "Earth Connected", "10 barefoot hugs", "globe.americas.fill", .epic, Double(hugs.filter(\.barefoot).count), 10),
            flag("stats", "Breath of the Forest", "Log a hug with Garmin stats", "wind", .common, hugs.contains { $0.hasStats || $0.garminPhoto != nil }),
            b("twelve", "Twelve-Minute Stillness", "A 12+ minute session", "hourglass", .rare, longest, 12, unit: " min"),
            b("twenty", "Deep Roots", "A 20+ minute session", "arrow.down.to.line.compact", .epic, longest, 20, unit: " min"),
            b("min-60", "Hour of Breath", "60 total breathwork minutes", "lungs.fill", .rare, totalMin, 60, unit: " min"),
            b("min-300", "Breath Monk", "300 total breathwork minutes", "sparkles", .legendary, totalMin, 300, unit: " min"),
            b("same-3", "Loyal Friend", "Hug the same tree 3 times", "person.2.fill", .rare, Double(maxSameTree), 3),
            b("same-10", "Soulmate Tree", "Hug the same tree 10 times", "heart.circle.fill", .epic, Double(maxSameTree), 10),
            b("trees-5", "Wanderer", "Befriend 5 different trees", "map.fill", .rare, Double(trees.count), 5),
            b("trees-15", "Explorer", "Befriend 15 different trees", "binoculars.fill", .epic, Double(trees.count), 15),
            b("far", "Far Roots", "Hug two trees 50 km apart", "airplane", .epic, farthest / 1000, 50, unit: " km"),
            b("species-3", "Species Seeker", "Hug 3 kinds of trees", "magnifyingglass", .common, Double(species.count), 3),
            b("species-8", "Botanist", "Hug 8 kinds of trees", "book.closed.fill", .epic, Double(species.count), 8),
            flag("redwood", "Gentle Giant", "Hug a redwood or sequoia", "mountain.2.fill", .rare,
                 species.contains { $0.contains("redwood") || $0.contains("sequoia") }),
            flag("dawn", "Dawn Hugger", "Hug before 7 AM", "sunrise.fill", .rare, hours.contains { $0 >= 4 && $0 < 7 }),
            flag("night", "Moon Hug", "Hug between 10 PM and 4 AM", "moon.stars.fill", .epic, hours.contains { $0 >= 22 || $0 < 4 }),
            b("seasons", "Four Seasons", "Hug in spring, summer, fall and winter", "circle.hexagongrid.fill", .legendary, Double(seasons.count), 4),
            b("streak-3", "Rooting In", "3-day hug streak", "flame.fill", .common, Double(best), 3, unit: " days"),
            b("streak-7", "Weeklong Roots", "7-day hug streak", "flame.circle.fill", .epic, Double(best), 7, unit: " days"),
            b("streak-30", "Unbreakable", "30-day hug streak", "crown.fill", .legendary, Double(best), 30, unit: " days"),
            flag("calm-heart", "Calm Heart", "Average heart rate 60 or lower", "heart.text.square.fill", .rare,
                 hugs.contains { ($0.avgHR ?? 999) <= 60 }),
            flag("slow-breath", "Slow Breather", "Average breathing 6 per minute or lower", "aqi.low", .epic,
                 hugs.contains { ($0.respRate ?? 99) <= 6 }),
            b("stress", "Stress Melter", "Drop your stress score by 15+", "thermometer.snowflake", .rare, stressDrop, 15),
            b("chill-10", "Certified Chill", "10 hugs tagged Chill", "cloud.sun.fill", .rare, Double(tagCount("chill")), 10),
            b("sober-10", "Clear Mind", "10 hugs tagged Sober", "drop.fill", .rare, Double(tagCount("sober")), 10),
            b("park-10", "Park Regular", "10 hugs tagged Park", "leaf.circle.fill", .rare, Double(tagCount("park")), 10),
            // Moving
            b("first-track", "First Tracks", "Record your first activity", "location.fill", .common, Double(activities.count), 1),
            b("miles-100", "Hundred Miles", "Move 100 miles on foot or bike", "figure.walk.motion", .epic, movedMiles, 100, unit: " mi"),
            b("run-10k", "10K Club", "Run 10 km in one go", "figure.run", .rare, longestRunKm, 10, unit: " km"),
            b("climb", "Trailblazer", "Climb 1,000 ft in one outing", "mountain.2.fill", .rare, bestClimbFt, 1000, unit: " ft"),
            b("ride-100", "Century Wheels", "Ride 100 miles total", "bicycle", .epic, rideMiles, 100, unit: " mi"),
            b("road-trip", "Road Tripper", "Drive 100 miles in one trip", "car.fill", .rare, longestDriveMi, 100, unit: " mi"),
            b("trail-hug", "Trail Hug", "Hug a tree tagged Hike on a day you tracked a hike", "point.topleft.down.to.point.bottomright.curvepath.fill",
              .epic, Double(trailHugs), 1),
        ]
    }

    static func season(of date: Date) -> Int {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return 0
        case 6...8: return 1
        case 9...11: return 2
        default: return 3
        }
    }
}

/// Small deterministic random generator seeded from a string.
struct SeededRNG {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        state = h == 0 ? 0x9E3779B97F4A7C15 : h
    }

    mutating func next() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}
