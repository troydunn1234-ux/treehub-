import Foundation
import HealthKit

/// Trends & correlations: how next-morning recovery, HRV and sleep look after days with vs without
/// something (a supplement, a sauna, a workout, a late meal, a drink). Plain averages of your own days,
/// with sample sizes and an effect size, never a claim about cause.
enum Correlations {
    /// Fewest days on each side before a comparison is shown.
    static let minDays = 5
    /// How far back to look.
    static let windowDays = 180

    enum OutcomeKind: String, CaseIterable, Identifiable {
        case recovery, hrv, sleep
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recovery: String(localized: "Recovery")
            case .hrv: String(localized: "HRV")
            case .sleep: String(localized: "Sleep")
            }
        }
    }

    struct Outcome {
        let kind: OutcomeKind
        /// "recovery", "Watch readiness", "HRV", "sleep" as used in a sentence.
        let noun: String
        let unit: String
        let decimals: Int
        /// Value keyed by the morning it belongs to.
        let byMorning: [Date: Double]

        func format(_ v: Double) -> String {
            if kind == .sleep { return fmtHM(v) }
            return v.formatted(.number.precision(.fractionLength(decimals))) + unit
        }
    }

    struct Factor: Identifiable {
        let id: String
        let title: String
        let icon: String
        /// Finishes "On days you …": "took Magnesium".
        let phrase: String
        /// Days (start of day) the thing happened.
        let exposed: Set<Date>
        /// Days that may count as "without" (nil = every day with an outcome).
        var eligible: ((Date) -> Bool)? = nil
    }

    enum Size: String {
        case none, small, moderate, large
        var label: String {
            switch self {
            case .none: String(localized: "No clear difference")
            case .small: String(localized: "Small difference")
            case .moderate: String(localized: "Moderate difference")
            case .large: String(localized: "Large difference")
            }
        }
    }

    struct Result: Identifiable {
        let factor: Factor
        let outcome: Outcome
        let on: [Double]
        let off: [Double]
        var id: String { factor.id }

        var enough: Bool { on.count >= Correlations.minDays && off.count >= Correlations.minDays }
        var onMean: Double? { Stats.mean(on) }
        var offMean: Double? { Stats.mean(off) }
        var diff: Double? { guard let a = onMean, let b = offMean else { return nil }; return a - b }
        /// Cohen's d with the pooled standard deviation.
        var effect: Double? {
            guard enough, let d = diff, let s1 = Stats.sd(on), let s2 = Stats.sd(off) else { return nil }
            let n1 = Double(on.count), n2 = Double(off.count)
            let pooled = sqrt(((n1 - 1) * s1 * s1 + (n2 - 1) * s2 * s2) / (n1 + n2 - 2))
            return pooled > 0 ? d / pooled : nil
        }
        var size: Size {
            guard let e = effect.map(abs) else { return .none }
            return e < 0.2 ? .none : e < 0.5 ? .small : e < 0.8 ? .moderate : .large
        }

        /// "On days you took Magnesium, your next-morning recovery averaged 68% (12 days), vs 61% on days you didn't (30 days)."
        var sentence: String {
            guard let a = onMean, let b = offMean else { return "" }
            return String(localized: "On days you \(factor.phrase), your next-morning \(outcome.noun) averaged \(outcome.format(a)) (\(on.count) days), vs \(outcome.format(b)) on days you didn't (\(off.count) days).")
        }
    }

    // MARK: Outcomes

    @MainActor
    static func outcome(_ kind: OutcomeKind, store: LabStore) -> Outcome {
        let cut = Date().dayStart.adding(days: -windowDays)
        func series(_ days: [DayStat], _ kp: KeyPath<DayStat, Double?>) -> [Date: Double] {
            var out: [Date: Double] = [:]
            for d in days where d.day >= cut { if let v = d[keyPath: kp] { out[d.day] = v } }
            return out
        }
        switch kind {
        case .recovery:
            let whoop = series(store.whoopDays, \.recovery)
            if whoop.count >= 10 {
                return Outcome(kind: kind, noun: String(localized: "WHOOP recovery"), unit: "%", decimals: 0, byMorning: whoop)
            }
            return Outcome(kind: kind, noun: String(localized: "Watch readiness"), unit: "", decimals: 0, byMorning: series(store.watchDays, \.recovery))
        case .hrv:
            let w = series(store.watchDays, \.hrv), h = series(store.whoopDays, \.hrv)
            let useWhoop = h.count > w.count
            return Outcome(kind: kind, noun: useWhoop ? String(localized: "WHOOP HRV") : String(localized: "Watch HRV"),
                           unit: " ms", decimals: 0, byMorning: useWhoop ? h : w)
        case .sleep:
            func nights(_ s: Source) -> [Date: Double] {
                var out: [Date: Double] = [:]
                for n in store.sleeps where n.source == s && n.night >= cut && n.asleepMin > 0 { out[n.night] = n.asleepMin }
                return out
            }
            let w = nights(.watch), h = nights(.whoop)
            return Outcome(kind: kind, noun: String(localized: "sleep"), unit: "", decimals: 0, byMorning: h.count > w.count ? h : w)
        }
    }

    // MARK: Factors

    @MainActor
    static func factors(store: LabStore, supps: [Supplement], doses: [SuppDose], extras: HealthExtras) -> [Factor] {
        var out: [Factor] = []
        let today = Date().dayStart
        for s in supps {
            let taken = Set(doses.filter { $0.suppID == s.id }.map { Day.date($0.day).dayStart })
            let since = min(s.createdAt.dayStart, taken.min() ?? today)
            out.append(Factor(id: "supp-\(s.id.uuidString)", title: "\(s.emoji) \(s.name)", icon: "pills.fill",
                              phrase: String(localized: "took \(s.name)"), exposed: taken,
                              eligible: { $0 >= since }))
        }
        if !extras.heatDays.isEmpty {
            out.append(Factor(id: "heat", title: String(localized: "Sauna or steam"), icon: "flame.fill",
                              phrase: String(localized: "had a sauna or steam session"), exposed: extras.heatDays))
        }
        let mindful = Set(store.watchDays.filter { ($0.mindfulMin ?? 0) >= 3 }.map(\.day))
        if !mindful.isEmpty {
            out.append(Factor(id: "mindful", title: String(localized: "Mindful session"), icon: "wind",
                              phrase: String(localized: "logged a mindful session"), exposed: mindful))
        }
        let worked = Set(store.workouts.filter { $0.minutes >= 10 }.map { $0.start.dayStart })
        if !worked.isEmpty {
            out.append(Factor(id: "workout", title: String(localized: "Workout"), icon: "figure.run",
                              phrase: String(localized: "worked out"), exposed: worked))
        }
        let hard = Set(store.whoopDays.filter { ($0.strain ?? 0) >= 14 }.map(\.day))
        let strainDays = Set(store.whoopDays.filter { $0.strain != nil }.map(\.day))
        if !strainDays.isEmpty {
            out.append(Factor(id: "strain", title: String(localized: "High strain (14+)"), icon: "bolt.fill",
                              phrase: String(localized: "hit a WHOOP strain of 14 or more"), exposed: hard,
                              eligible: { strainDays.contains($0) }))
        }
        if !extras.foodDays.isEmpty {
            let food = extras.foodDays
            out.append(Factor(id: "late-eating", title: String(localized: "Late eating (after 9 pm)"), icon: "fork.knife",
                              phrase: String(localized: "logged food after 9 pm"), exposed: extras.lateEatingDays,
                              eligible: { food.contains($0) }))
        }
        if let first = extras.firstAlcoholDay {
            out.append(Factor(id: "alcohol", title: String(localized: "Alcohol"), icon: "wineglass.fill",
                              phrase: String(localized: "logged a drink"), exposed: Set(extras.alcoholDays),
                              eligible: { $0 >= first }))
        }
        return out
    }

    static func compare(_ f: Factor, _ o: Outcome) -> Result {
        var on: [Double] = [], off: [Double] = []
        let today = Date().dayStart
        for (morning, v) in o.byMorning {
            let day = morning.adding(days: -1)
            guard day < today else { continue }
            if f.exposed.contains(day) { on.append(v) }
            else if f.eligible?(day) ?? true { off.append(v) }
        }
        return Result(factor: f, outcome: o, on: on, off: off)
    }
}

