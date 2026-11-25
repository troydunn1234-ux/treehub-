import Foundation
import SwiftUI

/// The "All data" catalogue: every number Pulse Lab syncs, grouped into sections, each with a way to
/// read its full history from the store (Apple side and WHOOP side kept apart, as everywhere else).
enum StatSection: String, CaseIterable, Identifiable {
    case recovery, sleep, strain, heart, body, mobility, nutrition

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .strain: "Strain & activity"
        case .heart: "Heart"
        case .body: "Body"
        case .mobility: "Mobility"
        case .nutrition: "Nutrition & mind"
        }
    }
    var icon: String {
        switch self {
        case .recovery: "battery.100.bolt"
        case .sleep: "moon.zzz.fill"
        case .strain: "flame.fill"
        case .heart: "heart.fill"
        case .body: "figure.stand"
        case .mobility: "figure.walk.motion"
        case .nutrition: "fork.knife"
        }
    }
    var tint: Color {
        switch self {
        case .recovery: Lab.good
        case .sleep: Lab.violet
        case .strain: Lab.whoop
        case .heart: Lab.bad
        case .body: Lab.watch
        case .mobility: Lab.watch
        case .nutrition: Lab.warn
        }
    }
}

struct StatPoint: Equatable {
    let day: Date
    let value: Double
}

/// One metric's full history, oldest first, per side.
struct StatSeries: Equatable {
    var watch: [StatPoint] = []
    var whoop: [StatPoint] = []
    var isEmpty: Bool { watch.isEmpty && whoop.isEmpty }
    func points(_ s: Source) -> [StatPoint] { s == .watch ? watch : whoop }
}

struct StatDef: Identifiable {
    let id: String
    let section: StatSection
    let title: String
    let unit: String
    var decimals: Int = 0
    /// Health type id, to look up which device the Apple side actually came from.
    var healthID: String? = nil
    /// Badge for the Apple side when Health didn't say ("WATCH", "IPHONE", "HEALTH"…).
    var appleBadge: String = "WATCH"
    /// When both sides have the same day, show WHOOP's number first.
    var preferWhoop = false
    var note: String
    let read: @MainActor (LabStore) -> StatSeries
}

@MainActor
enum AllStats {
    // MARK: Readers

    static func days(_ kp: KeyPath<DayStat, Double?>, sides: Set<Source> = [.watch, .whoop],
                             _ f: @escaping (Double) -> Double = { $0 }) -> @MainActor (LabStore) -> StatSeries {
        { store in
            var s = StatSeries()
            func pts(_ d: [DayStat]) -> [StatPoint] { d.compactMap { x in x[keyPath: kp].map { StatPoint(day: x.day, value: f($0)) } } }
            if sides.contains(.watch) { s.watch = pts(store.watchDays) }
            if sides.contains(.whoop) { s.whoop = pts(store.whoopDays) }
            return s
        }
    }

    private static func nights(sides: Set<Source> = [.watch, .whoop], _ f: @escaping (SleepNight) -> Double?) -> @MainActor (LabStore) -> StatSeries {
        { store in
            var s = StatSeries()
            for n in store.sleeps where sides.contains(n.source) {
                guard let v = f(n) else { continue }
                let p = StatPoint(day: n.night.dayStart, value: v)
                if n.source == .watch { s.watch.append(p) } else { s.whoop.append(p) }
            }
            s.watch.sort { $0.day < $1.day }; s.whoop.sort { $0.day < $1.day }
            return s
        }
    }

