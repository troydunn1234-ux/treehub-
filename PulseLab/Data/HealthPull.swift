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
            QSpec(id: .distanceCycling, unit: .meterUnit(with: .kilo), cumulative: true, key: \.cyclingKm),
            QSpec(id: .walkingSpeed, unit: .meter().unitDivided(by: .second()), cumulative: false, key: \.walkSpeed),
            QSpec(id: .walkingStepLength, unit: .meter(), cumulative: false, key: \.walkStepM),
            QSpec(id: .walkingAsymmetryPercentage, unit: .percent(), cumulative: false, key: \.walkAsymmetry, scale: 100),
            QSpec(id: .walkingDoubleSupportPercentage, unit: .percent(), cumulative: false, key: \.doubleSupport, scale: 100),
            QSpec(id: .physicalEffort, unit: .kilocalorie().unitDivided(by: .hour().unitMultiplied(by: .gramUnit(with: .kilo))), cumulative: false, key: \.physicalEffort),
            QSpec(id: .leanBodyMass, unit: .gramUnit(with: .kilo), cumulative: false, key: \.leanMassKg),
            QSpec(id: .bodyMassIndex, unit: .count(), cumulative: false, key: \.bmi),
            QSpec(id: .height, unit: .meter(), cumulative: false, key: \.heightM),
            QSpec(id: .dietaryEnergyConsumed, unit: .kilocalorie(), cumulative: true, key: \.dietKcal),
            QSpec(id: .dietaryWater, unit: .liter(), cumulative: true, key: \.waterL),
        ]
        var all = s
        if #available(iOS 18.0, *) {
            all.append(QSpec(id: .appleSleepingBreathingDisturbances, unit: .count(), cumulative: false, key: \.breathingDisturbances))
        }
        return all
    }()

    /// Metrics the Watch doesn't measure itself (scales, food apps, the Health app): when no Watch sample
    /// exists for a day, the Apple side uses whatever else is in Health instead of showing a gap.
    static let fallbackToAnySource: Set<HKQuantityTypeIdentifier> = [
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .height, .vo2Max, .oxygenSaturation,
        .respiratoryRate, .walkingSpeed, .walkingStepLength, .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage,
        .walkingHeartRateAverage, .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
    ]

    var readTypes: Set<HKObjectType> {
        var t = Set<HKObjectType>(Self.specs.compactMap { HKQuantityType.quantityType(forIdentifier: $0.id) })
        t.insert(HKObjectType.workoutType())
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sleep) }
        if let mind = HKCategoryType.categoryType(forIdentifier: .mindfulSession) { t.insert(mind) }
        if let stand = HKCategoryType.categoryType(forIdentifier: .appleStandHour) { t.insert(stand) }
        return t
    }

    /// Every sample type we watch for new data (observer queries + background delivery).
    var sampleTypes: [HKSampleType] { readTypes.compactMap { $0 as? HKSampleType } }

    /// True when Health has types we haven't asked about yet (a newer Pulse Lab reads more than before).
    func needsAuthorizationPrompt() async -> Bool {
        guard Self.available else { return false }
        return await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                cont.resume(returning: status == .shouldRequest)
            }
        }
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
        // Apple Watch samples come from a per-device source "com.apple.health.<UUID>" — the user may have
        // renamed the watch, so don't rely on the name alone. The iPhone's own source is "com.apple.health".
        if id.hasPrefix("com.apple.health.") || name.contains("watch") { return .watch }
        return .other
    }
    /// Short badge text for a non-Watch, non-WHOOP source: "IPHONE" for the phone / Health app, else the app's name.
    static func originLabel(_ src: HKSource) -> String {
        if src.bundleIdentifier.lowercased().hasPrefix("com.apple") { return "IPHONE" }
        let n = src.name.uppercased()
        return n.count > 14 ? String(n.prefix(13)) + "…" : n
    }
    /// Apple's own iPhone writers (Sleep schedule "in bed", Health app entries).
    static func isAppleOther(_ sample: HKSample) -> Bool {
        origin(sample) == .other && sample.sourceRevision.source.bundleIdentifier.lowercased().hasPrefix("com.apple")
    }
    static func origin(_ sample: HKSample) -> Origin {
        let o = origin(sample.sourceRevision.source)
        if o != .other { return o }
        if let model = sample.device?.model?.lowercased(), model.contains("watch") { return .watch }
        if let pt = sample.sourceRevision.productType?.lowercased(), pt.contains("watch") { return .watch }
        return .other
    }

    // MARK: - Full pull

    struct Result: Codable {
        var watch: [DayStat] = []
        var whoop: [DayStat] = []
        var sleeps: [SleepNight] = []
        var hypnogram: [HypnoSegment] = []
        var workouts: [WorkoutRec] = []
        /// Steps per day per device ("iPhone", "Apple Watch Ultra 3"…), before de-duplication.
        var stepsByDevice: [Date: [String: Double]] = [:]
        /// Newest sample Health has from an Apple Watch / from WHOOP (for the Sources screen).
        var lastWatchSample: Date?
        var lastWhoopSample: Date?
        var watchName: String?
        /// Where the newest Apple-side value of each quantity type came from ("WATCH", "IPHONE", "WATCH + IPHONE", an app name).
        var appleOrigins: [String: String]?
        /// Set when Health was locked (iPhone locked): the result is incomplete and must not replace the cache.
        var failed = false

        enum CodingKeys: String, CodingKey { case watch, whoop, sleeps, hypnogram, workouts, stepsByDevice, lastWatchSample, lastWhoopSample, watchName, appleOrigins }

        /// Replace everything from `cutoff` on with `newer` (a pull that started at `cutoff`), keep older history.
        func merged(with newer: Result, from cutoff: Date) -> Result {
            let c = cutoff.dayStart
            var out = Result()
            out.watch = (watch.filter { $0.day < c } + newer.watch.filter { $0.day >= c }).sorted { $0.day < $1.day }
            out.whoop = (whoop.filter { $0.day < c } + newer.whoop.filter { $0.day >= c }).sorted { $0.day < $1.day }
            out.sleeps = (sleeps.filter { $0.night < c } + newer.sleeps.filter { $0.night >= c }).sorted { $0.night < $1.night }
            out.hypnogram = newer.hypnogram.isEmpty ? hypnogram : newer.hypnogram
            let fresh = newer.workouts.filter { $0.start >= c }
            let freshIDs = Set(fresh.map(\.id))
            out.workouts = (workouts.filter { $0.start < c && !freshIDs.contains($0.id) } + fresh).sorted { $0.start < $1.start }
            out.stepsByDevice = stepsByDevice.filter { $0.key < c }.merging(newer.stepsByDevice.filter { $0.key >= c }) { _, n in n }
            out.lastWatchSample = [lastWatchSample, newer.lastWatchSample].compactMap { $0 }.max()
            out.lastWhoopSample = [lastWhoopSample, newer.lastWhoopSample].compactMap { $0 }.max()
            out.watchName = newer.watchName ?? watchName
            out.appleOrigins = (appleOrigins ?? [:]).merging(newer.appleOrigins ?? [:]) { _, n in n }
            return out
        }
    }

    /// Thread-safe flag for "some query failed".
    final class FailFlag: @unchecked Sendable {
        private let lock = NSLock(); private var v = false
        func set() { lock.lock(); v = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
    }

    func pull(days: Int = 90) async -> Result {
        await pull(from: Date().dayStart.adding(days: -(days - 1)))
    }

    /// Everything from `start` (a day start) to now. `progress` gets 0…1 as the queries finish.
    func pull(from start: Date, progress: (@Sendable (Double) -> Void)? = nil) async -> Result {
        guard Self.available else { return Result() }
        let failed = FailFlag()
        let start = start.dayStart
        var watch: [Date: DayStat] = [:], whoop: [Date: DayStat] = [:]
        let total = Double(Self.specs.count + 6)
        var done = 0.0
        func tick() { done += 1; progress?(min(1, done / total)) }

        var origins: [String: String] = [:]
        await withTaskGroup(of: (Int, [Date: [Double?]], String?).self) { group in
            for i in Self.specs.indices {
                group.addTask {
                    let (values, origin) = await self.daily(Self.specs[i], from: start, failed: failed)
                    return (i, values, origin)
                }
            }
            for await (i, values, origin) in group {
                tick()
                let spec = Self.specs[i]
                if let origin { origins[spec.id.rawValue] = origin }
                for (day, pair) in values {
                    let v = (watch: pair[0], whoop: pair[1])
                    if let w = v.watch { watch[day, default: DayStat(day: day)][keyPath: spec.key] = w * spec.scale }
                    if let w = v.whoop { whoop[day, default: DayStat(day: day)][keyPath: spec.key] = w * spec.scale }
                }
            }
        }

        let mindful = await mindfulMinutes(from: start, failed: failed); tick()
        for (day, m) in mindful { watch[day, default: DayStat(day: day)].mindfulMin = m }
        let stand = await standHours(from: start, failed: failed); tick()
        for (day, h) in stand { watch[day, default: DayStat(day: day)].standHours = h }
        let stepsByDevice = await stepsByDevice(from: start); tick()

        let (sleeps, hypno) = await sleepNights(from: start.adding(days: -1), failed: failed); tick()
        let workouts = await workouts(from: start, failed: failed); tick()
        let (lastWatch, lastWhoop, watchName) = await newestSamples(); tick()
        var r = Result(watch: watch.values.sorted { $0.day < $1.day },
                       whoop: whoop.values.sorted { $0.day < $1.day },
                       sleeps: sleeps, hypnogram: hypno, workouts: workouts, stepsByDevice: stepsByDevice)
        r.lastWatchSample = lastWatch
        r.lastWhoopSample = lastWhoop
        r.watchName = watchName
        r.appleOrigins = origins
        r.failed = failed.value
        return r
    }

    /// Newest heart-rate sample from an Apple Watch and from WHOOP (tells whether each is still writing to Health).
    private func newestSamples() async -> (Date?, Date?, String?) {
        guard let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return (nil, nil, nil) }
        let recent = await samples(hr, from: Date().adding(days: -30), limit: 400, newestFirst: true)
        let w = recent.first { Self.origin($0) == .watch }
        let wh = recent.first { Self.origin($0) == .whoop }
        let name = w?.device?.name ?? w?.sourceRevision.source.name
        return (w?.endDate, wh?.endDate, name)
    }

    /// Hours with a "stood" mark (the Watch's stand ring), per day.
    private func standHours(from start: Date, failed: FailFlag) async -> [Date: Double] {
        guard let t = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return [:] }
        var out: [Date: Double] = [:]
        for s in await samples(t, from: start, failed: failed) {
            guard let c = s as? HKCategorySample, c.value == HKCategoryValueAppleStandHour.stood.rawValue else { continue }
            out[c.startDate.dayStart, default: 0] += 1
        }
        return out
    }

    /// Steps counted by each device separately (the Watch and the iPhone both count; Health merges them for the total).
    private func stepsByDevice(from start: Date) async -> [Date: [String: Double]] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [:] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred, options: [.cumulativeSum, .separateBySource],
                                                anchorDate: start, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, collection, _ in
                var out: [Date: [String: Double]] = [:]
                collection?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    for src in stat.sources ?? [] {
                        guard Self.origin(src) != .whoop, let v = stat.sumQuantity(for: src)?.doubleValue(for: .count()), v > 0 else { continue }
                        let name = src.bundleIdentifier.lowercased() == "com.apple.health" ? "iPhone" : src.name
                        out[stat.startDate.dayStart, default: [:]][name, default: 0] += v
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Per-day value for each origin. Cumulative metrics: the Watch side falls back to Health's merged,
    /// de-duplicated total when the day has no Watch-specific samples (e.g. phone-only steps).
    private func daily(_ spec: QSpec, from start: Date, failed: FailFlag) async -> ([Date: [Double?]], String?) {
        guard let type = HKQuantityType.quantityType(forIdentifier: spec.id) else { return ([:], nil) }
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let opts: HKStatisticsOptions = spec.cumulative ? [.cumulativeSum, .separateBySource] : [.discreteAverage, .separateBySource]
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred, options: opts,
                                                anchorDate: start, intervalComponents: DateComponents(day: 1))
            let fallback = Self.fallbackToAnySource.contains(spec.id)
            q.initialResultsHandler = { _, collection, error in
                if (error as? HKError)?.code == .errorDatabaseInaccessible { failed.set() }
                var out: [Date: [Double?]] = [:]
                var newestOrigin: String?
                collection?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    var w: [Double] = [], wh: [Double] = [], other: [Double] = []
                    var otherNames: [String] = []
                    for src in stat.sources ?? [] {
                        let qty = spec.cumulative ? stat.sumQuantity(for: src) : stat.averageQuantity(for: src)
                        guard let v = qty?.doubleValue(for: spec.unit) else { continue }
                        switch Self.origin(src) {
                        case .whoop: wh.append(v)
                        case .watch: w.append(v)
                        case .other: other.append(v); otherNames.append(Self.originLabel(src))
                        }
                    }
                    let hadWatch = !w.isEmpty
                    if w.isEmpty && fallback && !other.isEmpty && !spec.cumulative { w = other }
                    var watchV: Double? = w.isEmpty ? nil : (spec.cumulative ? w.reduce(0, +) : w.reduce(0, +) / Double(w.count))
                    let whoopV: Double? = wh.isEmpty ? nil : (spec.cumulative ? wh.reduce(0, +) : wh.reduce(0, +) / Double(wh.count))
                    // Cumulative metrics (steps, energy, distance…): Health's merged total already removes the
                    // overlap between iPhone and Watch (and between two Watches). Summing per source double-counts,
                    // so the Apple side is always merged − WHOOP's share.
                    if spec.cumulative, let merged = stat.sumQuantity()?.doubleValue(for: spec.unit) {
                        let v = max(0, merged - (whoopV ?? 0))
                        watchV = v > 0 ? v : nil
                    }
                    if watchV != nil || whoopV != nil { out[stat.startDate.dayStart] = [watchV, whoopV] }
                    if watchV != nil {
                        // Which devices/apps the Apple-side number is built from (days run oldest → newest).
                        var names: [String] = hadWatch ? ["WATCH"] : []
                        if spec.cumulative || !hadWatch {
                            for n in otherNames where !names.contains(n) { names.append(n) }
                        }
                        if !names.isEmpty { newestOrigin = names.prefix(2).joined(separator: " + ") }
                    }
                }
                cont.resume(returning: (out, newestOrigin))
            }
            store.execute(q)
        }
    }

    private func samples(_ type: HKSampleType, from start: Date, failed: FailFlag? = nil) async -> [HKSample] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, error in
                if (error as? HKError)?.code == .errorDatabaseInaccessible { failed?.set() }
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
    }

    private func mindfulMinutes(from start: Date, failed: FailFlag) async -> [Date: Double] {
        guard let t = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return [:] }
        var out: [Date: Double] = [:]
        for s in await samples(t, from: start, failed: failed) { out[s.startDate.dayStart, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60 }
        return out
    }

    /// Nights are attributed to the day you woke up: anything ending after 6 pm counts toward tomorrow.
    static func nightKey(_ end: Date) -> Date {
        let hour = Calendar.current.component(.hour, from: end)
        return hour >= 18 ? end.dayStart.adding(days: 1) : end.dayStart
    }

    private func sleepNights(from start: Date, failed: FailFlag) async -> ([SleepNight], [HypnoSegment]) {
        guard let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return ([], []) }
        let all = await samples(t, from: start, failed: failed).compactMap { $0 as? HKCategorySample }
        var nights: [String: SleepNight] = [:]
        for s in all {
            let o = Self.origin(s)
            guard o != .other || Self.isAppleOther(s) else { continue }
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

    private func workouts(from start: Date, failed: FailFlag) async -> [WorkoutRec] {
        let ws = await samples(HKObjectType.workoutType(), from: start, failed: failed).compactMap { $0 as? HKWorkout }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var recs: [WorkoutRec] = ws.compactMap { w in
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
                              distanceKm: (w.statistics(for: distType) ?? w.statistics(for: HKQuantityType(.distanceCycling)))?
                                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)))
        }
        // Workouts saved without heart-rate statistics (WHOOP, older or third-party ones): work the average and
        // peak out from the heart-rate samples recorded during the workout.
        for i in recs.indices where recs[i].avgHR == nil {
            if let (avg, max) = await heartRate(from: recs[i].start, to: recs[i].end) {
                recs[i].avgHR = avg
                recs[i].maxHR = recs[i].maxHR ?? max
            }
        }
        return recs
    }

    private func heartRate(from start: Date, to end: Date) async -> (Double, Double)? {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.heartRate), quantitySamplePredicate: pred,
                                      options: [.discreteAverage, .discreteMax]) { _, stat, _ in
                guard let avg = stat?.averageQuantity()?.doubleValue(for: bpm),
                      let max = stat?.maximumQuantity()?.doubleValue(for: bpm) else { cont.resume(returning: nil); return }
                cont.resume(returning: (avg, max))
            }
            store.execute(q)
        }
    }

    // MARK: - Data check (diagnostics)

    /// What is actually flowing from Health for one metric: the newest sample and how many arrived in the last 7 days.
    struct ProbeRow: Identifiable {
        let id: String
        let title: String
        let unit: String
        var lastValue: Double?
        var lastDate: Date?
        var lastSource: String = "—"
        var lastOrigin: Origin = .other
        var count7d: Int = 0
    }

    static let probeTitles: [HKQuantityTypeIdentifier: String] = [
        .restingHeartRate: "Resting HR", .heartRateVariabilitySDNN: "HRV (SDNN)", .heartRate: "Heart rate",
        .walkingHeartRateAverage: "Walking HR", .respiratoryRate: "Respiratory rate", .oxygenSaturation: "Blood oxygen",
        .appleSleepingWristTemperature: "Wrist temperature", .vo2Max: "VO₂ max", .bodyMass: "Weight", .bodyFatPercentage: "Body fat",
        .heartRateRecoveryOneMinute: "HR recovery", .environmentalAudioExposure: "Noise", .runningSpeed: "Running speed",
        .runningPower: "Running power", .runningStrideLength: "Stride", .stepCount: "Steps", .distanceWalkingRunning: "Distance",
        .flightsClimbed: "Flights", .activeEnergyBurned: "Active energy", .basalEnergyBurned: "Resting energy",
        .appleExerciseTime: "Exercise minutes", .appleStandTime: "Stand minutes", .timeInDaylight: "Daylight",
        .distanceCycling: "Cycling distance", .walkingSpeed: "Walking speed", .walkingStepLength: "Step length",
        .walkingAsymmetryPercentage: "Walking asymmetry", .walkingDoubleSupportPercentage: "Double support",
        .physicalEffort: "Physical effort", .leanBodyMass: "Lean mass", .bodyMassIndex: "BMI", .height: "Height",
        .dietaryEnergyConsumed: "Food energy", .dietaryWater: "Water",
    ]

    /// One row per metric we read, plus sleep and workouts. Cheap enough to run on demand from Settings.
    func probe() async -> [ProbeRow] {
        guard Self.available else { return [] }
        let since = Date().dayStart.adding(days: -6)
        var rows: [ProbeRow] = []
        for spec in Self.specs {
            guard let type = HKQuantityType.quantityType(forIdentifier: spec.id) else { continue }
            var row = ProbeRow(id: spec.id.rawValue, title: Self.probeTitles[spec.id] ?? (spec.key == \DayStat.breathingDisturbances ? "Breathing disturbances" : spec.id.rawValue), unit: Self.unitLabel(spec))
            let recent = await samples(type, from: since, limit: 20_000)
            row.count7d = recent.count
            var last = recent.last as? HKQuantitySample
            if last == nil { last = await samples(type, from: .distantPast, limit: 1, newestFirst: true).first as? HKQuantitySample }
            if let last {
                row.lastValue = last.quantity.doubleValue(for: spec.unit) * spec.scale
                row.lastDate = last.endDate
                row.lastSource = last.sourceRevision.source.name
                row.lastOrigin = Self.origin(last)
            }
            rows.append(row)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            var row = ProbeRow(id: "sleep", title: "Sleep samples", unit: "min")
            let recent = await samples(sleep, from: since, limit: 20_000)
            row.count7d = recent.count
            if let last = recent.last {
                row.lastValue = last.endDate.timeIntervalSince(last.startDate) / 60
                row.lastDate = last.endDate; row.lastSource = last.sourceRevision.source.name; row.lastOrigin = Self.origin(last)
            }
            rows.append(row)
        }
        var w = ProbeRow(id: "workouts", title: "Workouts", unit: "min")
        let ws = await samples(HKObjectType.workoutType(), from: since, limit: 20_000)
        w.count7d = ws.count
        if let last = ws.last {
            w.lastValue = last.endDate.timeIntervalSince(last.startDate) / 60
            w.lastDate = last.endDate; w.lastSource = last.sourceRevision.source.name; w.lastOrigin = Self.origin(last)
        }
        rows.append(w)
        return rows
    }

    private func samples(_ type: HKSampleType, from start: Date, limit: Int, newestFirst: Bool = false) async -> [HKSample] {
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: limit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: !newestFirst)]) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
    }

    static func unitLabel(_ spec: QSpec) -> String {
        if spec.key == \DayStat.breathingDisturbances { return "count" }
        switch spec.id {
        case .restingHeartRate, .heartRate, .walkingHeartRateAverage, .heartRateRecoveryOneMinute: return "bpm"
        case .heartRateVariabilitySDNN: return "ms"
        case .respiratoryRate: return "br/min"
        case .oxygenSaturation, .bodyFatPercentage: return "%"
        case .appleSleepingWristTemperature: return "°C"
        case .vo2Max: return "ml/kg/min"
        case .bodyMass: return "kg"
        case .environmentalAudioExposure: return "dB"
        case .runningSpeed: return "m/s"
        case .runningPower: return "W"
        case .runningStrideLength: return "m"
        case .stepCount, .flightsClimbed, .bodyMassIndex: return "count"
        case .distanceWalkingRunning, .distanceCycling: return "km"
        case .walkingSpeed: return "m/s"
        case .walkingStepLength, .height: return "m"
        case .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage: return "%"
        case .physicalEffort: return "MET"
        case .leanBodyMass: return "kg"
        case .dietaryEnergyConsumed: return "kcal"
        case .dietaryWater: return "L"
        case .activeEnergyBurned, .basalEnergyBurned: return "kcal"
        default: return "min"
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
