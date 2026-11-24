import Foundation
import HealthKit
import SwiftUI

// "Right now": ONE practice picked for this moment from the numbers WHOOP and the Watch save to
// Apple Health (and, on iPhone, Pulse Lab's daily WHOOP summary from the shared wellness App Group).
// Rules only, every number shown under "Why this?". The stress level is an estimate built from
// heart rate, HRV and breathing rate; it is not WHOOP's Stress Monitor and not a medical measurement.

// MARK: - Readings

/// One number from Apple Health with where it came from ("WHOOP", "Watch", "iPhone" or the app's name).
struct HealthReading: Codable, Hashable {
    var value: Double
    var date: Date
    var source: String
}

/// Everything the suggestion looks at. Every field optional: missing data just means fewer rules apply.
struct BodySnapshot: Codable, Hashable {
    var takenAt = Date()
    /// Latest heart rate in the last 15 minutes.
    var heartRate: HealthReading?
    /// Latest resting heart rate (last 3 days).
    var restingHR: HealthReading?
    /// Latest HRV (last 24 h). WHOOP stores its RMSSD under Health's HRV type; the Watch stores SDNN.
    var hrv: HealthReading?
    /// 14-day average HRV from the same source as `hrv` (so WHOOP is only compared with WHOOP).
    var hrvBaseline: Double?
    var hrvBaselineDays = 0
    /// Latest breathing rate (last 24 h) and its 14-day average from the same source.
    var respRate: HealthReading?
    var respBaseline: Double?
    /// Last night's sleep (minutes asleep) from the source that recorded the most.
    var sleepMinutes: Double?
    var sleepSource: String?
    /// Training today (other apps' workouts; Still Pointz' own routines and heat sessions don't count).
    var workoutMinutesToday: Double = 0
    var workoutKcalToday: Double = 0
    var lastWorkoutEnd: Date?
    var lastWorkoutName: String?
    var lastWorkoutMinutes: Double?
    var lastWorkoutSource: String?
    /// Steps in the last 15 minutes (walking around raises heart rate too).
    var recentSteps: Double?
    var mindfulMinutesToday: Double = 0
    /// Last finished sauna / steam session (from the heat log).
    var lastHeatEnd: Date?
    var lastHeatKind: String?
    var lastHeatMinutes: Double?
    // Pulse Lab's summary for today (iPhone only).
    var whoopRecovery: Double?
    var whoopStrain: Double?
    var sleepPerformance: Double?
    var readiness: Double?
    var pulseLabSources: [String] = []

    var hasBodyData: Bool {
        heartRate != nil || restingHR != nil || hrv != nil || sleepMinutes != nil || whoopRecovery != nil || readiness != nil
    }

    /// HRV vs its 14-day average, in percent (negative = lower than usual).
    var hrvPct: Double? {
        guard let h = hrv?.value, let b = hrvBaseline, b > 0, hrvBaselineDays >= 3 else { return nil }
        return (h - b) / b * 100
    }

    /// Current heart rate above resting (bpm).
    var hrAboveRest: Double? {
        guard let h = heartRate?.value, let r = restingHR?.value else { return nil }
        return h - r
    }

    var respDelta: Double? {
        guard let r = respRate?.value, let b = respBaseline else { return nil }
        return r - b
    }

    /// Every source behind the numbers, for the badges.
    var sources: [String] {
        var out: [String] = []
        for s in [heartRate?.source, restingHR?.source, hrv?.source, respRate?.source, sleepSource].compactMap({ $0 }) where !out.contains(s) {
            out.append(s)
        }
        if !pulseLabSources.isEmpty, !out.contains("Pulse Lab") { out.append("Pulse Lab") }
        return out
    }
}

// MARK: - Stress estimate

/// A transparent 0–3 estimate from heart rate above resting, HRV vs usual and breathing rate vs usual.
struct StressEstimate: Codable, Hashable {
    enum Level: Int, Codable, CaseIterable, Comparable {
        case calm, balanced, elevated, high
        var label: String {
            switch self {
            case .calm: return String(localized: "Calm")
            case .balanced: return String(localized: "Balanced")
            case .elevated: return String(localized: "Elevated")
            case .high: return String(localized: "High")
            }
        }
        var tint: Color {
            switch self {
            case .calm: return SP.teal
            case .balanced: return SP.gold
            case .elevated: return SP.amber
            case .high: return SP.rose
            }
        }
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    var level: Level
    /// 0–3
    var score: Double
    var hrAbove: Double?
    var hrvPct: Double?
    var respDelta: Double?
    /// One line per signal that counted, e.g. "Heart rate 18 bpm above resting (+2)".
    var parts: [String]

