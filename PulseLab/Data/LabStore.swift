import Foundation
import SwiftUI

/// Everything the screens show: Apple Health (split Watch / WHOOP-in-Health) plus the WHOOP API,
/// merged into one neutral set of days, nights and workouts.
@MainActor
@Observable
final class LabStore {
    static let shared = LabStore()

    private(set) var watchDays: [DayStat] = []
    private(set) var whoopDays: [DayStat] = []
    private(set) var sleeps: [SleepNight] = []
    private(set) var hypnogram: [HypnoSegment] = []
    private(set) var workouts: [WorkoutRec] = []
    /// Steps per device per day (iPhone vs each Watch), straight from Health, not de-duplicated.
    private(set) var stepsByDevice: [Date: [String: Double]] = [:]
    private(set) var loading = false
    private(set) var lastPull: Date?
    private(set) var healthAsked = UserDefaults.standard.bool(forKey: "healthAsked")
    /// True once the first pull has finished (so screens can tell "loading" from "empty").
    private(set) var loadedOnce = false

    // Navigation & UI state shared by every screen.
    /// Set to jump to another tab (Lab notes use this).
    var jump: LabTab?
    /// Metric the Compare screen should focus on next time it appears.
    var focusCompare: String?
    /// Metric detail sheet currently shown.
    var detail: MetricKey?
    /// Short message shown as a toast at the top (errors, confirmations).
    var toast: String?
    /// This morning's briefing (Today card, notification, Siri, Watch); rebuilt after every sync.
    private(set) var briefing = Briefing()
    /// Log WHOOP sheet shown from the root (morning pop-up, notification tap, Siri, pulselab://log-whoop).
    var logWhoop: LogWhoopRequest?

    // MARK: - WHOOP typed in by hand

    /// Manual WHOOP entries by day (persisted in WhoopManualStore).
    private(set) var manual: [Date: WhoopManualEntry] = LabStore.isDemo ? [:] : WhoopManualStore.load()
    /// Fields whose shown WHOOP value came from a manual entry (the API didn't have that number), by day.
    private(set) var manualMarks: [Date: Set<ManualField>] = [:]

    func isManual(_ day: Date, _ f: ManualField) -> Bool { manualMarks[day.dayStart]?.contains(f) ?? false }
    func manualEntry(_ day: Date) -> WhoopManualEntry? { manual[day.dayStart] }
    /// Today's WHOOP recovery, from the API, Health or a manual entry.
    var hasWhoopRecoveryToday: Bool { whoopDays.stat(on: Date())?.recovery != nil }

    func saveManual(_ e: WhoopManualEntry) {
        var e = e
        e.day = e.day.dayStart
        e.savedAt = Date()
        if e.isEmpty { manual[e.day] = nil } else { manual[e.day] = e }
        if !Self.isDemo { WhoopManualStore.save(manual) }
        remerge()
    }

    func deleteManual(_ day: Date) {
        manual[day.dayStart] = nil
        if !Self.isDemo { WhoopManualStore.save(manual) }
        remerge()
    }

    /// Another device changed manual entries (iCloud): read them again and redraw.
    func reloadManual() {
        guard !Self.isDemo else { return }
        manual = WhoopManualStore.load()
        remerge()
    }

    /// Rebuild the merged days after a manual edit, without reading Health or WHOOP again.
    private func remerge() {
        if Self.isDemo { loadDemo(); return }
        // Before the saved history is read, a manual edit is laid over it once it arrives (merge applies manual).
        guard cacheLoaded || cacheLoad == nil else {
            Task { await cacheReady(); remerge() }
            return
        }
        merge(health: healthCache ?? HealthPull.Result())
        lastPull = Date()
        afterRefresh()
    }

    var hasAnyData: Bool { !watchDays.isEmpty || !whoopDays.isEmpty || !sleeps.isEmpty || !workouts.isEmpty }

    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    var whoopConnected: Bool { Self.isDemo || WhoopAdapter.connected }

