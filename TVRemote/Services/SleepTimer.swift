import Foundation
import Observation
import UIKit
import UserNotifications
import BackgroundTasks

/// Sleep timer: turns the TV off after 15/30/60/90 minutes (or any length) with the normal power-off command.
///
/// iOS doesn't let an app run whenever it likes in the background, so this uses every way it allows, in order:
///  1. While Couch Remote is open, a timer in the app sends power off right on time.
///  2. If the app is in the background with under ~25 s to go, it asks iOS for a little extra time and finishes.
///  3. A local notification goes off at the end time. Its "Turn Off TV" button runs in the background (no need
///     to unlock or open the app) and sends power off; tapping the notification does the same.
///  4. A background refresh is requested for the end time; if iOS runs it soon enough, the TV goes off then too.
/// The phone has to be on the same Wi-Fi as the TV for any of these to reach it.
@MainActor
@Observable
final class SleepTimer {
    static let shared = SleepTimer()

    static let notificationID = "sleepTimer.end"
    static let category = "SLEEP_TIMER"
    static let turnOffAction = "SLEEP_TURN_OFF"
    static let extendAction = "SLEEP_EXTEND"
    static let refreshTaskID = "com.troydunn.clicker.sleeptimer"
    private static let endKey = "sleepTimer.endsAt"
    private static let lengthKey = "sleepTimer.minutes"
    private static let firedKey = "sleepTimer.firedAt"