    /// Nil (with a note) right after a workout or heat session, while walking, or without heart data.
    static func estimate(_ s: BodySnapshot, now: Date = Date()) -> (StressEstimate?, String?) {
        if let end = s.lastHeatEnd, now.timeIntervalSince(end) < 60 * 60, now >= end {
            return (nil, String(localized: "Paused for an hour after the sauna or steam: heat raises heart rate for a good reason."))
        }
        if let end = s.lastWorkoutEnd, now.timeIntervalSince(end) < 45 * 60 {
            return (nil, String(localized: "Paused for 45 minutes after a workout: heart rate is up for a good reason."))
        }
        if let steps = s.recentSteps, steps > 400 {
            return (nil, String(localized: "Paused while you're on the move (\(Int(steps)) steps in the last 15 minutes)."))
        }
        var points = 0.0, maxPoints = 0.0
        var parts: [String] = []
        var core = false
        if let d = s.hrAboveRest {
            let p: Double = d < 8 ? 0 : d < 15 ? 1 : d < 25 ? 2 : 3
            points += p; maxPoints += 3; core = true
            parts.append(String(localized: "Heart rate \(signed(d)) bpm vs resting: \(Int(p)) of 3"))
        }
        if let pct = s.hrvPct, let h = s.hrv, now.timeIntervalSince(h.date) < 12 * 3600 {
            let p: Double = pct > -10 ? 0 : pct > -25 ? 1 : 2
            points += p; maxPoints += 2; core = true
            parts.append(String(localized: "HRV \(signed(pct))% vs your 14-day average: \(Int(p)) of 2"))
        }
        if let d = s.respDelta, let r = s.respRate, now.timeIntervalSince(r.date) < 12 * 3600 {
            let p: Double = d < 1.5 ? 0 : d < 3 ? 1 : 2
            points += p; maxPoints += 2
            parts.append(String(localized: "Breathing \(signed(d, decimals: 1))/min vs usual: \(Int(p)) of 2"))
        }
        guard core, maxPoints > 0 else {
            return (nil, String(localized: "Needs a heart rate from the last 15 minutes and your resting heart rate, or a recent HRV."))
        }
        let score = 3 * points / maxPoints
        let level: Level = score < 0.75 ? .calm : score < 1.5 ? .balanced : score < 2.25 ? .elevated : .high
        return (StressEstimate(level: level, score: score, hrAbove: s.hrAboveRest, hrvPct: s.hrvPct,
                               respDelta: s.respDelta, parts: parts), nil)
    }

    static func signed(_ v: Double, decimals: Int = 0) -> String {
        let n = v.formatted(.number.precision(.fractionLength(decimals)))
        return v > 0 ? "+" + n : n
    }
}

// MARK: - Suggestion

/// One row under "Why this?".
struct WhyLine: Codable, Hashable, Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var source: String? = nil
}

struct Suggestion: Codable, Hashable {
    var practiceId: String
    var title: String
    var minutes: Int
    /// The data half of the line, e.g. "Your heart rate is 18 bpm above resting and HRV is low".
    var because: String
    /// Which rule fired (shown under "Why this?").
    var rule: String
    /// Goal category id (calm, sleep, recovery…).
    var goal: String
    var why: [WhyLine] = []
    var worksBest = false
    var stressLevel: Int? = nil
    var stressNote: String? = nil
    var sources: [String] = []
    var computedAt = Date()
    /// True when no body data was used (time of day only).
    var timeOnly = false

    /// "Your heart rate is 18 bpm above resting — try 1-Minute Calm SOS (2 min)"
    var line: String { String(localized: "\(because) — try \(title) (\(minutes) min)") }
}

enum SuggestionEngine {
    struct Rule {
        var id: String
        var goal: String
        /// Practice ids in order of preference, with their length.
        var picks: [(String, Int)]
        var because: String
    }

    enum Daypart { case early, morning, midday, afternoon, evening, night }

    static func daypart(_ now: Date) -> Daypart {
        let h = Calendar.current.component(.hour, from: now)
        switch h {
        case 4..<6: return .early
        case 6..<11: return .morning
        case 11..<14: return .midday
        case 14..<18: return .afternoon
        case 18..<21: return .evening
        default: return .night
        }
    }

