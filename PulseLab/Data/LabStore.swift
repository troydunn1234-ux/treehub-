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

    var readinessToday: Double? { readinessDetailToday?.score }
    /// True when this morning's readiness leans on yesterday's Watch HRV / resting HR.
    var readinessUsesYesterday: Bool { readinessDetailToday?.usedYesterday ?? false }
    private var readinessDetailToday: Compare.ReadinessDetail? {
        Compare.readinessDetail(day: Date(), watch: watchDays, sleeps: sleeps, carryOver: true)
    }
    var recoveryToday: Double? { whoopDays.last(where: { $0.recovery != nil })?.recovery }

    func connectHealth() async {
        let ok = await HealthPull.shared.requestAccess()
        healthAsked = true
        UserDefaults.standard.set(true, forKey: "healthAsked")
        if !ok { toast = "Apple Health isn't available on this device." }
        await refresh()
    }

    /// Open a tab, optionally focusing a metric (detail sheet or Compare focus).
    func go(_ tab: LabTab, metric: MetricKey? = nil) {
        if tab == .compare, let m = metric?.compareName { focusCompare = m }
        jump = tab
        if let metric, tab != .compare { detail = metric }
    }

    func refresh() async {
        if Self.isDemo { loadDemo(); return }
        guard !loading else { return }
        loading = true
        defer { loading = false; loadedOnce = true }
        async let health = HealthPull.shared.pull(days: 90)
        if WhoopAdapter.connected {
            await WhoopAdapter.sync(days: 90)
            if let e = WhoopAdapter.client.lastError {
                let failed = WhoopAdapter.client.log.first { !$0.ok }.map { " (\($0.path.replacingOccurrences(of: "/v2/", with: "")))" } ?? ""
                toast = "WHOOP: \(e)\(failed) · see Settings → Data check"
            }
        }
        let h = await health
        merge(health: h)
        lastPull = Date()
        afterRefresh()
    }

    /// Agreement scores over the last 30 days (what Today, the weekly summary and Trust all read).
    var agreements30: [Agreement] { Compare.agreements(watch: watchDays, whoop: whoopDays, sleeps: sleeps, days: 30) }

    /// Push fresh numbers to the widget and refresh the weekly notification text.
    private func afterRefresh() {
        WidgetBridge.publish(self)
        Notify.reschedule(agreements: agreements30)
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
        for api in WhoopAdapter.days() {
            var d = whoop[api.day] ?? DayStat(day: api.day)
            d.rhr = api.rhr ?? d.rhr
            d.hrv = api.hrv ?? d.hrv
            d.resp = api.resp ?? d.resp
            d.spo2 = api.spo2 ?? d.spo2
            d.tempDev = api.tempDev ?? d.tempDev
            d.skinTempC = api.skinTempC ?? d.skinTempC
            d.avgHR = api.avgHR ?? d.avgHR
            d.recovery = api.recovery ?? d.recovery
            d.strain = api.strain ?? d.strain
            d.totalKcalWhoop = api.totalKcalWhoop ?? d.totalKcalWhoop
            whoop[api.day] = d
        }
        whoopDays = whoop.values.sorted { $0.day < $1.day }

        // Readiness for every Watch day (so it can be charted against WHOOP recovery).
        var wd = watchDays
        for i in wd.indices { wd[i].recovery = Compare.readiness(day: wd[i].day, watch: watchDays, sleeps: h.sleeps) }
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
    }

    // MARK: - CSV export

    func csv() -> String {
        var rows = ["date,source,resting_hr,hrv_ms,resp_rate,spo2,temp_dev_c,active_kcal,total_kcal,steps,distance_km,exercise_min,recovery,strain,sleep_h,deep_min,rem_min"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        func v(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "" }
        for s in Source.allCases {
            for d in days(s) {
                let n = sleeps.first { $0.source == s && Calendar.current.isDate($0.night, inSameDayAs: d.day) }
                rows.append([f.string(from: d.day), s.rawValue, v(d.rhr), v(d.hrv), v(d.resp), v(d.spo2), v(d.tempDev), v(d.activeKcal),
                             v(d.totalKcal), v(d.steps), v(d.distanceKm), v(d.exerciseMin), v(d.recovery), v(d.strain),
                             v(n.map { $0.asleepMin / 60 }), v(n?.deepMin), v(n?.remMin)].joined(separator: ","))
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
        var wd = watchDays
        for i in wd.indices { wd[i].recovery = Compare.readiness(day: wd[i].day, watch: watchDays, sleeps: sleeps) }
        watchDays = wd
        healthAsked = true
        lastPull = Date()
        loadedOnce = true
        afterRefresh()
    }
}
