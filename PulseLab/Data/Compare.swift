import Foundation

/// How closely two trackers agree on one metric over the days both measured it.
struct Agreement: Identifiable {
    struct Pair: Identifiable { let day: Date; let watch: Double; let whoop: Double; var id: Date { day } }

    let metric: String
    let unit: String
    let tolerance: Double
    /// HRV: Apple measures SDNN, WHOOP measures RMSSD, so absolute values differ by design.
    /// For trend-only metrics we score agreement on day-to-day direction and correlation, not on size.
    let trendOnly: Bool
    let pairs: [Pair]
    var id: String { metric }

    var n: Int { pairs.count }
    var meanWatch: Double? { n > 0 ? pairs.map(\.watch).reduce(0, +) / Double(n) : nil }
    var meanWhoop: Double? { n > 0 ? pairs.map(\.whoop).reduce(0, +) / Double(n) : nil }
    /// Mean of (Watch − WHOOP).
    var bias: Double? { n > 0 ? pairs.map { $0.watch - $0.whoop }.reduce(0, +) / Double(n) : nil }
    var meanAbsDiff: Double? { n > 0 ? pairs.map { abs($0.watch - $0.whoop) }.reduce(0, +) / Double(n) : nil }
    var sdDiff: Double? {
        guard n > 1, let b = bias else { return nil }
        let v = pairs.map { pow(($0.watch - $0.whoop) - b, 2) }.reduce(0, +) / Double(n - 1)
        return sqrt(v)
    }
    var correlation: Double? { Stats.pearson(pairs.map(\.watch), pairs.map(\.whoop)) }
    /// Share of days within tolerance (or, for trend-only, days where both moved the same way).
    var agreePercent: Double? {
        guard n > 0 else { return nil }
        if trendOnly {
            guard n > 1 else { return nil }
            var same = 0, total = 0
            for i in 1..<n {
                let a = pairs[i].watch - pairs[i - 1].watch, b = pairs[i].whoop - pairs[i - 1].whoop
                if abs(a) < 0.0001 && abs(b) < 0.0001 { continue }
                total += 1
                if (a >= 0) == (b >= 0) { same += 1 }
            }
            return total > 0 ? Double(same) / Double(total) * 100 : nil
        }
        return Double(pairs.filter { abs($0.watch - $0.whoop) <= tolerance }.count) / Double(n) * 100
    }
    /// Who usually reads higher, when the gap matters.
    var higher: Source? {
        guard !trendOnly, let b = bias, abs(b) > tolerance * 0.25 else { return nil }
        return b > 0 ? .watch : .whoop
    }
    /// Plain-English verdict.
    var verdict: String {
        guard n >= 3 else { return "Need a few more days where both measured this." }
        if trendOnly {
            let r = correlation ?? 0
            return r > 0.6 ? "Move together closely" : r > 0.3 ? "Mostly move together" : "Often disagree day to day"
        }
        let p = agreePercent ?? 0
        let lead = higher.map { " · \($0.name) reads higher" } ?? ""
        return (p >= 80 ? "Tight match" : p >= 55 ? "Close most days" : "Noticeable gap") + lead
    }
    var score: Double {
        if trendOnly { return max(0, min(100, ((correlation ?? 0) + 1) * 50 * 0.6 + (agreePercent ?? 50) * 0.4)) }
        return agreePercent ?? 0
    }
}

enum Stats {
    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        let mx = x.prefix(n).reduce(0, +) / Double(n), my = y.prefix(n).reduce(0, +) / Double(n)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in 0..<n {
            let a = x[i] - mx, b = y[i] - my
            sxy += a * b; sxx += a * a; syy += b * b
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / sqrt(sxx * syy)
    }

    static func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    static func sd(_ v: [Double]) -> Double? {
        guard v.count > 1, let m = mean(v) else { return nil }
        return sqrt(v.map { pow($0 - m, 2) }.reduce(0, +) / Double(v.count - 1))
    }
}

enum Compare {
    struct Spec { let metric: String; let unit: String; let tol: Double; let trend: Bool; let get: (DayStat) -> Double? }

    static let dailySpecs: [Spec] = [
        Spec(metric: "Resting HR", unit: "bpm", tol: 3, trend: false) { $0.rhr },
        Spec(metric: "HRV", unit: "ms", tol: 0, trend: true) { $0.hrv },
        Spec(metric: "Respiratory rate", unit: "br/min", tol: 1, trend: false) { $0.resp },
        Spec(metric: "Blood oxygen", unit: "%", tol: 2, trend: false) { $0.spo2 },
        Spec(metric: "Temp deviation", unit: "°C", tol: 0.3, trend: false) { $0.tempDev },
        Spec(metric: "Calories", unit: "kcal", tol: 250, trend: false) { $0.totalKcal },
    ]

