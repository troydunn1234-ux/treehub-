import Foundation
import SwiftUI

/// One plain-English finding ("Lab note") built from the numbers both trackers recorded.
struct Insight: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    /// Which tracker the finding is "about" (nil = both / neutral).
    let source: Source?
    /// Where tapping it should take you.
    let tab: LabTab
    let metric: MetricKey?
    /// Higher = more interesting; the Today screen shows the top 3.
    let weight: Double
}

enum Insights {
    /// Everything we can say with at least a few days of overlap. Pure function so it is cheap to recompute.
    @MainActor
    static func build(_ store: LabStore, days: Int = 30) -> [Insight] {
        var out: [Insight] = []
        let ag = Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
        func a(_ m: String) -> Agreement? { ag.first { $0.metric == m && $0.n >= 3 } }

        // Resting HR gap
        if let r = a("Resting HR"), let b = r.bias {
            let who: Source = b >= 0 ? .watch : .whoop
            let other: Source = who == .watch ? .whoop : .watch
            if abs(b) >= 0.5 {
                out.append(Insight(id: "rhr-gap", icon: "heart.fill",
                                   title: "\(who.name) reads your resting HR \(fmt(abs(b), 1)) bpm higher",
                                   detail: "Average over \(r.n) days both measured it, vs \(other.name). They agree within 3 bpm on \(Int(r.agreePercent ?? 0))% of days.",
                                   source: who, tab: .heart, metric: .rhr, weight: 6 + abs(b)))
            } else {
                out.append(Insight(id: "rhr-gap", icon: "heart.fill",
                                   title: "Resting HR is a dead heat",
                                   detail: "Apple Watch and WHOOP average within \(fmt(abs(b), 1)) bpm of each other over \(r.n) days.",
                                   source: nil, tab: .heart, metric: .rhr, weight: 5))
            }
        }

        // HRV trend agreement
        if let h = a("HRV"), let p = h.agreePercent {
            out.append(Insight(id: "hrv-trend", icon: "waveform.path.ecg",
                               title: "Your HRV trend agrees \(Int(p.rounded()))% between devices",
                               detail: "Days where both moved the same direction. Values differ by design (Watch = SDNN, WHOOP = RMSSD), so the trend is what counts. r = \(fmt(h.correlation ?? 0, 2)).",
                               source: nil, tab: .compare, metric: .hrv, weight: 7 + (p >= 75 ? 1 : 0)))
        }

        // Best sleep this week
        let weekCut = Date().dayStart.adding(days: -6)
        let week = store.sleeps.filter { $0.night >= weekCut }
        if let best = week.max(by: { $0.asleepMin < $1.asleepMin }), best.asleepMin > 0 {
            let other = week.first { $0.source != best.source && Calendar.current.isDate($0.night, inSameDayAs: best.night) }
            let day = best.night.formatted(.dateTime.weekday(.abbreviated))
            var d = "\(fmtHM(best.asleepMin)) (\(best.source.name))"
            if let o = other { d += " / \(fmtHM(o.asleepMin)) (\(o.source.name))" }
            out.append(Insight(id: "best-sleep", icon: "moon.stars.fill", title: "Best sleep this week: \(day)",
                               detail: d, source: best.source, tab: .sleep, metric: .sleep, weight: 6))
        }

        // Sleep total gap
        if let s = a("Sleep"), let b = s.bias, abs(b) >= 0.15 {
            let who: Source = b >= 0 ? .watch : .whoop
            out.append(Insight(id: "sleep-gap", icon: "bed.double.fill",
                               title: "\(who.name) credits you \(fmtHM(abs(b) * 60)) more sleep",
                               detail: "Average per night over \(s.n) nights. Trackers draw the line between light sleep and awake differently.",
                               source: who, tab: .sleep, metric: .sleep, weight: 5 + abs(b) * 4))
        }

        // Recovery after short nights (WHOOP recovery, else Watch readiness)
        if let note = shortSleepEffect(store) { out.append(note) }

        // Workout calories
        let pairs = Compare.matchWorkouts(store.workouts.filter { $0.start >= Date().dayStart.adding(days: -(days - 1)) }).pairs
        let kc = pairs.compactMap { p -> (Double, Double)? in
            guard let a = p.watch.kcal, let b = p.whoop.kcal, a > 0, b > 0 else { return nil }
            return (a, b)
        }
        if kc.count >= 2 {
            let sa = kc.map { $0.0 }.reduce(0, +), sb = kc.map { $0.1 }.reduce(0, +)
            let pct = (sa / sb - 1) * 100
            let who: Source = pct >= 0 ? .watch : .whoop
            let other: Source = who == .watch ? .whoop : .watch
            let mag = who == .watch ? pct : (sb / sa - 1) * 100
            out.append(Insight(id: "workout-kcal", icon: "flame.fill",
                               title: "Workouts: \(who.name) counts \(Int(abs(mag).rounded()))% more calories than \(other.name)",
                               detail: "Across \(kc.count) workouts both tracked at the same time.",
                               source: who, tab: .activity, metric: nil, weight: 5 + min(4, abs(mag) / 10)))
        }

        // Daily calories
        if let c = a("Calories"), let b = c.bias, abs(b) >= 50 {
            let who: Source = b >= 0 ? .watch : .whoop
            out.append(Insight(id: "kcal-gap", icon: "bolt.fill",
                               title: "\(who.name) logs \(Int(abs(b).rounded())) more kcal a day",
                               detail: "Total daily burn, averaged over \(c.n) days. WHOOP estimates from heart rate alone; Apple Watch adds motion.",
                               source: who, tab: .activity, metric: .calories, weight: 4 + min(3, abs(b) / 150)))
        }

        // Readiness vs recovery
        if let r = store.readinessToday, let w = store.recoveryToday {
            let d = Int((r - w).rounded())
            out.append(Insight(id: "ready-today", icon: "gauge.with.dots.needle.67percent",
                               title: abs(d) <= 8 ? "Both say you're \(band(w)) today" : (d > 0 ? "Your Watch is \(d) points more optimistic today" : "WHOOP is \(-d) points more optimistic today"),
                               detail: "Watch readiness \(Int(r)) vs WHOOP recovery \(Int(w)).",
                               source: nil, tab: .heart, metric: .recovery, weight: 6.5))
        }

        // Streak
        let st = streak(store)
        if st >= 2 {
            out.append(Insight(id: "streak", icon: "link",
                               title: "\(st)-day double-wear streak",
                               detail: "Days in a row with data from both Apple Watch and WHOOP. Longer streaks make every comparison sharper.",
                               source: nil, tab: .compare, metric: nil, weight: 3 + min(3, Double(st) / 7)))
        }

        return out.sorted { $0.weight > $1.weight }
    }