/// Health data only the Insights screen needs, read when it opens (not part of the main sync).
struct HealthExtras {
    var heatDays: Set<Date> = []
    var foodDays: Set<Date> = []
    var lateEatingDays: Set<Date> = []
    var alcoholDays: Set<Date> = []
    var firstAlcoholDay: Date?
}

final class InsightsHealth: @unchecked Sendable {
    static let shared = InsightsHealth()
    private var store: HKHealthStore { HealthPull.shared.store }
    static let alcoholAskedKey = "insightsAlcoholAsked"

    static var alcoholAsked: Bool { UserDefaults.standard.bool(forKey: alcoholAskedKey) }

    /// Alcohol isn't part of the main Health request; ask only when someone wants it in Insights.
    func requestAlcohol() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: [HKQuantityType(.numberOfAlcoholicBeverages)])
        UserDefaults.standard.set(true, forKey: Self.alcoholAskedKey)
    }

    func load(days: Int = Correlations.windowDays) async -> HealthExtras {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        guard HKHealthStore.isHealthDataAvailable(), !demo else { return demo ? Self.demo() : HealthExtras() }
        let start = Date().dayStart.adding(days: -days)
        var x = HealthExtras()

        // Sauna & steam: workouts Still Pointz saves with its session title.
        let workouts = await samples(HKObjectType.workoutType(), from: start)
        for case let w as HKWorkout in workouts {
            let title = (w.metadata?["StillPointTitle"] as? String ?? "").lowercased()
            let brand = (w.metadata?[HKMetadataKeyWorkoutBrandName] as? String ?? "").lowercased()
            if title.contains("sauna") || title.contains("steam") || brand.contains("sauna") {
                x.heatDays.insert(w.startDate.dayStart)
            }
        }

        // Meal timing: food energy samples. Anything from 9 pm to 3 am counts toward the evening it belongs to.
        let cal = Calendar.current
        let food = await samples(HKQuantityType(.dietaryEnergyConsumed), from: start)
        for s in food {
            let h = cal.component(.hour, from: s.startDate)
            let evening = h < 3 ? s.startDate.dayStart.adding(days: -1) : s.startDate.dayStart
            x.foodDays.insert(evening)
            if h >= 21 || h < 3 { x.lateEatingDays.insert(evening) }
        }

        if Self.alcoholAsked {
            let drinks = await samples(HKQuantityType(.numberOfAlcoholicBeverages), from: start)
            for case let s as HKQuantitySample in drinks
            where s.quantity.doubleValue(for: .count()) > 0 {
                x.alcoholDays.insert(s.startDate.dayStart)
            }
            x.firstAlcoholDay = x.alcoholDays.min()
        }
        return x
    }

    private func samples(_ type: HKSampleType, from start: Date) async -> [HKSample] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
    }

    /// Screenshots / simulator QA: a believable pattern so the screen isn't empty.
    static func demo() -> HealthExtras {
        var x = HealthExtras()
        let today = Date().dayStart
        for i in 1...60 {
            let d = today.adding(days: -i)
            if i % 3 == 0 { x.heatDays.insert(d) }
            x.foodDays.insert(d)
            if i % 4 == 1 { x.lateEatingDays.insert(d) }
            if i % 6 == 2 { x.alcoholDays.insert(d) }
        }
        x.firstAlcoholDay = today.adding(days: -60)
        return x
    }
}
