import Foundation
import HealthKit

/// Pulls everything Pulse Lab shows from Apple Health, split by where each sample came from:
/// the Apple Watch, or WHOOP (which also writes some of its data into Health).
final class HealthPull: @unchecked Sendable {
    static let shared = HealthPull()
    let store = HKHealthStore()

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Quantity types we read, with how to aggregate a day and the unit we keep.
    struct QSpec {
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
        let cumulative: Bool
        let key: WritableKeyPath<DayStat, Double?>
        var scale: Double = 1
    }

    static let specs: [QSpec] = {
        let s: [QSpec] = [
            QSpec(id: .restingHeartRate, unit: .count().unitDivided(by: .minute()), cumulative: false, key: \.rhr),
            QSpec(id: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), cumulative: false, key: \.hrv),
            QSpec(id: .heartRate, unit: .count().unitDivided(by: .minute()), cumulative: false, key: \.avgHR),
            QSpec(id: .walkingHeartRateAverage, unit: .count().unitDivided(by: .minute()), cumulative: false, key: \.walkHR),
            QSpec(id: .respiratoryRate, unit: .count().unitDivided(by: .minute()), cumulative: false, key: \.resp),
            QSpec(id: .oxygenSaturation, unit: .percent(), cumulative: false, key: \.spo2, scale: 100),
            // Absolute wrist temperature; LabStore turns it into a deviation from your average.
            QSpec(id: .appleSleepingWristTemperature, unit: .degreeCelsius(), cumulative: false, key: \.tempDev),
            QSpec(id: .vo2Max, unit: HKUnit(from: "ml/kg*min"), cumulative: false, key: \.vo2),
            QSpec(id: .bodyMass, unit: .gramUnit(with: .kilo), cumulative: false, key: \.weightKg),
            QSpec(id: .bodyFatPercentage, unit: .percent(), cumulative: false, key: \.bodyFat, scale: 100),
            QSpec(id: .heartRateRecoveryOneMinute, unit: .count().unitDivided(by: .minute()), cumulative: false, key: \.hrRecovery),
            QSpec(id: .environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel(), cumulative: false, key: \.audioDb),
            QSpec(id: .runningSpeed, unit: .meter().unitDivided(by: .second()), cumulative: false, key: \.runSpeed),
            QSpec(id: .runningPower, unit: .watt(), cumulative: false, key: \.runPower),
            QSpec(id: .runningStrideLength, unit: .meter(), cumulative: false, key: \.strideM),
            QSpec(id: .stepCount, unit: .count(), cumulative: true, key: \.steps),
            QSpec(id: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), cumulative: true, key: \.distanceKm),
            QSpec(id: .flightsClimbed, unit: .count(), cumulative: true, key: \.flights),
            QSpec(id: .activeEnergyBurned, unit: .kilocalorie(), cumulative: true, key: \.activeKcal),
            QSpec(id: .basalEnergyBurned, unit: .kilocalorie(), cumulative: true, key: \.basalKcal),
            QSpec(id: .appleExerciseTime, unit: .minute(), cumulative: true, key: \.exerciseMin),
            QSpec(id: .appleStandTime, unit: .minute(), cumulative: true, key: \.standMin),
            QSpec(id: .timeInDaylight, unit: .minute(), cumulative: true, key: \.daylightMin),
        ]
        return s
    }()

    var readTypes: Set<HKObjectType> {
        var t = Set<HKObjectType>(Self.specs.compactMap { HKQuantityType.quantityType(forIdentifier: $0.id) })
        t.insert(HKObjectType.workoutType())
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sleep) }
        if let mind = HKCategoryType.categoryType(forIdentifier: .mindfulSession) { t.insert(mind) }
        return t
    }

    func requestAccess() async -> Bool {
        guard Self.available else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: "healthAsked")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Source tagging

    /// WHOOP samples carry WHOOP's bundle id / name. Everything from an Apple Watch says "Watch"
    /// in the device or source name. iPhone-only samples are neither.
    enum Origin { case watch, whoop, other }
    static func origin(_ src: HKSource) -> Origin {
        let id = src.bundleIdentifier.lowercased(), name = src.name.lowercased()
        if id.contains("whoop") || name.contains("whoop") { return .whoop }
        if name.contains("watch") { return .watch }
        return .other
    }
    static func origin(_ sample: HKSample) -> Origin {
        let o = origin(sample.sourceRevision.source)
        if o != .other { return o }
        if let model = sample.device?.model?.lowercased(), model.contains("watch") { return .watch }
        if let pt = sample.sourceRevision.productType?.lowercased(), pt.contains("watch") { return .watch }
        return .other
    }

    // MARK: - Full pull

    struct Result {
        var watch: [DayStat] = []
        var whoop: [DayStat] = []
        var sleeps: [SleepNight] = []
        var hypnogram: [HypnoSegment] = []
        var workouts: [WorkoutRec] = []
    }

    func pull(days: Int = 90) async -> Result {
        guard Self.available else { return Result() }
        let start = Date().dayStart.adding(days: -(days - 1))
        var watch: [Date: DayStat] = [:], whoop: [Date: DayStat] = [:]

        await withTaskGroup(of: (Int, [Date: [Double?]]).self) { group in
            for i in Self.specs.indices {
                group.addTask { (i, await self.daily(Self.specs[i], from: start)) }
            }
            for await (i, values) in group {
                let spec = Self.specs[i]
                for (day, pair) in values {
                    let v = (watch: pair[0], whoop: pair[1])
                    if let w = v.watch { watch[day, default: DayStat(day: day)][keyPath: spec.key] = w * spec.scale }
                    if let w = v.whoop { whoop[day, default: DayStat(day: day)][keyPath: spec.key] = w * spec.scale }
                }
            }
        }

        let mindful = await mindfulMinutes(from: start)
        for (day, m) in mindful { watch[day, default: DayStat(day: day)].mindfulMin = m }

        let (sleeps, hypno) = await sleepNights(from: start.adding(days: -1))
        let workouts = await workouts(from: start)
        return Result(watch: watch.values.sorted { $0.day < $1.day },
                      whoop: whoop.values.sorted { $0.day < $1.day },
                      sleeps: sleeps, hypnogram: hypno, workouts: workouts)
    }

    /// Per-day value for each origin. Cumulative metrics: the Watch side falls back to Health's merged,
    /// de-duplicated total when the day has no Watch-specific samples (e.g. phone-only steps).
    private func daily(_ spec: QSpec, from start: Date) async -> [Date: [Double?]] {
        guard let type = HKQuantityType.quantityType(forIdentifier: spec.id) else { return [:] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let opts: HKStatisticsOptions = spec.cumulative ? [.cumulativeSum, .separateBySource] : [.discreteAverage, .separateBySource]
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred, options: opts,
                                                anchorDate: start, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, collection, _ in
                var out: [Date: [Double?]] = [:]
                collection?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    var w: [Double] = [], wh: [Double] = []
                    for src in stat.sources ?? [] {
                        let qty = spec.cumulative ? stat.sumQuantity(for: src) : stat.averageQuantity(for: src)
                        guard let v = qty?.doubleValue(for: spec.unit) else { continue }
                        switch Self.origin(src) {
                        case .whoop: wh.append(v)
                        case .watch: w.append(v)
                        case .other: break
                        }
                    }
                    var watchV: Double? = w.isEmpty ? nil : (spec.cumulative ? w.reduce(0, +) : w.reduce(0, +) / Double(w.count))
                    let whoopV: Double? = wh.isEmpty ? nil : (spec.cumulative ? wh.reduce(0, +) : wh.reduce(0, +) / Double(wh.count))
                    if watchV == nil, spec.cumulative, let merged = stat.sumQuantity()?.doubleValue(for: spec.unit) {
                        watchV = max(0, merged - (whoopV ?? 0))
                        if watchV == 0 { watchV = nil }
                    }
                    if watchV != nil || whoopV != nil { out[stat.startDate.dayStart] = [watchV, whoopV] }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func samples(_ type: HKSampleType, from start: Date) async -> [HKSample] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
    }

    private func mindfulMinutes(from start: Date) async -> [Date: Double] {
        guard let t = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return [:] }
        var out: [Date: Double] = [:]
        for s in await samples(t, from: start) { out[s.startDate.dayStart, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60 }
        return out
    }

    /// Nights are attributed to the day you woke up: anything ending after 6 pm counts toward tomorrow.
    static func nightKey(_ end: Date) -> Date {
        let hour = Calendar.current.component(.hour, from: end)
        return hour >= 18 ? end.dayStart.adding(days: 1) : end.dayStart
    }

    private func sleepNights(from start: Date) async -> ([SleepNight], [HypnoSegment]) {
        guard let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return ([], []) }
        let all = await samples(t, from: start).compactMap { $0 as? HKCategorySample }
        var nights: [String: SleepNight] = [:]
        for s in all {
            let o = Self.origin(s)
            guard o != .other else { continue }
            let src: Source = o == .whoop ? .whoop : .watch
            let key = Self.nightKey(s.endDate)
            let id = "\(src.rawValue)-\(key.timeIntervalSince1970)"
            var n = nights[id] ?? SleepNight(night: key, source: src)
            let m = s.endDate.timeIntervalSince(s.startDate) / 60
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .inBed: n.inBedMin += m
            case .awake: n.awakeMin += m
            case .asleepCore: n.coreMin += m
            case .asleepDeep: n.deepMin += m
            case .asleepREM: n.remMin += m
            case .asleepUnspecified: n.unspecifiedMin += m
            default: break
            }
            n.start = min(n.start ?? s.startDate, s.startDate)
            n.end = max(n.end ?? s.endDate, s.endDate)
            nights[id] = n
        }
        // Hypnogram: the latest Watch night, stage by stage.
        var hypno: [HypnoSegment] = []
        if let last = nights.values.filter({ $0.source == .watch && $0.asleepMin > 0 }).max(by: { $0.night < $1.night }),
           let s0 = last.start, let e0 = last.end {
            for s in all where Self.origin(s) == .watch && s.startDate >= s0 && s.endDate <= e0 {
                let stage: SleepStage?
                switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                case .awake: stage = .awake
                case .asleepREM: stage = .rem
                case .asleepCore, .asleepUnspecified: stage = .core
                case .asleepDeep: stage = .deep
                default: stage = nil
                }
                if let stage { hypno.append(HypnoSegment(start: s.startDate, end: s.endDate, stage: stage)) }
            }
        }
        return (nights.values.filter { $0.asleepMin > 0 || $0.inBedMin > 0 }.sorted { $0.night < $1.night }, hypno)
    }

    private func workouts(from start: Date) async -> [WorkoutRec] {
        let ws = await samples(HKObjectType.workoutType(), from: start).compactMap { $0 as? HKWorkout }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return ws.compactMap { w in
            let o = Self.origin(w)
            let src: Source = o == .whoop ? .whoop : .watch
            if o == .other && w.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple") == false { return nil }
            let hrType = HKQuantityType(.heartRate)
            let kcalType = HKQuantityType(.activeEnergyBurned)
            let distType = HKQuantityType(.distanceWalkingRunning)
            let hr = w.statistics(for: hrType)
            return WorkoutRec(id: w.uuid.uuidString, source: src,
                              name: Self.activityName(w.workoutActivityType),
                              symbol: Self.activitySymbol(w.workoutActivityType),
                              start: w.startDate, end: w.endDate,
                              kcal: w.statistics(for: kcalType)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                              avgHR: hr?.averageQuantity()?.doubleValue(for: bpm),
                              maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm),
                              strain: nil,
                              distanceKm: w.statistics(for: distType)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)))
        }
    }

    static func activityName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .swimming: "Swim"
        case .yoga: "Yoga"
        case .hiking: "Hike"
        case .basketball: "Basketball"
        case .soccer: "Soccer"
        case .boxing, .kickboxing: "Boxing"
        case .elliptical: "Elliptical"
        case .rowing: "Row"
        case .stairClimbing, .stairs: "Stairs"
        case .coreTraining: "Core"
        case .crossTraining: "Cross training"
        case .golf: "Golf"
        case .tennis, .pickleball: "Racquet"
        case .dance, .socialDance: "Dance"
        case .mindAndBody, .flexibility, .cooldown: "Mobility"
        default: "Workout"
        }
    }

    static func activitySymbol(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell.fill"
        case .highIntensityIntervalTraining: "bolt.heart.fill"
        case .swimming: "figure.pool.swim"
        case .yoga, .mindAndBody, .flexibility: "figure.yoga"
        case .hiking: "figure.hiking"
        case .basketball: "figure.basketball"
        case .soccer: "figure.soccer"
        case .boxing, .kickboxing: "figure.boxing"
        case .rowing: "figure.rower"
        case .golf: "figure.golf"
        default: "figure.mixed.cardio"
        }
    }
}