    static func fmtSleep(_ m: Double) -> String {
        let h = Int(m) / 60, mm = Int(m) % 60
        return "\(h) h \(mm) m"
    }

    /// The rule for this moment: the first one whose condition holds, in this order.
    static func rule(_ s: BodySnapshot?, stress: StressEstimate?, now: Date) -> Rule {
        let part = daypart(now)
        let night = part == .night
        if let s {
            // 1. Just out of the sauna / steam.
            if let end = s.lastHeatEnd, now >= end, now.timeIntervalSince(end) < 45 * 60 {
                let kind = s.lastHeatKind == HeatKind.steam.rawValue ? String(localized: "steam room") : String(localized: "sauna")
                let mins = s.lastHeatMinutes.map { " (\(Int($0.rounded())) min)" } ?? ""
                return Rule(id: "heat", goal: "recovery", picks: [("sauna-cooldown", 5), ("cold-recover", 3), ("resonance", 5)],
                            because: String(localized: "Just out of the \(kind)\(mins)"))
            }
            // 2. Training in the last 90 minutes.
            if let end = s.lastWorkoutEnd, now.timeIntervalSince(end) < 90 * 60, (s.lastWorkoutMinutes ?? 0) >= 10 {
                let because: String
                if let st = s.whoopStrain, st >= 10 {
                    because = String(localized: "Strain \(st.formatted(.number.precision(.fractionLength(0)))) after training")
                } else {
                    let what = (s.lastWorkoutName ?? String(localized: "workout")).lowercased()
                    because = String(localized: "Just finished a \(Int((s.lastWorkoutMinutes ?? 0).rounded()))-min \(what)")
                }
                return Rule(id: "post-workout", goal: "recovery", picks: [("post-workout", 5), ("legs-up-rest", 10), ("resonance", 5)],
                            because: because)
            }
            // 3. Stress estimate Elevated or High.
            if let st = stress, st.level >= .elevated {
                var bits: [String] = []
                if let d = st.hrAbove, d >= 8 { bits.append(String(localized: "heart rate is \(Int(d.rounded())) bpm above resting")) }
                if let p = st.hrvPct, p <= -10 { bits.append(p <= -25 ? String(localized: "HRV is low") : String(localized: "HRV is a bit under your usual")) }
                if let r = st.respDelta, r >= 1.5 { bits.append(String(localized: "breathing is faster than usual")) }
                let because = bits.isEmpty ? String(localized: "Stress estimate is \(st.level.label.lowercased())")
                    : String(localized: "Your ") + bits.joined(separator: String(localized: " and "))
                let picks: [(String, Int)] = night
                    ? [("wind-down-478", 3), ("long-exhale", 5), ("calm-sos", 2)]
                    : st.level == .high ? [("calm-sos", 2), ("sigh", 3), ("long-exhale", 5)]
                    : [("calm-sos", 2), ("resonance", 5), ("long-exhale", 5), ("box", 3)]
                return Rule(id: "stress", goal: "calm", picks: picks, because: because)
            }
            // 4. Low recovery (WHOOP recovery, Pulse Lab readiness or HRV well under usual).
            let shortNight = (s.sleepMinutes ?? 999) < 6 * 60
            let nightBit = shortNight ? String(localized: " after a short night (\(fmtSleep(s.sleepMinutes ?? 0)))") : ""
            if let r = s.whoopRecovery, r < 34 {
                return lowRecovery(night: night, because: String(localized: "Recovery \(Int(r.rounded()))%") + nightBit)
            }
            if s.whoopRecovery == nil, let r = s.readiness, r < 40 {
                return lowRecovery(night: night, because: String(localized: "Readiness \(Int(r.rounded()))") + nightBit)
            }
            if let p = s.hrvPct, p <= -20, part == .early || part == .morning || part == .midday {
                return lowRecovery(night: night, because: String(localized: "HRV \(Int(abs(p).rounded()))% under your usual") + nightBit)
            }
            if shortNight, let m = s.sleepMinutes, m > 60, part == .morning || part == .midday || part == .afternoon {
                return Rule(id: "short-night", goal: "recovery", picks: [("legs-up-rest", 10), ("yoga-nidra", 10), ("resonance", 5)],
                            because: String(localized: "Only \(fmtSleep(m)) of sleep last night"))
            }
        }
        // 5. Time of day (and a high-recovery morning).
        switch part {
        case .night:
            return Rule(id: "night", goal: "sleep", picks: [("wind-down-nidra", 10), ("wind-down-478", 3), ("body-scan", 10)],
                        because: String(localized: "It's late — time to wind down for sleep"))
        case .evening:
            return Rule(id: "evening", goal: "calm", picks: [("resonance", 5), ("long-exhale", 5), ("legs-up-rest", 10)],
                        because: String(localized: "Evening — let the day settle"))
        case .early, .morning:
            if let r = s?.whoopRecovery ?? s?.readiness, r >= 67 {
                let label = s?.whoopRecovery != nil ? String(localized: "Recovery \(Int(r.rounded()))%") : String(localized: "Readiness \(Int(r.rounded()))")
                return Rule(id: "high-recovery", goal: "energy", picks: [("morning-wake", 3), ("pre-workout", 3), ("stoic-morning", 5)],
                            because: String(localized: "\(label) — a good morning to wake the body up"))
            }
            return Rule(id: "morning", goal: "energy", picks: [("morning-wake", 3), ("anapanasati", 5), ("stoic-morning", 5)],
                        because: String(localized: "Morning — start the day steady"))
        case .midday, .afternoon:
            if let st = stress, st.level == .calm, let r = s?.whoopRecovery ?? s?.readiness, r >= 67 {
                return Rule(id: "focus", goal: "focus", picks: [("focus-reset", 2), ("box", 3), ("zazen-count", 5)],
                            because: String(localized: "Calm and well recovered — a short focus reset"))
            }
            return Rule(id: "afternoon", goal: "focus", picks: [("focus-reset", 2), ("box", 3), ("resonance", 5)],
                        because: String(localized: "Afternoon — a short reset to refocus"))
        }
    }