    /// When the TV goes off; nil when no timer is running.
    private(set) var endsAt: Date? {
        didSet {
            if let endsAt { UserDefaults.standard.set(endsAt.timeIntervalSince1970, forKey: Self.endKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.endKey) }
        }
    }
    /// The last length picked (minutes), so the custom picker starts there.
    var lastMinutes: Int {
        didSet { UserDefaults.standard.set(lastMinutes, forKey: Self.lengthKey) }
    }
    var isRunning: Bool { endsAt != nil }

    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var bgTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let delegate = SleepNotificationDelegate()
    @ObservationIgnored private var attached = false

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.endKey)
        endsAt = saved > 0 ? Date(timeIntervalSince1970: saved) : nil
        let m = UserDefaults.standard.integer(forKey: Self.lengthKey)
        lastMinutes = m > 0 ? m : 30
    }

    // MARK: Setup (ClickerApp.init)

    func attach() {
        guard !attached else { return }
        attached = true
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let off = UNNotificationAction(identifier: Self.turnOffAction, title: "Turn Off TV", options: [])
        let more = UNNotificationAction(identifier: Self.extendAction, title: "15 More Minutes", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [off, more],
                                                                 intentIdentifiers: [], options: [])])
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Task { @MainActor in SleepTimer.shared.handleRefresh(task) }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SleepTimer.shared.didEnterBackground() }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SleepTimer.shared.catchUp() }
        }
        catchUp()
    }

    // MARK: Start / stop

    func start(minutes: Int) {
        let m = max(1, min(600, minutes))
        lastMinutes = m
        endsAt = Date().addingTimeInterval(TimeInterval(m * 60))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        armTick()
        scheduleNotification()
        scheduleRefresh()
        ClankerrWatchBridge.shared.sleepTimerChanged()
        TVStore.shared.show("Sleep timer: TV off in \(Self.label(minutes: m))")
    }

    func extend(minutes: Int) {
        let base = max(endsAt ?? Date(), Date())
        endsAt = base.addingTimeInterval(TimeInterval(minutes * 60))
        armTick()
        scheduleNotification()
        scheduleRefresh()
        ClankerrWatchBridge.shared.sleepTimerChanged()
    }

    func cancel(quiet: Bool = false) {
        endsAt = nil
        tick?.cancel(); tick = nil
        endBackgroundTask()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        ClankerrWatchBridge.shared.sleepTimerChanged()
        if !quiet { TVStore.shared.show("Sleep timer off") }
    }

    /// Time's up: power off, then clear the timer. Safe to call more than once.
    func fire() async {
        guard endsAt != nil else { return }
        endsAt = nil
        // Remembered so a late notification tap can't send power a second time (on some TVs power is a toggle).
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.firedKey)
        tick?.cancel(); tick = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        let ok = await TVStore.shared.powerOffNow()
        if !ok {
            // One retry: the TV socket may have gone stale while the phone slept.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            _ = await TVStore.shared.powerOffNow()
        }
        ClankerrWatchBridge.shared.sleepTimerChanged()
        TVStore.shared.show(ok ? "Sleep timer: turned off the TV" : "Sleep timer: couldn't reach the TV")
        endBackgroundTask()
    }

    /// Back in the app (or launched): fire a timer that ran out while iOS had the app paused, if it's recent.
    func catchUp() {
        guard let end = endsAt else { return }
        let late = Date().timeIntervalSince(end)
        if late >= 0 {
            // Up to 10 minutes late it still makes sense; much later you may have turned the TV back on yourself.
            if late <= 600 { Task { await fire() } } else { cancel(quiet: true); TVStore.shared.show("The sleep timer ended while Couch Remote was paused") }
        } else {
            armTick()
        }
    }

    // MARK: In-app timer and background time

    private func armTick() {
        tick?.cancel()
        guard let end = endsAt else { return }
        tick = Task { @MainActor [weak self] in
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled, let self, let now = self.endsAt, abs(now.timeIntervalSince(end)) < 1 else { return }
            await self.fire()
        }
    }

    private func didEnterBackground() {
        guard let end = endsAt else { return }
        // iOS gives a backgrounded app roughly 30 seconds. Only worth asking when the timer ends inside that.
        if end.timeIntervalSinceNow < 25 {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "Sleep timer") { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
        }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    // MARK: Notification and background refresh

    private func scheduleNotification() {
        guard let end = endsAt else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let c = UNMutableNotificationContent()
        c.title = "Sleep timer is up"
        c.body = "If your TV is still on, tap Turn Off TV. (Your phone needs to be on the same Wi-Fi as the TV.)"
        c.sound = nil
        c.categoryIdentifier = Self.category
        c.userInfo = ["sleepTimer": true]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: c, trigger: trigger))
    }

    private func scheduleRefresh() {
        guard let end = endsAt else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        let r = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        r.earliestBeginDate = end
        try? BGTaskScheduler.shared.submit(r)
    }

    private func handleRefresh(_ task: BGTask) {
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        guard let end = endsAt else { task.setTaskCompleted(success: true); return }
        let late = Date().timeIntervalSince(end)
        guard late >= 0 else { scheduleRefresh(); task.setTaskCompleted(success: true); return }
        guard late <= 3600 else { cancel(quiet: true); task.setTaskCompleted(success: true); return }
        Task { @MainActor in
            await self.fire()
            task.setTaskCompleted(success: true)
        }
    }

    /// Notification button or tap.
    func handleResponse(action: String) async {
        switch action {
        case Self.extendAction:
            // The timer already ran out (that's why the notification showed): start a fresh 15 minutes.
            if endsAt == nil || (endsAt ?? Date()) <= Date() { endsAt = nil; start(minutes: 15) } else { extend(minutes: 15) }
        case UNNotificationDismissActionIdentifier:
            return
        default:
            if endsAt == nil {
                // Already handled by the in-app timer or a background refresh in the last 15 minutes: nothing to do.
                let fired = UserDefaults.standard.double(forKey: Self.firedKey)
                if fired > 0, Date().timeIntervalSince1970 - fired < 900 { return }
                endsAt = Date()
            }
            await fire()
        }
    }

    static func label(minutes m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }
}

/// Receives the sleep timer notification's buttons, also when iOS starts the app in the background for them.
final class SleepNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // While the app is open the in-app timer already handles it.
        if notification.request.identifier == SleepTimer.notificationID {
            Task { @MainActor in await SleepTimer.shared.handleResponse(action: UNNotificationDefaultActionIdentifier) }
            completionHandler([])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.identifier == SleepTimer.notificationID else { completionHandler(); return }
        let action = response.actionIdentifier
        Task { @MainActor in
            await SleepTimer.shared.handleResponse(action: action)
            completionHandler()
        }
    }
}
