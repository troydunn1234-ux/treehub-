import Foundation

/// Pulse Lab's signature, for one day: where Apple Watch and WHOOP agree and where they split on the four numbers
/// both report: resting heart rate, HRV, last night's sleep and yesterday's strain. Shown first on Today, and
/// handed to the widgets and the Watch complication as one agreement score (WidgetBridge / WatchSync).
///
/// Fair comparisons only: resting HR and sleep compare the readings themselves; HRV (SDNN vs RMSSD) and strain
/// (WHOOP strain vs Watch active calories) aren't on the same scale, so they compare which way each tracker
/// moved against its own last 7 days. A metric only counts when both trackers have a recent reading.
struct TodayAgreement: Equatable {
    struct Row: Identifiable, Equatable {
        enum Metric: String, CaseIterable { case rhr, hrv, sleep, strain }
        let metric: Metric
        /// What each side read, ready to show ("52 bpm", "7h 12m", "Up 8%"). Nil = nothing recent.
        let watch: String?
        let whoop: String?
        /// Nil when only one side (or neither) has a reading.
        let agree: Bool?
        /// One line on why ("3 bpm apart", "Both below their week").
        let detail: String
        /// How far apart the two readings are, in the row's own unit (bpm, minutes). Nil for the trend rows.
        var gap: Double? = nil
        var id: String { metric.rawValue }

        var title: String {
            switch metric {
            case .rhr: String(localized: "Resting HR")
            case .hrv: String(localized: "HRV")
            case .sleep: String(localized: "Sleep")
            case .strain: String(localized: "Strain")
            }
        }

        /// The name inside a sentence ("They agree on resting HR"). Its own keys, so Spanish can add the article.
        var noun: String {
            switch metric {
            case .rhr: String(localized: "rhr.inSentence", defaultValue: "resting HR")
            case .hrv: String(localized: "hrv.inSentence", defaultValue: "HRV")
            case .sleep: String(localized: "sleep.inSentence", defaultValue: "sleep")
            case .strain: String(localized: "strain.inSentence", defaultValue: "strain")
            }
        }

        /// Plain words for a split ("sleep is off by 42 min"); nil when they agree or weren't compared.
        var why: String? {
            guard agree == false else { return nil }
            switch metric {
            case .rhr:
                guard let gap else { return String(localized: "resting HR is off") }
                return String(localized: "resting HR is off by \(Int(gap.rounded())) bpm")
            case .sleep:
                guard let gap else { return String(localized: "sleep is off") }
                return String(localized: "sleep is off by \(TodayAgreement.span(gap))")
            case .hrv: return String(localized: "HRV is moving different ways")
            case .strain: return String(localized: "strain is moving different ways")
            }
        }

        /// What a side with nothing shows instead of a bare dash.
        var missing: String {
            switch metric {
            case .rhr, .hrv: String(localized: "Not in yet")
            case .sleep: String(localized: "No sleep")
            case .strain: String(localized: "No data")
            }
        }
    }

    let rows: [Row]

    var compared: Int { rows.filter { $0.agree != nil }.count }
    var agreeing: Int { rows.filter { $0.agree == true }.count }
    /// 0–100: share of the compared metrics the two trackers agree on. Nil until at least one metric compares.
    var score: Double? { compared > 0 ? (Double(agreeing) / Double(compared) * 100).rounded() : nil }
    /// Short names of the metrics they split on ("HRV, Sleep").
    var splits: [String] { rows.filter { $0.agree == false }.map(\.title) }

    /// True when every compared metric agrees and at least two were compared (the hero's small celebration).
    var fullAgreement: Bool { compared >= 2 && agreeing == compared }

    var headline: String {
        guard compared > 0 else { return String(localized: "Waiting for both trackers") }
        if compared == 1, let only = rows.first(where: { $0.agree != nil }) {
            return only.agree == true ? String(localized: "They agree on \(only.noun)") : String(localized: "They split on \(only.noun)")
        }
        if agreeing == compared {
            return compared == 2 ? String(localized: "They agree on both") : String(localized: "They agree on all \(compared)")
        }
        if agreeing == 0 {
            return compared == 2 ? String(localized: "They split on both") : String(localized: "They split on all \(compared)")
        }
        return String(localized: "They agree on \(agreeing) of \(compared)")
    }

    /// The plain-words line under the headline: by how much they split ("Sleep is off by 42 min."), or that they don't.
    var reason: String {
        guard compared > 0 else { return String(localized: "Each number needs a recent reading from both trackers.") }
        let whys = rows.compactMap(\.why)
        if whys.isEmpty {
            return compared == rows.count ? String(localized: "Same story on every number today.")
                : String(localized: "Same story on everything both measured.")
        }
        if whys.count <= 2 { return Self.sentence(whys.formatted(.list(type: .and))) }
        if agreeing == 0 { return String(localized: "Nothing lines up today. Tap a row to see by how much.") }
        let names = rows.filter { $0.agree == false }.map(\.noun)
        return String(localized: "They differ on \(names.formatted(.list(type: .and))).")
    }

    /// "42 min" under an hour, "1h 12m" from there.
    static func span(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m < 60 ? String(localized: "\(m) min") : fmtHM(Double(m))
    }

    /// Capital first letter and a full stop.
    private static func sentence(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + String(s.dropFirst()) + "."
    }