    /// Sum of a workout value per day, per source.
    private static func workouts(sides: Set<Source> = [.watch, .whoop], _ f: @escaping (WorkoutRec) -> Double?) -> @MainActor (LabStore) -> StatSeries {
        { store in
            var w: [Date: Double] = [:], h: [Date: Double] = [:]
            for x in store.workouts where sides.contains(x.source) {
                guard let v = f(x) else { continue }
                if x.source == .watch { w[x.start.dayStart, default: 0] += v } else { h[x.start.dayStart, default: 0] += v }
            }
            func pts(_ d: [Date: Double]) -> [StatPoint] { d.map { StatPoint(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day } }
            return StatSeries(watch: pts(w), whoop: pts(h))
        }
    }

    /// A daily Health series on the Apple side plus WHOOP's single body measurement (dated by the last WHOOP sync).
    private static func body(_ kp: KeyPath<DayStat, Double?>, whoop: @escaping @MainActor () -> Double?, _ f: @escaping (Double) -> Double) -> @MainActor (LabStore) -> StatSeries {
        { store in
            var s = days(kp, f)(store)
            if s.whoop.isEmpty, let v = whoop() {
                s.whoop = [StatPoint(day: (WhoopAdapter.body.at ?? Date()).dayStart, value: f(v))]
            }
            return s
        }
    }

    // MARK: Catalogue

    /// Built on demand so unit preferences (lb/kg, °F/°C, mi/km) are current.
    static func defs() -> [StatDef] {
        let imp = Units.imperial, fahr = Units.fahrenheit
        let lb: (Double) -> Double = { imp ? $0 * 2.20462 : $0 }
        let dist: (Double) -> Double = { imp ? $0 * 0.621371 : $0 }
        let distU = imp ? "mi" : "km"
        let speed: (Double) -> Double = { imp ? $0 * 2.23694 : $0 * 3.6 }   // m/s → mph / km/h
        let speedU = imp ? "mph" : "km/h"
        let short: (Double) -> Double = { imp ? $0 * 39.3701 : $0 * 100 }   // m → in / cm
        let shortU = imp ? "in" : "cm"
        let tempD: (Double) -> Double = { fahr ? $0 * 1.8 : $0 }
        let tempA: (Double) -> Double = { fahr ? $0 * 1.8 + 32 : $0 }
        let tU = fahr ? "°F" : "°C"
        let hours: (Double) -> Double = { $0 / 60 }

        let zoneNames = ["Zone 1 · 50–60% max HR", "Zone 2 · 60–70%", "Zone 3 · 70–80%", "Zone 4 · 80–90%", "Zone 5 · 90–100%"]
        let zones: [StatDef] = (1...5).map { z in
            StatDef(id: "zone\(z)", section: .heart, title: zoneNames[z - 1], unit: "min",
                    note: "Minutes in heart-rate zone \(z) across the day's WHOOP workouts.",
                    read: workouts(sides: [.whoop]) { w in w.zonesMin.flatMap { $0.count > z ? $0[z] : nil } })
        }

        let recovery: [StatDef] = [
            StatDef(id: "recovery", section: .recovery, title: "WHOOP recovery", unit: "%", preferWhoop: true,
                    note: "WHOOP's 0–100 recovery from HRV, resting HR, sleep and breathing.", read: days(\.recovery, sides: [.whoop])),
            StatDef(id: "readiness", section: .recovery, title: "Readiness (Watch)", unit: "score", appleBadge: "WATCH",
                    note: "Pulse Lab's own 1–99 score from Watch HRV and resting HR vs your baseline, plus sleep.", read: days(\.recovery, sides: [.watch])),
            StatDef(id: "hrv", section: .recovery, title: "Heart rate variability", unit: "ms", healthID: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
                    note: "Watch: SDNN from spot readings. WHOOP: RMSSD through the night.", read: days(\.hrv)),
            StatDef(id: "rhr", section: .recovery, title: "Resting heart rate", unit: "bpm", healthID: "HKQuantityTypeIdentifierRestingHeartRate",
                    note: "Lowest steady heart rate of the day.", read: days(\.rhr)),
            StatDef(id: "spo2", section: .recovery, title: "Blood oxygen", unit: "%", decimals: 1, healthID: "HKQuantityTypeIdentifierOxygenSaturation",
                    note: "Oxygen saturation, mostly measured asleep.", read: days(\.spo2)),
            StatDef(id: "tempDev", section: .recovery, title: "Temperature vs baseline", unit: tU, decimals: 2, healthID: "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
                    note: "Wrist (Watch) or skin (WHOOP) temperature, as change from your own average.", read: days(\.tempDev, tempD)),
            StatDef(id: "skinTemp", section: .recovery, title: "Skin temperature", unit: tU, decimals: 1, preferWhoop: true,
                    note: "WHOOP's absolute skin temperature during sleep.", read: days(\.skinTempC, sides: [.whoop], tempA)),
            StatDef(id: "resp", section: .recovery, title: "Respiratory rate", unit: "br/min", decimals: 1, healthID: "HKQuantityTypeIdentifierRespiratoryRate",
                    note: "Breaths per minute while asleep.", read: days(\.resp)),
        ]
        let sleep: [StatDef] = [
            StatDef(id: "asleep", section: .sleep, title: "Time asleep", unit: "h", decimals: 1,
                    note: "Light + deep + REM, each minute counted once even when several apps wrote it, main sleep only (naps left out), credited to the morning you woke up.", read: nights { $0.asleepMin > 0 ? $0.asleepMin / 60 : nil }),
            StatDef(id: "inBed", section: .sleep, title: "Time in bed", unit: "h", decimals: 1,
                    note: "Apple Watch: asleep + awake through the night as the Watch measured it (the iPhone's Sleep-schedule time is left out). WHOOP: its own in-bed time.",
                    read: nights { n in let b = max(n.inBedMin, n.asleepMin + n.awakeMin); return b > 0 ? b / 60 : nil }),
            StatDef(id: "deep", section: .sleep, title: "Deep sleep", unit: "min", note: "Slow-wave sleep.", read: nights { $0.deepMin > 0 ? $0.deepMin : nil }),
            StatDef(id: "rem", section: .sleep, title: "REM sleep", unit: "min", note: "Dream sleep.", read: nights { $0.remMin > 0 ? $0.remMin : nil }),
            StatDef(id: "light", section: .sleep, title: "Light sleep", unit: "min", note: "Core / light sleep (includes unspecified asleep time).",
                    read: nights { n in let v = n.minutes(.core); return v > 0 ? v : nil }),
            StatDef(id: "awake", section: .sleep, title: "Awake in the night", unit: "min", note: "Time awake between falling asleep and getting up.",
                    read: nights { $0.asleepMin > 0 ? $0.awakeMin : nil }),
            StatDef(id: "efficiency", section: .sleep, title: "Sleep efficiency", unit: "%",
                    note: "Asleep ÷ time in bed. WHOOP's own figure is used for WHOOP nights.",
                    read: nights { $0.whoopEfficiency ?? $0.efficiency }),
            StatDef(id: "performance", section: .sleep, title: "Sleep performance", unit: "%", preferWhoop: true,
                    note: "WHOOP: sleep you got vs sleep you needed.", read: nights(sides: [.whoop]) { $0.performance }),
            StatDef(id: "consistency", section: .sleep, title: "Sleep consistency", unit: "%", preferWhoop: true,
                    note: "WHOOP: how similar your bed and wake times are day to day.", read: nights(sides: [.whoop]) { $0.consistency }),
            StatDef(id: "need", section: .sleep, title: "Sleep need", unit: "h", decimals: 1, preferWhoop: true,
                    note: "WHOOP: baseline + sleep debt + recent strain − naps.", read: nights(sides: [.whoop]) { $0.needMin.map(hours) }),
            StatDef(id: "cycles", section: .sleep, title: "Sleep cycles", unit: "cycles", preferWhoop: true,
                    note: "WHOOP: complete sleep cycles in the night.", read: nights(sides: [.whoop]) { $0.cycles }),
            StatDef(id: "disturbances", section: .sleep, title: "Disturbances", unit: "count", preferWhoop: true,
                    note: "WHOOP: times you were disturbed in the night.", read: nights(sides: [.whoop]) { $0.disturbances }),
            StatDef(id: "breathingDist", section: .sleep, title: "Breathing disturbances", unit: "/h", decimals: 1, healthID: "HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances",
                    note: "Watch: interruptions to normal breathing per hour asleep.", read: days(\.breathingDisturbances, sides: [.watch])),
        ]
        let strain: [StatDef] = [
            StatDef(id: "strain", section: .strain, title: "WHOOP strain", unit: "/ 21", decimals: 1, preferWhoop: true,
                    note: "WHOOP day strain, 0–21.", read: days(\.strain, sides: [.whoop])),
            StatDef(id: "totalKcal", section: .strain, title: "Total calories", unit: "kcal", appleBadge: "WATCH",
                    note: "Active + resting. WHOOP gives one total for the day.", read: days(\.totalKcal)),
            StatDef(id: "activeKcal", section: .strain, title: "Active energy", unit: "kcal", healthID: "HKQuantityTypeIdentifierActiveEnergyBurned",
                    note: "Calories burned above resting.", read: days(\.activeKcal, sides: [.watch])),
            StatDef(id: "basalKcal", section: .strain, title: "Resting energy", unit: "kcal", healthID: "HKQuantityTypeIdentifierBasalEnergyBurned",
                    note: "Calories your body burns at rest.", read: days(\.basalKcal, sides: [.watch])),
            StatDef(id: "steps", section: .strain, title: "Steps", unit: "steps", healthID: "HKQuantityTypeIdentifierStepCount",
                    note: "Watch and iPhone steps, de-duplicated by Health. WHOOP steps when typed in by hand.", read: days(\.steps)),
            StatDef(id: "distance", section: .strain, title: "Walking + running distance", unit: distU, decimals: 2, healthID: "HKQuantityTypeIdentifierDistanceWalkingRunning",
                    note: "Distance on foot.", read: days(\.distanceKm, sides: [.watch], dist)),
            StatDef(id: "flights", section: .strain, title: "Flights climbed", unit: "floors", healthID: "HKQuantityTypeIdentifierFlightsClimbed",
                    note: "Roughly 3 m / 10 ft of climbing each.", read: days(\.flights, sides: [.watch])),
            StatDef(id: "exercise", section: .strain, title: "Exercise minutes", unit: "min", healthID: "HKQuantityTypeIdentifierAppleExerciseTime",
                    note: "Brisk-or-harder minutes (the green ring).", read: days(\.exerciseMin, sides: [.watch])),
            StatDef(id: "standMin", section: .strain, title: "Stand minutes", unit: "min", healthID: "HKQuantityTypeIdentifierAppleStandTime",
                    note: "Minutes spent standing and moving.", read: days(\.standMin, sides: [.watch])),
            StatDef(id: "standHours", section: .strain, title: "Stand hours", unit: "h",
                    note: "Hours with at least a minute of standing (the blue ring).", read: days(\.standHours, sides: [.watch])),
            StatDef(id: "cycling", section: .strain, title: "Cycling distance", unit: distU, decimals: 2, healthID: "HKQuantityTypeIdentifierDistanceCycling",
                    note: "Distance ridden.", read: days(\.cyclingKm, sides: [.watch], dist)),
            StatDef(id: "daylight", section: .strain, title: "Time in daylight", unit: "min", healthID: "HKQuantityTypeIdentifierTimeInDaylight",
                    note: "Minutes outdoors in daylight.", read: days(\.daylightMin, sides: [.watch])),
            StatDef(id: "workoutMin", section: .strain, title: "Workout time", unit: "min",
                    note: "Total minutes of logged workouts.", read: workouts { $0.minutes }),
            StatDef(id: "workoutStrain", section: .strain, title: "Workout strain", unit: "/ 21", decimals: 1, preferWhoop: true,
                    note: "WHOOP strain from the day's workouts (highest workout).",
                    read: { store in
                        var h: [Date: Double] = [:]
                        for w in store.workouts where w.source == .whoop { if let s = w.strain { h[w.start.dayStart] = max(h[w.start.dayStart] ?? 0, s) } }
                        return StatSeries(whoop: h.map { StatPoint(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day })
                    }),
        ]
        let heart: [StatDef] = [
            StatDef(id: "avgHR", section: .heart, title: "Average heart rate", unit: "bpm", healthID: "HKQuantityTypeIdentifierHeartRate",
                    note: "Average over the day (WHOOP: over the cycle).", read: days(\.avgHR)),
            StatDef(id: "maxHR", section: .heart, title: "Peak heart rate", unit: "bpm", preferWhoop: true,
                    note: "WHOOP: highest heart rate in the cycle.", read: days(\.maxHR, sides: [.whoop])),
            StatDef(id: "walkHR", section: .heart, title: "Walking heart rate", unit: "bpm", healthID: "HKQuantityTypeIdentifierWalkingHeartRateAverage",
                    note: "Average heart rate while walking.", read: days(\.walkHR, sides: [.watch])),
            StatDef(id: "hrRecovery", section: .heart, title: "Heart rate recovery", unit: "bpm", healthID: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
                    note: "How far heart rate drops in the minute after a workout.", read: days(\.hrRecovery, sides: [.watch])),
            StatDef(id: "vo2", section: .heart, title: "VO₂ max", unit: "ml/kg/min", decimals: 1, healthID: "HKQuantityTypeIdentifierVO2Max",
                    note: "Cardio fitness estimate.", read: days(\.vo2, sides: [.watch])),
            StatDef(id: "workoutHR", section: .heart, title: "Workout avg heart rate", unit: "bpm",
                    note: "Average heart rate across the day's workouts.",
                    read: { store in
                        var w: [Date: [Double]] = [:], h: [Date: [Double]] = [:]
                        for x in store.workouts { guard let v = x.avgHR else { continue }
                            if x.source == .watch { w[x.start.dayStart, default: []].append(v) } else { h[x.start.dayStart, default: []].append(v) } }
                        func pts(_ d: [Date: [Double]]) -> [StatPoint] { d.compactMap { k, v in Stats.mean(v).map { StatPoint(day: k, value: $0) } }.sorted { $0.day < $1.day } }
                        return StatSeries(watch: pts(w), whoop: pts(h))
                    }),
        ]
        let bodyDefs: [StatDef] = [
            StatDef(id: "weight", section: .body, title: "Weight", unit: imp ? "lb" : "kg", decimals: 1, healthID: "HKQuantityTypeIdentifierBodyMass", appleBadge: "HEALTH",
                    note: "From a scale, the Health app or WHOOP's profile.", read: body(\.weightKg, whoop: { WhoopAdapter.body.weightKg }, lb)),
            StatDef(id: "bodyFat", section: .body, title: "Body fat", unit: "%", decimals: 1, healthID: "HKQuantityTypeIdentifierBodyFatPercentage", appleBadge: "HEALTH",
                    note: "From a smart scale or entered in Health.", read: days(\.bodyFat, sides: [.watch])),
            StatDef(id: "lean", section: .body, title: "Lean body mass", unit: imp ? "lb" : "kg", decimals: 1, healthID: "HKQuantityTypeIdentifierLeanBodyMass", appleBadge: "HEALTH",
                    note: "Everything that isn't fat.", read: days(\.leanMassKg, sides: [.watch], lb)),
            StatDef(id: "bmi", section: .body, title: "BMI", unit: "kg/m²", decimals: 1, healthID: "HKQuantityTypeIdentifierBodyMassIndex", appleBadge: "HEALTH",
                    note: "Body mass index.", read: days(\.bmi, sides: [.watch])),
            StatDef(id: "height", section: .body, title: "Height", unit: shortU, decimals: 1, healthID: "HKQuantityTypeIdentifierHeight", appleBadge: "HEALTH",
                    note: "From Health or WHOOP's profile.", read: body(\.heightM, whoop: { WhoopAdapter.body.heightM }, short)),
        ]
        let mobility: [StatDef] = [
            StatDef(id: "walkSpeed", section: .mobility, title: "Walking speed", unit: speedU, decimals: 1, healthID: "HKQuantityTypeIdentifierWalkingSpeed", appleBadge: "IPHONE",
                    note: "Measured by the iPhone in your pocket.", read: days(\.walkSpeed, sides: [.watch], speed)),
            StatDef(id: "stepLength", section: .mobility, title: "Step length", unit: shortU, decimals: 1, healthID: "HKQuantityTypeIdentifierWalkingStepLength", appleBadge: "IPHONE",
                    note: "Average walking step.", read: days(\.walkStepM, sides: [.watch], short)),
            StatDef(id: "asymmetry", section: .mobility, title: "Walking asymmetry", unit: "%", decimals: 1, healthID: "HKQuantityTypeIdentifierWalkingAsymmetryPercentage", appleBadge: "IPHONE",
                    note: "How uneven left and right steps are. Lower is steadier.", read: days(\.walkAsymmetry, sides: [.watch])),
            StatDef(id: "doubleSupport", section: .mobility, title: "Double support time", unit: "%", decimals: 1, healthID: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", appleBadge: "IPHONE",
                    note: "Share of each step with both feet on the ground.", read: days(\.doubleSupport, sides: [.watch])),
            StatDef(id: "effort", section: .mobility, title: "Physical effort", unit: "MET", decimals: 1, healthID: "HKQuantityTypeIdentifierPhysicalEffort",
                    note: "Average effort level (kcal per kg per hour).", read: days(\.physicalEffort, sides: [.watch])),
            StatDef(id: "runSpeed", section: .mobility, title: "Running speed", unit: speedU, decimals: 1, healthID: "HKQuantityTypeIdentifierRunningSpeed",
                    note: "Average running speed.", read: days(\.runSpeed, sides: [.watch], speed)),
            StatDef(id: "runPower", section: .mobility, title: "Running power", unit: "W", healthID: "HKQuantityTypeIdentifierRunningPower",
                    note: "Average running power.", read: days(\.runPower, sides: [.watch])),
            StatDef(id: "stride", section: .mobility, title: "Running stride length", unit: shortU, decimals: 1, healthID: "HKQuantityTypeIdentifierRunningStrideLength",
                    note: "Average running stride.", read: days(\.strideM, sides: [.watch], short)),
        ]
        let nutrition: [StatDef] = [
            StatDef(id: "food", section: .nutrition, title: "Food energy", unit: "kcal", healthID: "HKQuantityTypeIdentifierDietaryEnergyConsumed", appleBadge: "HEALTH",
                    note: "Calories logged by a food app.", read: days(\.dietKcal, sides: [.watch])),
            StatDef(id: "water", section: .nutrition, title: "Water", unit: imp ? "fl oz" : "L", decimals: imp ? 0 : 1, healthID: "HKQuantityTypeIdentifierDietaryWater", appleBadge: "HEALTH",
                    note: "Water logged in Health.", read: days(\.waterL, sides: [.watch]) { imp ? $0 * 33.814 : $0 }),
            StatDef(id: "mindful", section: .nutrition, title: "Mindful minutes", unit: "min", appleBadge: "WATCH",
                    note: "Breathe / Reflect sessions and meditation apps.", read: days(\.mindfulMin, sides: [.watch])),
            StatDef(id: "noise", section: .nutrition, title: "Environmental noise", unit: "dB", healthID: "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
                    note: "Average sound level around you.", read: days(\.audioDb, sides: [.watch])),
        ]
        return recovery + sleep + strain + heart + zones + bodyDefs + mobility + nutrition
    }

    /// One metric by id: the catalogue, plus "recoveryVs" (WHOOP recovery and Watch readiness on one chart).
    static func def(_ id: String) -> StatDef? {
        if id == "recoveryVs" {
            return StatDef(id: "recoveryVs", section: .recovery, title: "Recovery vs readiness", unit: "score",
                           note: "WHOOP recovery (0–100%) and Pulse Lab's Watch readiness (1–99) side by side.", read: days(\.recovery))
        }
        return defs().first { $0.id == id }
    }
}

extension StatDef {
    /// The side whose newest value is most recent (ties go to the metric's preferred side).
    func primary(_ s: StatSeries) -> Source? {
        switch (s.watch.last, s.whoop.last) {
        case (nil, nil): return nil
        case (_, nil): return .watch
        case (nil, _): return .whoop
        case let (w?, h?):
            if w.day == h.day { return preferWhoop ? .whoop : .watch }
            return w.day > h.day ? .watch : .whoop
        }
    }
}

extension LabStore {
    /// Where a side of a metric came from: "WHOOP", "WHOOP · MANUAL" (newest value typed in), or the
    /// Health device / app ("WATCH", "IPHONE", an app name…).
    func badge(_ def: StatDef, _ s: Source, series: StatSeries) -> String {
        if s == .whoop {
            if let f = ManualField.forStat(def.id), let d = series.whoop.last?.day, isManual(d, f) { return "WHOOP · MANUAL" }
            return "WHOOP"
        }
        if let id = def.healthID, let o = appleOrigins[id] { return o }
        return def.appleBadge
    }

    /// Days in a metric's WHOOP history that were typed in by hand.
    func manualDays(_ def: StatDef, series: StatSeries) -> Int {
        guard let f = ManualField.forStat(def.id) else { return 0 }
        return series.whoop.filter { isManual($0.day, f) }.count
    }
}