    private static func lowRecovery(night: Bool, because: String) -> Rule {
        if night {
            return Rule(id: "low-recovery", goal: "sleep", picks: [("wind-down-nidra", 10), ("legs-up-rest", 10), ("wind-down-478", 3)], because: because)
        }
        return Rule(id: "low-recovery", goal: "recovery", picks: [("legs-up-rest", 10), ("resonance", 5), ("body-scan", 10)], because: because)
    }

    static func ruleTitle(_ id: String) -> String {
        switch id {
        case "heat": return String(localized: "Within 45 min of a sauna or steam session → cool-down")
        case "post-workout": return String(localized: "Within 90 min of a workout → downshift")
        case "stress": return String(localized: "Stress estimate Elevated or High → calm the body")
        case "low-recovery": return String(localized: "Low recovery or HRV well under usual → rest")
        case "short-night": return String(localized: "Under 6 hours of sleep → rest")
        case "night": return String(localized: "After 9 pm → wind down for sleep")
        case "evening": return String(localized: "Evening → settle")
        case "high-recovery": return String(localized: "Morning with high recovery → energy")
        case "morning": return String(localized: "Morning → steady start")
        case "focus", "afternoon": return String(localized: "Daytime → focus")
        default: return id
        }
    }

    /// Practice and length for a rule: "Works best for you" practices in the goal first, then the rule's picks,
    /// then the rest of the goal. Skips the last practice done and, when possible, locked ones.
    static func choose(_ r: Rule, lastDone: String?, worksBest: [String], isLocked: (Practice) -> Bool,
                       lib: PracticeLibrary = .shared) -> (Practice, Int, Bool)? {
        let preferredMinutes = r.picks.first?.1 ?? 5
        // Energising or movement practices are never offered for sleep or calm.
        func fits(_ p: Practice) -> Bool {
            if r.goal == "sleep" || r.goal == "calm" { return !p.isMovement && !p.isIn("energy") }
            return true
        }
        let best = worksBest.compactMap { lib.practice($0) }.filter { $0.isIn(r.goal) && fits($0) }
        let picks = r.picks.compactMap { lib.practice($0.0) }
        let rest = lib.practices(inCategory: r.goal).filter(fits)
        var seen = Set<String>()
        let ordered = (best + picks + rest).filter { seen.insert($0.id).inserted && $0.id != lastDone }
        let open = ordered.filter { !isLocked($0) }
        guard let p = open.first ?? ordered.first else { return nil }
        let want = r.picks.first(where: { $0.0 == p.id })?.1 ?? preferredMinutes
        let mins = p.minutes.contains(want) ? want : (p.minutes.min(by: { abs($0 - want) < abs($1 - want) }) ?? p.defaultMinutes)
        return (p, mins, best.contains(where: { $0.id == p.id }))
    }

