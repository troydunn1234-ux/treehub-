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
    /// Why the two trackers differ on this metric, in one or two sentences.
    var why: String { Compare.why[metric] ?? "" }

    /// The whole comparison in plain words: averages, who's higher, by how much, how often they agree.
    var plain: String {
        guard n >= 3, let mw = meanWatch, let mh = meanWhoop else {
            return n == 0 ? "Neither tracker has this yet." : "Only \(n) day\(n == 1 ? "" : "s") so far where both measured this — the verdict needs 3."
        }
        let f: (Double) -> String = { abs($0) < 10 ? String(format: "%.1f", $0) : String(format: "%.0f", $0) }
        if trendOnly {
            let r = correlation ?? 0
            let how = r > 0.6 ? "rise and fall together almost every day" : r > 0.3 ? "usually move the same way" : "often move in different directions"
            return "Over \(n) days your Watch averaged \(f(mw)) \(unit) and WHOOP \(f(mh)) \(unit). The numbers aren't the same scale, so look at direction: they \(how)."
        }
        let b = bias ?? 0
        let higherDays = pairs.filter { $0.watch > $0.whoop }.count
        let within = pairs.filter { abs($0.watch - $0.whoop) <= tolerance }.count
        var who: String
        if abs(b) <= tolerance * 0.25 { who = "They land on about the same number." }
        else if b > 0 { who = "Your Watch reads higher on \(higherDays) of \(n) days, by about \(f(abs(b))) \(unit)." }
        else { who = "WHOOP reads higher on \(n - higherDays) of \(n) days, by about \(f(abs(b))) \(unit)." }
        return "Over \(n) days your Watch averaged \(f(mw)) \(unit) and WHOOP \(f(mh)) \(unit). \(who) They're within \(tolerance.formatted()) \(unit) of each other on \(within) of \(n) days."
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

    #if DEBUG
    /// Sanity checks on the comparison maths, run once at launch in Debug builds.
    static func selfCheck() {
        let x = [50.0, 52, 55, 53, 58, 60], y = x.map { $0 + 2 }
        assert(abs((pearson(x, y) ?? 0) - 1) < 1e-9, "perfectly shifted series must correlate 1.0")
        assert(abs((pearson(x, x.map { 100 - $0 }) ?? 0) + 1) < 1e-9, "mirrored series must correlate -1.0")
        assert(pearson([1, 1, 1], [2, 3, 4]) == nil, "flat series has no correlation")
        let days = (0..<6).map { Date().dayStart.adding(days: -$0) }
        let pairs = zip(days, zip(x, y)).map { Agreement.Pair(day: $0.0, watch: $0.1.0, whoop: $0.1.1) }
        let a = Agreement(metric: "t", unit: "u", tolerance: 3, trendOnly: false, pairs: pairs)
        assert(abs((a.bias ?? 0) + 2) < 1e-9, "mean difference should be −2")
        assert(abs((a.meanAbsDiff ?? 0) - 2) < 1e-9, "mean absolute difference should be 2")
        assert(a.agreePercent == 100, "all pairs within tolerance 3")
        assert(a.higher == .whoop, "WHOOP reads higher here")
        let wide = Agreement(metric: "t", unit: "u", tolerance: 1, trendOnly: false, pairs: pairs)
        assert(wide.agreePercent == 0, "none within tolerance 1")
        let trend = Agreement(metric: "t", unit: "u", tolerance: 1, trendOnly: true, pairs: pairs)
        assert(trend.agreePercent == 100, "same direction every day")
        assert(mean([]) == nil && sd([1]) == nil, "empty stats are nil, not 0")
        // Readiness: a day exactly at baseline with no sleep scores the starting 55, and every point is itemised.
        let today = Date().dayStart
        let flat = (0...8).map { i -> DayStat in var s = DayStat(day: today.adding(days: -i)); s.hrv = 50; s.rhr = 55; return s }
        let r = Compare.readinessDetail(day: today, watch: flat, sleeps: [], carryOver: false)
        assert(r?.score == 55 && r?.baselineDays == 7, "baseline day scores 55 on a 7-day baseline")
        assert(abs((r?.parts.map(\.points).reduce(0, +) ?? 1)) < 1e-9, "no points at baseline")
    }
    #endif
}

