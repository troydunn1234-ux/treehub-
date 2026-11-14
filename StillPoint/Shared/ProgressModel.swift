import Foundation

// Streaks, weekly minutes by kind of practice, the 12-week calendar and gentle milestones.
// Shared by the iPhone and Watch apps (the views live in StillPoint/App/ProgressViews.swift).

/// One finished sauna or steam session, kept for the streak and Progress (the full heat log stays in HeatStore).
struct HeatEntry: Codable, Hashable {
    var start: Date
    var minutes: Double
    var kind: HeatKind
}

/// What a minute of practice counts as on the Progress screen.
enum ActivityCategory: String, CaseIterable, Identifiable, Hashable {
    case joint, lymph, stretch, breathe, sauna, steam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .joint: return "Joints"
        case .lymph: return "Lymph"
        case .stretch: return "Stretch"
        case .breathe: return "Breathe"
        case .sauna: return "Sauna"
        case .steam: return "Steam"
        }
    }

    var symbol: String {
        switch self {
        case .joint: return BodyFocus.joint.symbol
        case .lymph: return BodyFocus.lymph.symbol
        case .stretch: return BodyFocus.stretch.symbol
        case .breathe: return BodyFocus.breathe.symbol
        case .sauna: return HeatKind.sauna.symbol
        case .steam: return HeatKind.steam.symbol
        }
    }

    init(_ focus: BodyFocus) {
        switch focus {
        case .joint: self = .joint
        case .lymph: self = .lymph
        case .stretch: self = .stretch
        case .breathe: self = .breathe
        }
    }

    init(_ heat: HeatKind) { self = heat == .sauna ? .sauna : .steam }
}

struct CategoryMinutes: Identifiable, Hashable {
    var category: ActivityCategory
    var minutes: Double
    var id: String { category.rawValue }
}

/// A gentle milestone: earned once, kept forever.
struct Milestone: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// 0…1 toward earning it.
    let progress: Double
    var earned: Bool { progress >= 1 }
}

extension SessionLog {
    /// Which category a guided session counts toward. Sitting practices without a body focus count as Breathe.
    func category(of r: SessionRecord, library lib: PracticeLibrary = .shared) -> ActivityCategory {
        if let p = lib.practice(r.practiceId), let f = p.focus { return ActivityCategory(f) }
        return r.isMovement ? .stretch : .breathe
    }

    /// Minutes per category for one interval (sessions ≥ 1 min only, like the streak).
    func minutesByCategory(from start: Date, to end: Date = .distantFuture) -> [ActivityCategory: Double] {
        var out: [ActivityCategory: Double] = [:]
        let lib = PracticeLibrary.shared
        for r in records where r.seconds >= 60 && r.start >= start && r.start < end {
            out[category(of: r, library: lib), default: 0] += r.minutes
        }
        for h in heatEntries where h.minutes >= 1 && h.start >= start && h.start < end {
            out[ActivityCategory(h.kind), default: 0] += h.minutes
        }
        return out
    }

    /// This calendar week, every category (zeros included), in display order.
    func thisWeekByCategory() -> [CategoryMinutes] {
        let m = minutesByCategory(from: weekStartDate)
        return ActivityCategory.allCases.map { CategoryMinutes(category: $0, minutes: m[$0] ?? 0) }
    }

    /// Minutes per day (start of day → minutes) since `start`, guided sessions and heat together.
    func dailyActivity(since start: Date) -> [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for r in records where r.seconds >= 60 && r.start >= start {
            out[cal.startOfDay(for: r.start), default: 0] += r.minutes
        }
        for h in heatEntries where h.minutes >= 1 && h.start >= start {
            out[cal.startOfDay(for: h.start), default: 0] += h.minutes
        }
        return out
    }

    /// Every minute ever, heat included.
    var allActivityMinutes: Double {
        records.filter { $0.seconds >= 60 }.reduce(0) { $0 + $1.minutes } + heatEntries.reduce(0) { $0 + $1.minutes }
    }

    /// Small, kind milestones. None of them can be lost.
    var milestones: [Milestone] {
        let best = Double(bestStreak)
        let total = allActivityMinutes
        let anyDay = activeDays.isEmpty ? 0.0 : 1.0
        let lib = PracticeLibrary.shared
        let tried = Set(records.filter { $0.seconds >= 60 }.map { category(of: $0, library: lib) })
        let body: [ActivityCategory] = [.joint, .lymph, .stretch, .breathe]
        let bodyCount = Double(body.filter { tried.contains($0) }.count)
        let heatCount = Double(heatEntries.count)

        func streak(_ n: Double, _ id: String, _ title: String, _ symbol: String) -> Milestone {
            Milestone(id: id, title: title, detail: best >= n ? "\(Int(n)) days in a row" : "\(Int(n - best)) more days in a row",
                      symbol: symbol, progress: min(1, best / n))
        }
        func minutes(_ n: Double, _ id: String, _ title: String) -> Milestone {
            Milestone(id: id, title: title,
                      detail: total >= n ? "\(Int(n / 60)) \(n == 60 ? "hour" : "hours") in all" : "\(Int((n - total).rounded(.up))) min to go",
                      symbol: "hourglass", progress: min(1, total / n))
        }

        return [
            Milestone(id: "first", title: "First stillness", detail: anyDay >= 1 ? "Your first session" : "Finish one session",
                      symbol: "leaf", progress: anyDay),
            streak(3, "s3", "Three days", "flame"),
            streak(7, "s7", "A full week", "flame.fill"),
            streak(14, "s14", "Two weeks", "sparkles"),
            streak(30, "s30", "A month", "moon.stars"),
            streak(100, "s100", "A hundred days", "sun.max"),
            minutes(60, "m60", "First hour"),
            minutes(600, "m600", "Ten hours"),
            Milestone(id: "body", title: "Whole body", detail: bodyCount >= 4 ? "Joints, lymph, stretch & breath" : "\(Int(4 - bodyCount)) more of joints, lymph, stretch, breathe",
                      symbol: "figure.mind.and.body", progress: bodyCount / 4),
            Milestone(id: "heat", title: "Into the heat", detail: heatCount >= 1 ? "A sauna or steam session" : "Time one sauna or steam",
                      symbol: "flame", progress: min(1, heatCount)),
            Milestone(id: "heat10", title: "Heat regular", detail: heatCount >= 10 ? "10 heat sessions" : "\(Int(10 - heatCount)) more heat sessions",
                      symbol: "cloud.fog", progress: min(1, heatCount / 10)),
        ]
    }
}