    static func suggest(_ s: BodySnapshot?, stress: StressEstimate?, stressNote: String?, now: Date = Date(),
                        lastDone: String?, worksBest: [String], isLocked: (Practice) -> Bool) -> Suggestion {
        let lib = PracticeLibrary.shared
        let r = rule(s, stress: stress, now: now)
        let picked = choose(r, lastDone: lastDone, worksBest: worksBest, isLocked: isLocked)
        let p = picked?.0 ?? lib.quickPractice
        let mins = picked?.1 ?? p.defaultMinutes
        var out = Suggestion(practiceId: p.id, title: p.title, minutes: mins, because: r.because, rule: r.id, goal: r.goal)
        out.worksBest = picked?.2 ?? false
        out.stressLevel = stress?.level.rawValue
        out.stressNote = stressNote
        out.sources = s?.sources ?? []
        out.computedAt = now
        // Time of day only: no body numbers, and neither the sauna nor the training rule fired. (The last sauna or
        // steam session is in every snapshot, even from days ago, so its mere presence said nothing about now: with
        // any heat in the log the card never said its pick came from the clock, and the Watch kept its own pick
        // over the iPhone's fuller one.)
        out.timeOnly = !(s?.hasBodyData ?? false) && r.id != "heat" && r.id != "post-workout"
        out.why = whyLines(s, stress: stress, stressNote: stressNote, rule: r, now: now, worksBest: out.worksBest)
        return out
    }

    static func whyLines(_ s: BodySnapshot?, stress: StressEstimate?, stressNote: String?, rule: Rule, now: Date, worksBest: Bool) -> [WhyLine] {
        var w: [WhyLine] = []
        func ago(_ d: Date) -> String {
            let m = Int(now.timeIntervalSince(d) / 60)
            if m < 1 { return String(localized: "just now") }
            if m < 90 { return String(localized: "\(m) min ago") }
            return String(localized: "\(m / 60) h ago")
        }
        w.append(WhyLine(label: String(localized: "Rule"), value: ruleTitle(rule.id)))
        if let st = stress {
            w.append(WhyLine(label: String(localized: "Stress estimate"),
                             value: "\(st.level.label) · \(st.score.formatted(.number.precision(.fractionLength(1)))) / 3"))
        } else if let n = stressNote {
            w.append(WhyLine(label: String(localized: "Stress estimate"), value: n))
        }
        if let s {
            if let h = s.heartRate { w.append(WhyLine(label: String(localized: "Heart rate"), value: "\(Int(h.value.rounded())) bpm · \(ago(h.date))", source: h.source)) }
            if let r = s.restingHR { w.append(WhyLine(label: String(localized: "Resting heart rate"), value: "\(Int(r.value.rounded())) bpm", source: r.source)) }
            if let h = s.hrv {
                var v = "\(Int(h.value.rounded())) ms · \(ago(h.date))"
                if let b = s.hrvBaseline, s.hrvBaselineDays >= 3, let p = s.hrvPct {
                    v += String(localized: " · 14-day avg \(Int(b.rounded())) ms (\(StressEstimate.signed(p))%)")
                }
                w.append(WhyLine(label: String(localized: "HRV"), value: v, source: h.source))
            }
            if let r = s.respRate {
                var v = "\(r.value.formatted(.number.precision(.fractionLength(1)))) /min"
                if let b = s.respBaseline { v += String(localized: " · usual \(b.formatted(.number.precision(.fractionLength(1))))") }
                w.append(WhyLine(label: String(localized: "Breathing rate"), value: v, source: r.source))
            }
            if let m = s.sleepMinutes { w.append(WhyLine(label: String(localized: "Sleep last night"), value: fmtSleep(m), source: s.sleepSource)) }
            if let r = s.whoopRecovery { w.append(WhyLine(label: String(localized: "WHOOP recovery"), value: "\(Int(r.rounded()))%", source: "Pulse Lab")) }
            if let st = s.whoopStrain { w.append(WhyLine(label: String(localized: "WHOOP strain"), value: st.formatted(.number.precision(.fractionLength(1))), source: "Pulse Lab")) }
            if let p = s.sleepPerformance { w.append(WhyLine(label: String(localized: "Sleep performance"), value: "\(Int(p.rounded()))%", source: "Pulse Lab")) }
            if let r = s.readiness { w.append(WhyLine(label: String(localized: "Readiness"), value: "\(Int(r.rounded()))", source: "Pulse Lab")) }
            if s.workoutMinutesToday > 0 {
                var v = String(localized: "\(Int(s.workoutMinutesToday.rounded())) min")
                if s.workoutKcalToday > 0 { v += " · \(Int(s.workoutKcalToday.rounded())) kcal" }
                if let e = s.lastWorkoutEnd { v += String(localized: " · last ended \(ago(e))") }
                w.append(WhyLine(label: String(localized: "Training today"), value: v, source: s.lastWorkoutSource))
            }
            if let e = s.lastHeatEnd, now.timeIntervalSince(e) < 6 * 3600 {
                w.append(WhyLine(label: String(localized: "Sauna / steam"), value: String(localized: "ended \(ago(e))")))
            }
            if s.mindfulMinutesToday > 0 {
                w.append(WhyLine(label: String(localized: "Mindful minutes today"), value: "\(Int(s.mindfulMinutesToday.rounded()))"))
            }
        }
        w.append(WhyLine(label: String(localized: "Time of day"), value: now.formatted(date: .omitted, time: .shortened)))
        if worksBest { w.append(WhyLine(label: String(localized: "Works best for you"), value: String(localized: "Your heart rate drops most with this one"))) }
        return w
    }
}