enum Compare {
    /// Known reasons each pair disagrees — so a gap reads as "expected", not "broken".
    static let why: [String: String] = [
        "Resting HR": "WHOOP takes resting HR during your deepest sleep. Apple takes it from calm moments across the whole day, which runs a few beats higher. A 2–5 bpm gap is normal.",
        "HRV": "Apple reports SDNN, WHOOP reports RMSSD — different formulas on different windows (Apple: short daytime samples; WHOOP: last slow-wave sleep). Compare the trend, never the number.",
        "Respiratory rate": "Both measure overnight. The Watch samples less often, so a 1 br/min gap is noise.",
        "Blood oxygen": "Both read overnight from the wrist. Watch readings are spot checks; WHOOP averages the night. Within 2% is the same number.",
        "Temp deviation": "Both show change from your own baseline, not a thermometer reading. Apple measures wrist temperature in sleep; WHOOP measures skin temperature on the strap, which sits tighter.",
        "Calories": "Apple = active + resting energy from Watch motion and HR. WHOOP = one total per cycle from HR alone, converted from kJ. WHOOP usually comes in lower on active days. A 250 kcal gap is normal.",
        "Sleep": "WHOOP's night is strap-based and ends at wake; Apple's comes from the Watch and the Sleep schedule. 20 minutes apart is normal; big gaps are usually one side missing a nap or a late bedtime.",
    ]

    struct Spec { let metric: String; let unit: String; let tol: Double; let trend: Bool; let get: (DayStat) -> Double? }

    static var dailySpecs: [Spec] { [
        Spec(metric: "Resting HR", unit: "bpm", tol: 3, trend: false) { $0.rhr },
        Spec(metric: "HRV", unit: "ms", tol: 0, trend: true) { $0.hrv },
        Spec(metric: "Respiratory rate", unit: "br/min", tol: 1, trend: false) { $0.resp },
        Spec(metric: "Blood oxygen", unit: "%", tol: 2, trend: false) { $0.spo2 },
        Spec(metric: "Temp deviation", unit: Units.fahrenheit ? "°F" : "°C", tol: Units.fahrenheit ? 0.5 : 0.3, trend: false) { Units.tempDelta($0.tempDev).0 },
        Spec(metric: "Calories", unit: "kcal", tol: 250, trend: false) { $0.totalKcal },
    ] }

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
    /// HRV vs your personal baseline (biggest weight), resting HR vs baseline, last night's sleep, and small
    /// penalties for raised breathing rate or wrist temperature. Every point is itemised in `ReadinessDetail.parts`.
    static func readiness(day: Date, watch: [DayStat], sleeps: [SleepNight]) -> Double? {
        readinessDetail(day: day, watch: watch, sleeps: sleeps, carryOver: false)?.score
    }

    /// Days of history `readinessDetail` looks back over (the day itself plus this many before it).
    static let readinessLookback = 14

    /// The score and exactly how it was reached, so the app can show every step.
    struct ReadinessDetail {
        /// One ingredient of the score.
        struct Part: Identifiable {
            enum Kind: String, CaseIterable { case hrv, rhr, sleep, resp, temp }
            let kind: Kind
            /// Today's value (display units), nil when the Watch has none.
            var value: Double?
            /// What it's compared with: your baseline average, or the 7 h sleep target.
            var baseline: Double?
            /// Points added (+) or taken away (−). 0 when the part couldn't be scored.
            var points: Double = 0
            /// The value came from yesterday (nothing recorded since midnight).
            var fromYesterday = false
            /// Most this part can move the score, each way, for the bar in the breakdown.
            var maxUp: Double
            var maxDown: Double
            var id: String { kind.rawValue }
            var scored: Bool { value != nil && baseline != nil }
            var diff: Double? { guard let v = value, let b = baseline else { return nil }; return v - b }