    static func agreements(watch: [DayStat], whoop: [DayStat], sleeps: [SleepNight], days: Int) -> [Agreement] {
        let cut = Date().dayStart.adding(days: -(days - 1))
        let w = Dictionary(watch.filter { $0.day >= cut }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let h = Dictionary(whoop.filter { $0.day >= cut }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Agreement] = dailySpecs.map { spec in
            let pairs = w.keys.sorted().compactMap { d -> Agreement.Pair? in
                guard let a = w[d].flatMap(spec.get), let b = h[d].flatMap(spec.get) else { return nil }
                return Agreement.Pair(day: d, watch: a, whoop: b)
            }
            return Agreement(metric: spec.metric, unit: spec.unit, tolerance: spec.tol, trendOnly: spec.trend, pairs: pairs)
        }
        // Sleep: hours asleep and stage minutes, night by night.
        let ws = Dictionary(sleeps.filter { $0.source == .watch && $0.night >= cut }.map { ($0.night, $0) }, uniquingKeysWith: { a, b in a.asleepMin >= b.asleepMin ? a : b })
        let hs = Dictionary(sleeps.filter { $0.source == .whoop && $0.night >= cut }.map { ($0.night, $0) }, uniquingKeysWith: { a, b in a.asleepMin >= b.asleepMin ? a : b })
        func sleepAgreement(_ name: String, tol: Double, _ f: (SleepNight) -> Double) -> Agreement {
            let pairs = ws.keys.sorted().compactMap { d -> Agreement.Pair? in
                guard let a = ws[d], let b = hs[d] else { return nil }
                return Agreement.Pair(day: d, watch: f(a), whoop: f(b))
            }
            return Agreement(metric: name, unit: name == "Sleep" ? "h" : "min", tolerance: tol, trendOnly: false, pairs: pairs)
        }
        out.insert(sleepAgreement("Sleep", tol: 0.33) { $0.asleepMin / 60 }, at: 2)
        out.append(sleepAgreement("Deep sleep", tol: 20) { $0.deepMin })
        out.append(sleepAgreement("REM sleep", tol: 20) { $0.remMin })
        return out
    }

    /// Workouts from both trackers that overlap in time (at least half of the shorter one).
    struct WorkoutPair: Identifiable {
        let watch: WorkoutRec
        let whoop: WorkoutRec
        var id: String { watch.id + whoop.id }
    }

    static func matchWorkouts(_ all: [WorkoutRec]) -> (pairs: [WorkoutPair], watchOnly: [WorkoutRec], whoopOnly: [WorkoutRec]) {
        let w = all.filter { $0.source == .watch }.sorted { $0.start > $1.start }
        var h = all.filter { $0.source == .whoop }.sorted { $0.start > $1.start }
        var pairs: [WorkoutPair] = [], watchOnly: [WorkoutRec] = []
        for a in w {
            if let i = h.firstIndex(where: { b in
                let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
                return overlap > 0 && overlap >= 0.5 * min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
            }) {
                pairs.append(WorkoutPair(watch: a, whoop: h[i])); h.remove(at: i)
            } else {
                watchOnly.append(a)
            }
        }
        return (pairs, watchOnly, h)
    }

    /// Pulse Lab's own "readiness" for the Apple Watch, built to sit next to WHOOP recovery:
    /// HRV vs your 7-day baseline (biggest weight), resting HR vs baseline, and last night's sleep.
    static func readiness(day: Date, watch: [DayStat], sleeps: [SleepNight]) -> Double? {
        let sorted = watch.sorted { $0.day < $1.day }
        guard let today = sorted.last(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) else { return nil }
        let prior = sorted.filter { $0.day < today.day && $0.day >= today.day.adding(days: -7) }
        let hrvBase = Stats.mean(prior.compactMap(\.hrv)), hrvSD = Stats.sd(prior.compactMap(\.hrv))
        let rhrBase = Stats.mean(prior.compactMap(\.rhr))
        guard today.hrv != nil || today.rhr != nil else { return nil }
        var score = 55.0
        if let v = today.hrv, let b = hrvBase {
            let z = (v - b) / max(hrvSD ?? b * 0.15, 1)
            score += 22 * max(-1.6, min(1.6, z))
        }
        if let r = today.rhr, let b = rhrBase {
            score -= 4 * max(-4, min(5, r - b))
        }
        if let s = sleeps.last(where: { $0.source == .watch && Calendar.current.isDate($0.night, inSameDayAs: day) }) {
            score += 10 * max(-1.5, min(1, (s.asleepMin / 60 - 7) / 1.2))
        }
        return max(1, min(99, score.rounded()))
    }
}