// MARK: - Apple Health reads

/// Read-only Health queries for the card. Async, and quiet on failure (no data = nil).
enum RightNowHealth {
    static var store: HKHealthStore { MindfulHealth.shared.store }
    static var available: Bool { HKHealthStore.isHealthDataAvailable() && !ProcessInfo.processInfo.arguments.contains("-demo") }

    static let hr = HKQuantityType(.heartRate)
    static let rest = HKQuantityType(.restingHeartRate)
    static let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    static let resp = HKQuantityType(.respiratoryRate)
    static let steps = HKQuantityType(.stepCount)
    static let sleep = HKCategoryType(.sleepAnalysis)
    static let mindful = HKCategoryType(.mindfulSession)

    static var readTypes: Set<HKObjectType> { [hr, rest, hrv, resp, steps, sleep, mindful, HKObjectType.workoutType()] }

    /// True when the person hasn't been asked yet for the types the card reads.
    static func shouldAsk() async -> Bool {
        guard available else { return false }
        let st = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return st == .shouldRequest
    }

    static func requestAccess() async {
        guard available else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// "WHOOP", "Watch", "iPhone" or the app's name.
    static func badge(_ r: HKSourceRevision) -> String {
        let b = r.source.bundleIdentifier.lowercased(), n = r.source.name.lowercased()
        if b.contains("whoop") || n.contains("whoop") { return "WHOOP" }
        if let p = r.productType?.lowercased() {
            if p.contains("watch") { return "Watch" }
            if p.contains("iphone") { return "iPhone" }
        }
        return r.source.name
    }

    private static func quantities(_ t: HKQuantityType, from: Date, to: Date = Date(), limit: Int? = nil) async -> [HKQuantitySample] {
        let pred = HKQuery.predicateForSamples(withStart: from, end: to.addingTimeInterval(120), options: [])
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: t, predicate: pred)],
                                        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: limit)
        return (try? await d.result(for: store)) ?? []
    }

    private static func latest(_ t: HKQuantityType, unit: HKUnit, within: TimeInterval) async -> HealthReading? {
        guard let q = await quantities(t, from: Date().addingTimeInterval(-within), limit: 1).first else { return nil }
        return HealthReading(value: q.quantity.doubleValue(for: unit), date: q.endDate, source: badge(q.sourceRevision))
    }

    /// 14-day average of daily means from one source, leaving out the last `skipHours`.
    private static func baseline(_ t: HKQuantityType, unit: HKUnit, source: String, skipHours: Double = 0) async -> (Double, Int)? {
        let now = Date()
        let samples = await quantities(t, from: now.addingTimeInterval(-15 * 86400), to: now.addingTimeInterval(-skipHours * 3600))
        let cal = Calendar.current
        var days: [Date: [Double]] = [:]
        for q in samples where badge(q.sourceRevision) == source {
            days[cal.startOfDay(for: q.startDate), default: []].append(q.quantity.doubleValue(for: unit))
        }
        let means = days.values.map { $0.reduce(0, +) / Double($0.count) }
        guard !means.isEmpty else { return nil }
        return (means.reduce(0, +) / Double(means.count), means.count)
    }

    static func snapshot() async -> BodySnapshot {
        var s = BodySnapshot()
        guard available else { return s }
        let bpm = MindfulHealth.bpm, ms = HKUnit.secondUnit(with: .milli)
        let now = Date()
        s.heartRate = await latest(hr, unit: bpm, within: 15 * 60)
        s.restingHR = await latest(rest, unit: bpm, within: 3 * 86400)
        if let h = await latest(hrv, unit: ms, within: 24 * 3600) {
            s.hrv = h
            if let base = await baseline(hrv, unit: ms, source: h.source, skipHours: 12) {
                s.hrvBaseline = base.0
                s.hrvBaselineDays = base.1
            }
        }
        if let r = await latest(resp, unit: bpm, within: 24 * 3600) {
            s.respRate = r
            if let base = await baseline(resp, unit: bpm, source: r.source, skipHours: 12), base.1 >= 3 { s.respBaseline = base.0 }
        }
        // Steps in the last 15 minutes.
        let stepPred = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-15 * 60), end: now, options: [])
        let stepQ = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: steps, predicate: stepPred), options: .cumulativeSum)
        let stepStats: HKStatistics? = (try? await stepQ.result(for: store)) ?? nil
        s.recentSteps = stepStats?.sumQuantity()?.doubleValue(for: .count())
        await addSleep(&s, now: now)
        await addWorkouts(&s, now: now)
        // Mindful minutes today (every app).
        let dayStart = Calendar.current.startOfDay(for: now)
        let mPred = HKQuery.predicateForSamples(withStart: dayStart, end: now, options: [])
        let mq = HKSampleQueryDescriptor(predicates: [.categorySample(type: mindful, predicate: mPred)], sortDescriptors: [], limit: nil)
        let ms2 = (try? await mq.result(for: store)) ?? []
        s.mindfulMinutesToday = ms2.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
        return s
    }

    /// Last night: asleep minutes between 6 pm yesterday and 2 pm today, from the source that recorded the most.
    private static func addSleep(_ s: inout BodySnapshot, now: Date) async {
        let day = Calendar.current.startOfDay(for: now)
        let from = day.addingTimeInterval(-6 * 3600), to = min(now, day.addingTimeInterval(14 * 3600))
        guard to > from else { return }
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let q = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleep, predicate: pred)], sortDescriptors: [], limit: nil)
        let samples = (try? await q.result(for: store)) ?? []
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var bySource: [String: Double] = [:]
        for c in samples where asleep.contains(c.value) {
            bySource[badge(c.sourceRevision), default: 0] += c.endDate.timeIntervalSince(c.startDate) / 60
        }
        if let best = bySource.max(by: { $0.value < $1.value }), best.value > 30 {
            s.sleepMinutes = best.value
            s.sleepSource = best.key
        }
    }

    private static func addWorkouts(_ s: inout BodySnapshot, now: Date) async {
        let day = Calendar.current.startOfDay(for: now)
        let pred = HKQuery.predicateForSamples(withStart: day.addingTimeInterval(-3 * 3600), end: now, options: [])
        let q = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 30)
        let ws = (try? await q.result(for: store)) ?? []
        let calmTypes: Set<HKWorkoutActivityType> = [.mindAndBody, .flexibility, .preparationAndRecovery, .cooldown, .yoga, .taiChi]
        let mine = (Bundle.main.bundleIdentifier ?? "com.troydunn.stillpoint").lowercased()
        let energy = HKQuantityType(.activeEnergyBurned)
        for w in ws {
            let b = w.sourceRevision.source.bundleIdentifier.lowercased()
            guard !b.hasPrefix(mine), !b.contains("stillpoint"), !calmTypes.contains(w.workoutActivityType) else { continue }
            let mins = w.duration / 60
            if w.endDate >= day {
                s.workoutMinutesToday += mins
                s.workoutKcalToday += w.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
            if s.lastWorkoutEnd == nil {
                s.lastWorkoutEnd = w.endDate
                s.lastWorkoutMinutes = mins
                s.lastWorkoutName = name(w.workoutActivityType)
                s.lastWorkoutSource = badge(w.sourceRevision)
            }
        }
    }

    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return String(localized: "Run")
        case .walking: return String(localized: "Walk")
        case .hiking: return String(localized: "Hike")
        case .cycling: return String(localized: "Ride")
        case .swimming: return String(localized: "Swim")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return String(localized: "Strength session")
        case .highIntensityIntervalTraining: return String(localized: "HIIT session")
        case .crossTraining: return String(localized: "Cross-training session")
        case .boxing, .kickboxing, .martialArts: return String(localized: "Fight session")
        case .rowing: return String(localized: "Row")
        case .elliptical: return String(localized: "Elliptical session")
        case .soccer, .basketball, .tennis: return String(localized: "Game")
        default: return String(localized: "Workout")
        }
    }

    /// Calls `changed` (on the main actor) when new heart, HRV, sleep or workout data lands in Health.
    static func observe(_ changed: @escaping @MainActor () -> Void) -> [HKObserverQuery] {
        guard available else { return [] }
        let types: [HKSampleType] = [hr, hrv, rest, sleep, HKObjectType.workoutType()]
        return types.map { t in
            let q = HKObserverQuery(sampleType: t, predicate: nil) { _, done, _ in
                Task { @MainActor in changed() }
                done()
            }
            store.execute(q)
            return q
        }
    }
}