            var title: String {
                switch kind {
                case .hrv: String(localized: "Heart rate variability")
                case .rhr: String(localized: "Resting heart rate")
                case .sleep: String(localized: "Sleep (Watch)")
                case .resp: String(localized: "Breathing rate")
                case .temp: String(localized: "Wrist temperature")
                }
            }
            var unit: String {
                switch kind {
                case .hrv: "ms"
                case .rhr: "bpm"
                case .sleep: "h"
                case .resp: "br/min"
                case .temp: Units.fahrenheit ? "°F" : "°C"
                }
            }
            var decimals: Int { switch kind { case .hrv, .rhr: 0; case .sleep, .resp: 1; case .temp: 2 } }
            var symbol: String {
                switch kind {
                case .hrv: "waveform.path.ecg"
                case .rhr: "heart.fill"
                case .sleep: "moon.zzz.fill"
                case .resp: "lungs.fill"
                case .temp: "thermometer.medium"
                }
            }
            /// AllStats id, so the breakdown can open the metric's own detail.
            var statID: String { switch kind { case .hrv: "hrv"; case .rhr: "rhr"; case .sleep: "asleep"; case .resp: "resp"; case .temp: "tempDev" } }
            /// What "baseline" means for this part.
            var baselineLabel: String {
                switch kind {
                case .sleep: String(localized: "Target")
                case .temp: String(localized: "Your normal")
                default: String(localized: "Baseline")
                }
            }
            /// The rule, in one line.
            var rule: String {
                switch kind {
                case .hrv: String(localized: "±22 points per standard deviation from your baseline, capped at ±1.6 SD (±35 points).")
                case .rhr: String(localized: "−4 points per bpm above your baseline, +4 per bpm below (−20 to +16).")
                case .sleep: String(localized: "±10 points per 1.2 h from 7 h asleep (−15 to +10). Needs the Watch worn to bed.")
                case .resp: String(localized: "Penalty only: −3 points per br/min more than 0.5 above your baseline (up to −6).")
                case .temp: String(localized: "Penalty only: −1 point per 0.1 °C more than 0.3 °C above your normal (up to −6).")
                }
            }
        }

        var score: Double
        var usedYesterday: Bool
        /// Score before it was clamped to 1–99.
        var raw: Double = 55
        /// 7 or 14: how many days the HRV / resting HR baseline covered.
        var baselineDays = 7
        /// How many earlier days actually had HRV or resting HR in that window.
        var baselineSamples = 0
        var parts: [Part] = []
        /// What's missing, in plain words ("Wear your Watch to sleep for overnight HRV").
        var missing: [String] = []
        static let start = 55.0
    }