    /// Days in a row (ending today or yesterday) where both trackers recorded something.
    @MainActor
    static func streak(_ store: LabStore) -> Int {
        func has(_ d: DayStat?) -> Bool { d.map { $0.rhr != nil || $0.hrv != nil || $0.totalKcal != nil || $0.recovery != nil } ?? false }
        var day = Date().dayStart
        if !(has(store.watchDays.stat(on: day)) && has(store.whoopDays.stat(on: day))) { day = day.adding(days: -1) }
        var n = 0
        while n < 400, has(store.watchDays.stat(on: day)), has(store.whoopDays.stat(on: day)) {
            n += 1
            day = day.adding(days: -1)
        }
        return n
    }

    @MainActor
    private static func shortSleepEffect(_ store: LabStore) -> Insight? {
        let useWhoop = store.whoopDays.contains { $0.recovery != nil }
        let src: Source = useWhoop ? .whoop : .watch
        let scores = Dictionary(store.days(src).compactMap { d in d.recovery.map { (d.day, $0) } }, uniquingKeysWith: { a, _ in a })
        var short: [Double] = [], normal: [Double] = []
        for n in store.sleeps where n.source == src && n.asleepMin > 0 {
            guard let r = scores[n.night.dayStart] else { continue }
            if n.asleepMin < 360 { short.append(r) } else { normal.append(r) }
        }
        guard short.count >= 2, normal.count >= 3, let s = Stats.mean(short), let m = Stats.mean(normal), m - s >= 4 else { return nil }
        let what = useWhoop ? "WHOOP recovery" : "Watch readiness"
        return Insight(id: "short-sleep", icon: "zzz",
                       title: "Recovery dips after nights under 6h",
                       detail: "\(what) averages \(Int(s)) after short nights vs \(Int(m)) otherwise (\(short.count) short nights).",
                       source: src, tab: .sleep, metric: .recovery, weight: 7.5)
    }

    private static func fmt(_ v: Double, _ d: Int) -> String { v.formatted(.number.precision(.fractionLength(d))) }
    private static func band(_ s: Double) -> String { s >= 67 ? "well recovered" : s >= 34 ? "in the middle" : "running low" }
}