// MARK: - Model

/// Holds the current suggestion; refreshed on open, on foreground and when Health gets new data.
@MainActor
final class RightNow: ObservableObject {
    static let shared = RightNow()

    @Published private(set) var suggestion: Suggestion
    @Published private(set) var snapshot: BodySnapshot?
    @Published private(set) var stress: StressEstimate?
    @Published private(set) var stressNote: String?
    @Published private(set) var needsHealthAccess = false
    @Published private(set) var refreshing = false
    /// Watch: the iPhone's suggestion (it sees WHOOP's full data and Pulse Lab).
    @Published private(set) var remote: Suggestion?

    /// Called after every refresh (iPhone: send to the Watch, check the stress nudge).
    var onUpdate: ((RightNow) -> Void)?
    /// iPhone: Pulse Lab's summary (the shared wellness group is only in the iPhone app).
    var pulseLab: (() -> (recovery: Double?, strain: Double?, sleepPerf: Double?, readiness: Double?, sources: [String])?)?

    private var observers: [HKObserverQuery] = []
    private var pending: Task<Void, Never>?
    private var lastRefresh = Date.distantPast

    private init() {
        suggestion = SuggestionEngine.suggest(nil, stress: nil, stressNote: nil, lastDone: Prefs.shared.recents.first,
                                              worksBest: SessionLog.shared.worksBest(), isLocked: { PracticeLibrary.shared.isLocked($0) })
    }