    func days(_ s: Source) -> [DayStat] { s == .watch ? watchDays : whoopDays }
    /// Today's numbers, falling back to the newest day we have (see `todayIsStale`).
    func today(_ s: Source) -> DayStat? { days(s).stat(on: Date()) ?? days(s).last }
    /// The newest value a tracker has for a metric, and whether it's from today.
    func latest(_ s: Source, _ kp: KeyPath<DayStat, Double?>) -> (Double, Bool)? {
        guard let d = days(s).last(where: { $0[keyPath: kp] != nil }), let v = d[keyPath: kp] else { return nil }
        return (v, d.day.isToday)
    }
    /// True when `today(_:)` had to fall back to an older day.
    func todayIsStale(_ s: Source) -> Bool { days(s).stat(on: Date()) == nil && days(s).last != nil }

    /// Why a side shows "—": tells "not set up" apart from "nothing arrived today". Nil when there is data.
    func reason(_ s: Source) -> String? {
        if Self.isDemo { return nil }
        switch s {
        case .watch:
            if !healthAsked { return "Health not allowed" }
            if watchDays.isEmpty { return loadedOnce ? "No Health samples" : "Loading" }
            if todayIsStale(.watch), let d = watchDays.last { return "As of \(d.day.formatted(.dateTime.weekday(.abbreviated)))" }
        case .whoop:
            if !whoopConnected && whoopDays.isEmpty { return "WHOOP not connected" }
            if whoopDays.isEmpty { return loadedOnce ? "No WHOOP data yet" : "Loading" }
            if todayIsStale(.whoop), let d = whoopDays.last { return "As of \(d.day.formatted(.dateTime.weekday(.abbreviated)))" }
        }
        return nil
    }

    // MARK: - Data check (Settings)

    private(set) var probe: [HealthPull.ProbeRow] = []
    private(set) var probing = false
    func runDataCheck() async {
        guard !probing else { return }
        probing = true
        defer { probing = false }
        if Self.isDemo { probe = []; return }
        probe = await HealthPull.shared.probe()
    }
    func lastNight(_ s: Source) -> SleepNight? { sleeps.filter { $0.source == s }.max { $0.night < $1.night } }

    /// Nil until there is a baseline to score against (see `ReadinessDetail.hasBaseline`).
    var readinessToday: Double? { readinessDetailToday.flatMap { $0.hasBaseline ? $0.score : nil } }
    /// True when this morning's readiness leans on yesterday's Watch HRV / resting HR.
    var readinessUsesYesterday: Bool { readinessDetailToday?.usedYesterday ?? false }
    /// Today's readiness with every contributor itemised (the readiness detail screen).
    var readinessDetailToday: Compare.ReadinessDetail? {
        // Reading both arrays keeps SwiftUI watching them even when the remembered answer is used.
        let watch = watchDays, nights = sleeps
        let day = Date().dayStart
        if let m = readinessMemo, m.day == day, m.version == dataVersion { return m.detail }
        let detail = Compare.readinessDetail(day: Date(), watch: watch, sleeps: nights, carryOver: true)
        readinessMemo = (day, dataVersion, detail)
        return detail
    }

    /// Bumped whenever the merged days / nights change; remembered answers below are only reused for the same version
    /// and day (Today reads readiness several times per redraw, and each read sorted two years of days).
    @ObservationIgnored private var dataVersion = 0
    @ObservationIgnored private var readinessMemo: (day: Date, version: Int, detail: Compare.ReadinessDetail?)?
    @ObservationIgnored private var agreementsMemo: (day: Date, version: Int, list: [Agreement])?
    /// This morning's WHOOP recovery (yesterday's until today's is scored). Never an older one: a recovery from
    /// days ago shown beside today's readiness would be a wrong head-to-head.
    var recoveryToday: Double? {
        guard let d = whoopDays.last(where: { $0.recovery != nil }), d.day >= Date().dayStart.adding(days: -1) else { return nil }
        return d.recovery
    }

    func connectHealth() async {
        let ok = await HealthPull.shared.requestAccess()
        healthAsked = true
        UserDefaults.standard.set(true, forKey: "healthAsked")
        if !ok { toast = "Apple Health isn't available on this device." }
        startLiveUpdates()
        await refresh(.user)
    }