    // MARK: Tolerances

    static let rhrTolerance = 3.0       // bpm
    static let sleepTolerance = 30.0    // minutes
    /// Within ±8% of its own last 7 days counts as "about usual".
    static let usualBand = 0.08

    enum Move: Equatable {
        case up, usual, down
        init(ratio r: Double) { self = r > 1 + TodayAgreement.usualBand ? .up : r < 1 - TodayAgreement.usualBand ? .down : .usual }
        var word: String {
            switch self {
            case .up: String(localized: "above")
            case .usual: String(localized: "near")
            case .down: String(localized: "below")
            }
        }
    }

    // MARK: Building it

    @MainActor
    static func build(_ store: LabStore) -> TodayAgreement {
        let since = Date().dayStart.adding(days: -1)
        let ws = store.lastNight(.watch).flatMap { $0.night >= since && $0.asleepMin > 0 ? $0 : nil }
        let hs = store.lastNight(.whoop).flatMap { $0.night >= since && $0.asleepMin > 0 ? $0 : nil }
        let yesterday = Date().dayStart.adding(days: -1)
        return TodayAgreement(rows: [
            rhr(store.reading(.watch, \.rhr, recent: "rhr")?.value, store.reading(.whoop, \.rhr, manual: .rhr)?.value),
            trend(.hrv, ratio(store.days(.watch), \.hrv, latestWithin: since), ratio(store.days(.whoop), \.hrv, latestWithin: since)),
            sleep(ws?.asleepMin, hs?.asleepMin),
            trend(.strain, ratio(store.days(.watch), \.activeKcal, on: yesterday), ratio(store.days(.whoop), \.strain, on: yesterday)),
        ])
    }

    static func rhr(_ w: Double?, _ h: Double?) -> Row {
        let f: (Double) -> String = { String(localized: "\(Int($0.rounded())) bpm") }
        guard let w, let h else {
            return Row(metric: .rhr, watch: w.map(f), whoop: h.map(f), agree: nil, detail: String(localized: "Needs a reading from both"))
        }
        let gap = abs(w - h)
        let agree = gap <= rhrTolerance
        let detail = gap < 0.5 ? String(localized: "Same reading")
            : String(localized: "\(Int(gap.rounded())) bpm apart")
        return Row(metric: .rhr, watch: f(w), whoop: f(h), agree: agree, detail: detail, gap: gap)
    }

    static func sleep(_ w: Double?, _ h: Double?) -> Row {
        guard let w, let h else {
            return Row(metric: .sleep, watch: w.map { fmtHM($0) }, whoop: h.map { fmtHM($0) }, agree: nil,
                       detail: String(localized: "Needs last night from both"))
        }
        let gap = abs(w - h)
        let detail = gap < 5 ? String(localized: "Same night")
            : (w > h ? String(localized: "Watch counts \(fmtHM(gap)) more") : String(localized: "WHOOP counts \(fmtHM(gap)) more"))
        return Row(metric: .sleep, watch: fmtHM(w), whoop: fmtHM(h), agree: gap <= sleepTolerance, detail: detail, gap: gap)
    }

    /// HRV and strain: each tracker against its own last 7 days.
    static func trend(_ metric: Row.Metric, _ w: Double?, _ h: Double?) -> Row {
        func show(_ r: Double) -> String {
            let pct = Int(((r - 1) * 100).rounded())
            if pct == 0 { return String(localized: "Usual") }
            return pct > 0 ? String(localized: "Up \(pct)%") : String(localized: "Down \(-pct)%")
        }
        let base = metric == .strain ? String(localized: "Compares yesterday with each tracker's own week")
            : String(localized: "Compares each tracker with its own week")
        guard let w, let h else { return Row(metric: metric, watch: w.map(show), whoop: h.map(show), agree: nil, detail: base) }
        let mw = Move(ratio: w), mh = Move(ratio: h)
        let detail = mw == mh ? String(localized: "Both \(mw.word) their week")
            : String(localized: "Watch \(mw.word), WHOOP \(mh.word) their week")
        return Row(metric: metric, watch: show(w), whoop: show(h), agree: mw == mh, detail: detail)
    }

    /// Newest value (from `latestWithin` on) ÷ the average of the 7 days before it.
    static func ratio(_ days: [DayStat], _ kp: KeyPath<DayStat, Double?>, latestWithin since: Date) -> Double? {
        guard let last = days.last(where: { $0[keyPath: kp] != nil }), last.day >= since, let v = last[keyPath: kp] else { return nil }
        return ratio(days, kp, value: v, day: last.day)
    }

    /// That day's value ÷ the average of the 7 days before it.
    static func ratio(_ days: [DayStat], _ kp: KeyPath<DayStat, Double?>, on day: Date) -> Double? {
        guard let v = days.stat(on: day)?[keyPath: kp] else { return nil }
        return ratio(days, kp, value: v, day: day.dayStart)
    }

    private static func ratio(_ days: [DayStat], _ kp: KeyPath<DayStat, Double?>, value v: Double, day: Date) -> Double? {
        let from = day.adding(days: -7)
        let prior = days.filter { $0.day >= from && $0.day < day }.compactMap { $0[keyPath: kp] }
        guard prior.count >= 3, let base = Stats.mean(prior), base > 0 else { return nil }
        return v / base
    }
}