    /// `carryOver`: for *today's* score, fall back to yesterday's HRV / resting HR when the Watch hasn't
    /// recorded any since midnight (it isn't worn to bed, and Apple writes resting HR late in the day).
    static func readinessDetail(day: Date, watch: [DayStat], sleeps: [SleepNight], carryOver: Bool) -> ReadinessDetail? {
        let cal = Calendar.current
        let sorted = watch.sorted { $0.day < $1.day }
        let todayStat = sorted.last(where: { cal.isDate($0.day, inSameDayAs: day) })
        if todayStat == nil && !carryOver { return nil }
        let yesterday = carryOver ? sorted.last(where: { cal.isDate($0.day, inSameDayAs: day.adding(days: -1)) }) : nil
        var hrv = todayStat?.hrv, rhr = todayStat?.rhr
        var hrvOld = false, rhrOld = false
        if hrv == nil, let y = yesterday?.hrv { hrv = y; hrvOld = true }
        if rhr == nil, let y = yesterday?.rhr { rhr = y; rhrOld = true }
        guard hrv != nil || rhr != nil else { return nil }
        let used = hrvOld || rhrOld

        // Baseline: the days before the day the readings came from. 14 days once at least 10 of them
        // have readings (steadier), otherwise the last 7.
        let anchor = used ? day.dayStart.adding(days: -1) : day.dayStart
        let prior14 = sorted.filter { $0.day < anchor && $0.day >= anchor.adding(days: -14) }
        let filled14 = prior14.filter { $0.hrv != nil || $0.rhr != nil }.count
        let window = filled14 >= 10 ? 14 : 7
        let prior = prior14.filter { $0.day >= anchor.adding(days: -window) }
        let hrvVals = prior.compactMap(\.hrv), rhrVals = prior.compactMap(\.rhr)
        let hrvBase = Stats.mean(hrvVals), hrvSD = Stats.sd(hrvVals)
        let rhrBase = Stats.mean(rhrVals)

        typealias Part = ReadinessDetail.Part
        var d = ReadinessDetail(score: 0, usedYesterday: used, baselineDays: window,
                                baselineSamples: prior.filter { $0.hrv != nil || $0.rhr != nil }.count)
        var score = ReadinessDetail.start

        var pHRV = Part(kind: .hrv, value: hrv, baseline: hrvBase, fromYesterday: hrvOld, maxUp: 22 * 1.6, maxDown: 22 * 1.6)
        if let v = hrv, let b = hrvBase {
            let z = (v - b) / max(hrvSD ?? b * 0.15, 1)
            pHRV.points = 22 * max(-1.6, min(1.6, z))
        }
        var pRHR = Part(kind: .rhr, value: rhr, baseline: rhrBase, fromYesterday: rhrOld, maxUp: 16, maxDown: 20)
        if let r = rhr, let b = rhrBase {
            pRHR.points = -4 * max(-4, min(5, r - b))
        }
        var pSleep = Part(kind: .sleep, baseline: 7, maxUp: 10, maxDown: 15)
        if let s = sleeps.last(where: { $0.source == .watch && cal.isDate($0.night, inSameDayAs: day) }), s.asleepMin > 0 {
            pSleep.value = s.asleepMin / 60
            pSleep.points = 10 * max(-1.5, min(1, (s.asleepMin / 60 - 7) / 1.2))
        }
        // Overnight extras: only from the day itself (yesterday's night says nothing about this morning).
        let respVals = prior.compactMap(\.resp)
        var pResp = Part(kind: .resp, value: todayStat?.resp, baseline: respVals.count >= 3 ? Stats.mean(respVals) : nil, maxUp: 0, maxDown: 6)
        if let v = pResp.value, let b = pResp.baseline, v - b > 0.5 {
            pResp.points = -min(6, 3 * (v - b - 0.5))
        }
        var pTemp = Part(kind: .temp, value: todayStat?.tempDev.flatMap { Units.tempDelta($0).0 }, baseline: todayStat?.tempDev == nil ? nil : 0, maxUp: 0, maxDown: 6)
        if let c = todayStat?.tempDev, c > 0.3 {
            pTemp.points = -min(6, 10 * (c - 0.3))
        }
        d.parts = [pHRV, pRHR, pSleep]
        if pResp.value != nil { d.parts.append(pResp) }
        if pTemp.value != nil { d.parts.append(pTemp) }
        for p in d.parts { score += p.points }

        if hrv == nil { d.missing.append(String(localized: "No HRV from the Watch in the last day. Wear your Watch to sleep for overnight HRV, or take a Breathe session for a spot reading.")) }
        else if hrvBase == nil { d.missing.append(String(localized: "Not enough earlier HRV for a baseline yet. It builds after a few days of wear.")) }
        if rhr == nil { d.missing.append(String(localized: "No resting heart rate yet. Apple writes it after a few hours of wear, often later in the day.")) }
        else if rhrBase == nil { d.missing.append(String(localized: "Not enough earlier resting heart rate for a baseline yet.")) }
        if pSleep.value == nil { d.missing.append(String(localized: "No Watch sleep for last night, so sleep adds nothing. Wear your Watch to sleep with Sleep tracking on.")) }
        if pResp.value == nil && pTemp.value == nil {
            d.missing.append(String(localized: "Breathing rate and wrist temperature come from Watch sleep tracking; they only ever take points off, never add."))
        }

        d.raw = score.rounded()
        d.score = max(1, min(99, score.rounded()))
        return d
    }
}