    /// Open a tab, optionally focusing a metric (detail sheet or Compare focus).
    func go(_ tab: LabTab, metric: MetricKey? = nil) {
        if tab == .compare, let m = metric?.compareName { focusCompare = m }
        jump = tab
        if let metric, tab != .compare { detail = metric }
    }

    // MARK: - Sync

    /// What kicked off a refresh. Only `.user` forces WHOOP past its 10-minute throttle; observer
    /// refreshes (new Health samples) skip WHOOP entirely and stay quiet.
    enum Trigger { case user, launch, foreground, observer, background }

    /// Raw Health history (2 years, cached on disk) that each refresh splices fresh days into.
    private var healthCache: HealthPull.Result?
    /// Start of the cached Health history (nil until the one-time backfill has finished).
    private(set) var historyFrom: Date?
    /// When Apple Health was last read successfully.
    private(set) var healthSynced: Date?
    /// True while the one-time full-history read runs.
    private(set) var backfilling = false
    private(set) var syncStage: String?
    private var healthProgress: Double = 0
    private var pendingPass = false
    private var observerTask: Task<Void, Never>?

    var lastWatchSample: Date? { healthCache?.lastWatchSample }
    var lastWhoopInHealth: Date? { healthCache?.lastWhoopSample }
    var watchName: String? { healthCache?.watchName }
    /// Where the Apple side of each Health metric last came from ("WATCH", "IPHONE", an app name…), keyed by type id.
    var appleOrigins: [String: String] { healthCache?.appleOrigins ?? [:] }

    /// 0…1 across Health and WHOOP while syncing.
    var syncProgress: Double {
        let w = WhoopClient.shared
        if w.isSyncing { return (healthProgress + w.progress) / 2 }
        return healthProgress
    }
    /// One line for the progress bar: "Apple Health · 2 years of history", "WHOOP · Sleep"…
    var syncLine: String? {
        guard loading else { return nil }
        let w = WhoopClient.shared
        if w.isSyncing, let st = w.stage { return "WHOOP · \(st)" }
        return syncStage
    }

    /// Reading the 2-year Health cache from disk (off the main thread, so launch draws its first frame right away).
    /// Every refresh waits for it first: a refresh that started without the cache would re-read 2 years of history.
    @ObservationIgnored private var cacheLoad: Task<Void, Never>?
    @ObservationIgnored private var cacheLoaded = false

    init() {
        guard !Self.isDemo else { return }
        cacheLoad = Task { @MainActor [weak self] in
            let snap = await Task.detached(priority: .userInitiated) { HealthCache.load() }.value
            guard let self else { return }
            defer { self.cacheLoaded = true }
            guard let snap, self.healthCache == nil else { return }
            self.healthCache = snap.result
            self.historyFrom = snap.backfilledFrom
            self.healthSynced = snap.savedAt
            self.lastPull = snap.savedAt
            self.merge(health: snap.result)
            self.loadedOnce = true
        }
    }

    /// Waits until the saved Health history is in memory (instant after the first time).
    private func cacheReady() async {
        if let t = cacheLoad { await t.value }
    }

    /// Observer queries + background delivery for every Health type (no-op until Health was asked).
    func startLiveUpdates() {
        guard !Self.isDemo, healthAsked else { return }
        HealthLive.shared.start { done in
            Task { @MainActor in
                await LabStore.shared.healthChanged()
                done()
            }
        }
    }