    /// What to show: on the Watch, the iPhone's pick while it's under 45 minutes old and nothing local is newer.
    var current: Suggestion {
        if let r = remote, Date().timeIntervalSince(r.computedAt) < 45 * 60,
           r.computedAt > suggestion.computedAt.addingTimeInterval(-5 * 60) || suggestion.timeOnly {
            return r
        }
        return suggestion
    }

    func applyRemote(_ s: Suggestion) { remote = s }

    /// Start watching Health for new data (call once at launch).
    func startObserving() {
        guard observers.isEmpty else { return }
        observers = RightNowHealth.observe { [weak self] in self?.scheduleRefresh() }
    }

    /// Coalesce bursts of Health updates (WHOOP writes many samples at once).
    func scheduleRefresh(after seconds: Double = 15) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func requestAccess() async {
        await RightNowHealth.requestAccess()
        needsHealthAccess = await RightNowHealth.shouldAsk()
        await refresh(force: true)
    }

    func refresh(force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastRefresh) < 20 { return }
        lastRefresh = Date()
        refreshing = true
        needsHealthAccess = await RightNowHealth.shouldAsk()
        var s = await RightNowHealth.snapshot()
        let log = SessionLog.shared
        if let h = log.heatEntries.max(by: { $0.start < $1.start }) {
            s.lastHeatEnd = h.start.addingTimeInterval(h.minutes * 60)
            s.lastHeatKind = h.kind.rawValue
            s.lastHeatMinutes = h.minutes
        }
        if let p = pulseLab?() {
            s.whoopRecovery = p.recovery
            s.whoopStrain = p.strain
            s.sleepPerformance = p.sleepPerf
            s.readiness = p.readiness
            s.pulseLabSources = p.sources
        }
        let (st, note) = StressEstimate.estimate(s)
        snapshot = s
        stress = st
        stressNote = note
        suggestion = SuggestionEngine.suggest(s, stress: st, stressNote: note, lastDone: Prefs.shared.recents.first,
                                              worksBest: log.worksBest(), isLocked: { PracticeLibrary.shared.isLocked($0) })
        refreshing = false
        onUpdate?(self)
    }
}