    /// New samples landed in Health: coalesce a burst of observer callbacks into one quick refresh.
    func healthChanged() async {
        if let t = observerTask { await t.value; return }
        let t = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self.refresh(.observer)
            self.observerTask = nil
        }
        observerTask = t
        await t.value
    }

    /// Start over: read the full 2 years from Health and WHOOP's whole history again.
    func rebuildHistory() async {
        guard !loading else { return }
        await cacheReady()
        HealthCache.clear()
        healthCache = nil
        historyFrom = nil
        HealthLive.shared.resetAnchors()
        WhoopClient.shared.resetHistory()
        await refresh(.user)
    }

    func refresh(_ trigger: Trigger = .user) async {
        if Self.isDemo { loadDemo(); return }
        guard !loading else {
            if trigger == .observer { pendingPass = true }
            return
        }
        loading = true
        await cacheReady()
        healthProgress = 0
        syncStage = "Apple Health"
        defer {
            loading = false; loadedOnce = true; syncStage = nil; healthProgress = 0
            if pendingPass {
                pendingPass = false
                Task { await self.refresh(.observer) }
            }
        }
        let interactive = trigger == .user || trigger == .launch || trigger == .foreground
        // A newer Pulse Lab may read types the user hasn't been asked about yet.
        if interactive, healthAsked, await HealthPull.shared.needsAuthorizationPrompt() {
            _ = await HealthPull.shared.requestAccess()
        }

        async let health = pullHealth()
        if WhoopAdapter.connected && trigger != .observer {
            await WhoopAdapter.sync(force: trigger == .user)
            if interactive, let e = WhoopAdapter.client.lastError {
                let failed = WhoopAdapter.client.log.first { !$0.ok }.map { " (\($0.path.replacingOccurrences(of: "/v2/", with: "")))" } ?? ""
                toast = "WHOOP: \(e)\(failed) · see Settings → Data check"
            }
        }
        let h = await health
        merge(health: h ?? healthCache ?? HealthPull.Result())
        if h != nil {
            let n = lastNight(.watch)
            recentWatch = await HealthPull.shared.recent(sleepStart: n?.start, sleepEnd: n?.end)
        }
        lastPull = Date()
        afterRefresh()
    }

    // MARK: - Most relevant recent reading (Today's head to head)

    /// Watch resting HR / HRV / breathing rate from the last 36 h (sample-level, see `HealthPull.recent`).
    private(set) var recentWatch: [String: HealthPull.Recent] = [:]

    /// A value with a short caption saying when it's from ("LAST NIGHT", "3H AGO", "YESTERDAY", "MANUAL").
    struct Reading { let value: Double; let caption: String; let manual: Bool }

    /// The most relevant recent value for one side: last night's / the newest sample (Watch overnight metrics),
    /// else today's daily value, else yesterday's. Nil only when there's nothing from today or yesterday.
    func reading(_ s: Source, _ kp: KeyPath<DayStat, Double?>, recent key: String? = nil, manual field: ManualField? = nil) -> Reading? {
        if s == .watch, let key, let r = recentWatch[key], r.at > Date().addingTimeInterval(-36 * 3600) {
            return Reading(value: r.value, caption: r.overnight ? String(localized: "LAST NIGHT") : Self.ago(r.at), manual: false)
        }
        let yesterday = Date().dayStart.adding(days: -1)
        guard let d = days(s).last(where: { $0[keyPath: kp] != nil }), d.day >= yesterday, let v = d[keyPath: kp] else { return nil }
        let manual = field.map { isManual(d.day, $0) } ?? false
        let when = d.day.isToday ? String(localized: "TODAY") : String(localized: "YESTERDAY")
        return Reading(value: v, caption: manual ? when + " · " + String(localized: "MANUAL") : when, manual: manual)
    }

    static func ago(_ t: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(t) / 60)
        if m < 60 { return m < 2 ? String(localized: "JUST NOW") : String(localized: "\(m)M AGO") }
        if Calendar.current.isDateInToday(t) { return String(localized: "\(m / 60)H AGO") }
        if Calendar.current.isDateInYesterday(t) { return String(localized: "YESTERDAY") }
        return t.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    /// Quick edit for one WHOOP number (steps / calories) shown from the root.
    var quickWhoop: WhoopQuickEdit?

    /// Reads Apple Health: the full history once, then only from the earliest day that can have changed
    /// (3 days back, the last successful read, or a day a late sample landed on), spliced into the cache.
    /// Nil when Health couldn't be read (locked iPhone, not allowed): the cache stays as it was.
    private func pullHealth() async -> HealthPull.Result? {
        guard HealthPull.available, healthAsked, UIApplication.shared.isProtectedDataAvailable else { return nil }
        let today = Date().dayStart
        let progress: @Sendable (Double) -> Void = { p in Task { @MainActor in LabStore.shared.healthProgress = p } }
        let dirtyBefore = HealthLive.dirtyFrom
        if let cache = healthCache, let from = historyFrom {
            var cutoff = today.adding(days: -3)
            if let last = healthSynced { cutoff = min(cutoff, last.dayStart.adding(days: -1)) }
            if let dirty = dirtyBefore { cutoff = min(cutoff, dirty) }
            // Saved history worked out with older maths (e.g. sleep that summed overlapping samples) is read
            // again once, in place: the saved numbers stay on screen until the corrected ones replace them.
            let stale = UserDefaults.standard.integer(forKey: Self.healthMathKey) < HealthPull.mathVersion
            if stale { cutoff = from }
            cutoff = max(cutoff, from)
            let fresh = await HealthPull.shared.pull(from: cutoff, progress: progress)
            guard !fresh.failed else { return nil }
            if stale { UserDefaults.standard.set(HealthPull.mathVersion, forKey: Self.healthMathKey) }
            return saveHealth(cache.merged(with: fresh, from: cutoff), from: from, dirtyBefore: dirtyBefore)
        }
        let from = today.adding(days: -(HealthCache.historyDays - 1))
        backfilling = true
        syncStage = "Apple Health · reading 2 years of history"
        defer { backfilling = false }
        let fresh = await HealthPull.shared.pull(from: from, progress: progress)
        guard !fresh.failed else { return nil }
        UserDefaults.standard.set(HealthPull.mathVersion, forKey: Self.healthMathKey)
        return saveHealth(fresh, from: from, dirtyBefore: dirtyBefore)
    }

    /// Which `HealthPull.mathVersion` the saved Health history was worked out with.
    static let healthMathKey = "healthMathVersion"

    private func saveHealth(_ result: HealthPull.Result, from: Date, dirtyBefore: Date?) -> HealthPull.Result {
        healthCache = result
        historyFrom = from
        healthSynced = Date()
        if HealthLive.dirtyFrom == dirtyBefore { HealthLive.dirtyFrom = nil }
        HealthCache.save(.init(version: HealthCache.version, result: result, backfilledFrom: from, savedAt: Date()))
        return result
    }

    /// Agreement scores over the last 30 days (what Today, the weekly summary and Trust all read).
    var agreements30: [Agreement] {
        let watch = watchDays, whoop = whoopDays, nights = sleeps
        let day = Date().dayStart
        if let m = agreementsMemo, m.day == day, m.version == dataVersion { return m.list }
        let list = Compare.agreements(watch: watch, whoop: whoop, sleeps: nights, days: 30)
        agreementsMemo = (day, dataVersion, list)
        return list
    }

    /// Push fresh numbers to the widget and refresh the weekly notification text.
    private func afterRefresh() {
        // A background wake that found nothing (Health locked and no saved history readable yet) must not blank
        // the widget, the Watch or what Still Pointz / Rootbound show: keep what was shared until there's data.
        if !hasAnyData && UIApplication.shared.applicationState == .background { return }
        let b = Briefing.build(self)
        briefing = b
        MorningBriefing.latest = b
        MorningBriefing.whoopAPI = WhoopAdapter.connected
        MorningBriefing.usesWhoop = whoopConnected || !whoopDays.isEmpty || !manual.isEmpty
        WidgetBridge.publish(self)
        PulseLabWellness.publish(self)
        WatchSync.shared.push(self)
        Notify.reschedule(agreements: agreements30)
        let logged = hasWhoopRecoveryToday
        Task { await WhoopPrompt.reschedule(loggedToday: logged) }
    }

    /// Lays manual WHOOP entries over the merged data. Per field the WHOOP API wins; a manual number
    /// beats a WHOOP value found in Health (it's what you read off the WHOOP app, prefilled from Health).
    private func applyManual(api: [DayStat], apiNights: Set<Date>) {
        var marks: [Date: Set<ManualField>] = [:]
        guard !manual.isEmpty else { manualMarks = [:]; dataVersion += 1; return }
        let apiByDay = Dictionary(api.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var byDay = Dictionary(whoopDays.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var nights = sleeps
        for (day, e) in manual {
            let a = apiByDay[day]
            var d = byDay[day] ?? DayStat(day: day)
            var m = Set<ManualField>()
            func put(_ v: Double?, _ apiV: Double?, _ kp: WritableKeyPath<DayStat, Double?>, _ f: ManualField) {
                guard let v, apiV == nil else { return }
                d[keyPath: kp] = v
                m.insert(f)
            }
            put(e.recovery, a?.recovery, \.recovery, .recovery)
            put(e.strain, a?.strain, \.strain, .strain)
            put(e.hrv, a?.hrv, \.hrv, .hrv)
            put(e.rhr, a?.rhr, \.rhr, .rhr)
            put(e.resp, a?.resp, \.resp, .resp)
            put(e.steps, a?.steps, \.steps, .steps)
            put(e.kcal, a?.totalKcalWhoop, \.totalKcalWhoop, .kcal)
            if e.recovery != nil || e.strain != nil || e.hrv != nil || e.rhr != nil || e.resp != nil || e.steps != nil || e.kcal != nil {
                byDay[day] = d
            }
            // Sleep belongs to the morning you woke up, same day as the entry.
            if !apiNights.contains(day), e.sleepMin != nil || e.sleepPerformance != nil {
                if let i = nights.firstIndex(where: { $0.source == .whoop && $0.night == day }) {
                    if let p = e.sleepPerformance { nights[i].performance = p; m.insert(.sleepPerformance) }
                    // Stages WHOOP wrote to Health stay; a typed total only fills a night without them.
                    if let s = e.sleepMin, nights[i].asleepMin == 0 { nights[i].unspecifiedMin = s; m.insert(.sleep) }
                } else {
                    var n = SleepNight(night: day, source: .whoop)
                    if let s = e.sleepMin { n.unspecifiedMin = s; m.insert(.sleep) }
                    if let p = e.sleepPerformance { n.performance = p; m.insert(.sleepPerformance) }
                    nights.append(n)
                }
            }
            if !m.isEmpty { marks[day] = m }
        }
        whoopDays = byDay.values.sorted { $0.day < $1.day }
        sleeps = nights.sorted { $0.night < $1.night }
        manualMarks = marks
        dataVersion += 1
    }

    /// WHOOP API wins where it has data; WHOOP samples found in Apple Health fill the gaps.
    private func merge(health h: HealthPull.Result) {
        // Health stores wrist temperature as an absolute reading; show it as change from your own average.
        var wdays = h.watch
        let temps = wdays.compactMap(\.tempDev)
        if let base = Stats.mean(temps) { for i in wdays.indices { wdays[i].tempDev = wdays[i].tempDev.map { $0 - base } } }
        watchDays = wdays
        stepsByDevice = h.stepsByDevice
        if !wdays.isEmpty { Reviews.noteWin() }
        var whoop = Dictionary(h.whoop.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let apiDays = WhoopAdapter.days()
        for api in apiDays {
            var d = whoop[api.day] ?? DayStat(day: api.day)
            d.rhr = api.rhr ?? d.rhr
            d.hrv = api.hrv ?? d.hrv
            d.resp = api.resp ?? d.resp
            d.spo2 = api.spo2 ?? d.spo2
            d.tempDev = api.tempDev ?? d.tempDev
            d.skinTempC = api.skinTempC ?? d.skinTempC
            d.avgHR = api.avgHR ?? d.avgHR
            d.maxHR = api.maxHR ?? d.maxHR
            d.recovery = api.recovery ?? d.recovery
            d.strain = api.strain ?? d.strain
            d.totalKcalWhoop = api.totalKcalWhoop ?? d.totalKcalWhoop
            whoop[api.day] = d
        }
        whoopDays = whoop.values.sorted { $0.day < $1.day }

        // Readiness for every Watch day (so it can be charted against WHOOP recovery).
        // Each day only needs itself, the 14 days before and that night, so hand it just those (2 years of days otherwise make this quadratic).
        var wd = watchDays
        let byDay = Dictionary(wd.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let watchNights = Dictionary(h.sleeps.filter { $0.source == .watch }.map { ($0.night, $0) }, uniquingKeysWith: { a, _ in a })
        for i in wd.indices {
            let d = wd[i].day
            let window = (0...Compare.readinessLookback).compactMap { byDay[d.adding(days: -$0)] }
            let night = watchNights[d].map { [$0] } ?? []
            wd[i].recovery = Compare.readiness(day: d, watch: window, sleeps: night)
        }
        watchDays = wd

        let apiSleeps = WhoopAdapter.sleeps()
        let apiNights = Set(apiSleeps.map(\.night))
        sleeps = (h.sleeps.filter { $0.source == .watch || !apiNights.contains($0.night) } + apiSleeps).sorted { $0.night < $1.night }
        hypnogram = h.hypnogram

        let apiW = WhoopAdapter.workouts()
        let healthWhoop = h.workouts.filter { $0.source == .whoop }
        // Drop WHOOP-in-Health workouts that the API already gave us (same start within 2 min).
        let extra = healthWhoop.filter { hw in !apiW.contains { abs($0.start.timeIntervalSince(hw.start)) < 120 } }
        workouts = (h.workouts.filter { $0.source == .watch } + extra + apiW).sorted { $0.start > $1.start }
        applyManual(api: apiDays, apiNights: apiNights)
    }

    // MARK: - CSV export

    func csv() -> String {
        var rows = ["date,source,resting_hr,hrv_ms,resp_rate,spo2,temp_dev_c,active_kcal,total_kcal,steps,distance_km,exercise_min,recovery,strain,sleep_h,deep_min,rem_min,sleep_performance,avg_hr,walking_hr,vo2max,weight_kg,body_fat_pct,stand_min,stand_hours,flights,mindful_min,daylight_min,basal_kcal,cycling_km,walk_speed_ms,physical_effort,breathing_disturbances,diet_kcal,water_l,skin_temp_c"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        func v(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "" }
        for s in Source.allCases {
            for d in days(s) {
                let n = sleeps.first { $0.source == s && Calendar.current.isDate($0.night, inSameDayAs: d.day) }
                rows.append([f.string(from: d.day), s.rawValue, v(d.rhr), v(d.hrv), v(d.resp), v(d.spo2), v(d.tempDev), v(d.activeKcal),
                             v(d.totalKcal), v(d.steps), v(d.distanceKm), v(d.exerciseMin), v(d.recovery), v(d.strain),
                             v(n.map { $0.asleepMin / 60 }), v(n?.deepMin), v(n?.remMin), v(n?.performance), v(d.avgHR), v(d.walkHR),
                             v(d.vo2), v(d.weightKg), v(d.bodyFat), v(d.standMin), v(d.standHours), v(d.flights), v(d.mindfulMin),
                             v(d.daylightMin), v(d.basalKcal), v(d.cyclingKm), v(d.walkSpeed), v(d.physicalEffort),
                             v(d.breathingDisturbances), v(d.dietKcal), v(d.waterL), v(d.skinTempC)].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    func exportFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PulseLab-\(Int(Date().timeIntervalSince1970)).csv")
        do { try csv().write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    // MARK: - Demo

    func loadDemo() {
        WhoopAdapter.demo()
        let d = DemoData.make()
        watchDays = d.watch
        whoopDays = d.whoop
        sleeps = d.sleeps
        hypnogram = d.hypnogram
        workouts = d.workouts
        applyManual(api: [], apiNights: [])
        var wd = watchDays
        for i in wd.indices { wd[i].recovery = Compare.readiness(day: wd[i].day, watch: watchDays, sleeps: sleeps) }
        watchDays = wd
        dataVersion += 1
        healthAsked = true
        lastPull = Date()
        loadedOnce = true
        afterRefresh()
    }
}
