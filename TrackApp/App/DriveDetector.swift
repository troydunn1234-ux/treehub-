import Foundation
import CoreLocation
import CoreMotion
import UserNotifications
import UIKit
import Observation

/// Notices when you start driving (while nothing is being recorded) and offers to start a drive.
///
/// Battery: no continuous GPS. Significant-location-change monitoring wakes the app (cell-tower
/// level, nearly free), motion activity says "automotive", and only then a ~30 s GPS burst reads
/// the speed. If you're over the threshold twice in a row, you get "Start drive?".
@MainActor
@Observable
final class DriveDetector: NSObject, CLLocationManagerDelegate {
    static let shared = DriveDetector()

    nonisolated static let enabledKey = "autoDrive"
    nonisolated static let thresholdKey = "autoDriveMph"
    nonisolated static let lastPromptKey = "autoDriveLastPrompt"
    nonisolated static let lastDriveEndKey = "autoDriveLastEnd"
    nonisolated static let pendingStartKey = "pendingStartDrive"
    nonisolated static let permsAskedKey = "autoDrivePermsAsked"
    nonisolated static let alwaysAskedKey = "autoDriveAlwaysAsked"
    nonisolated static let alwaysCardKey = "autoDriveAlwaysCardShown"
    nonisolated static let defaultMph = 20.0
    nonisolated static let categoryID = "DRIVE_PROMPT"
    nonisolated static let startActionID = "START_DRIVE"
    nonisolated static let laterActionID = "NOT_NOW"
    nonisolated static let requestID = "drive-prompt"
    nonisolated static let startDriveNote = Notification.Name("RoamrStartDrive")

    private static let promptCooldown: TimeInterval = 20 * 60
    private static let afterDriveQuiet: TimeInterval = 10 * 60
    private static let burstLength: UInt64 = 30

    /// In-app banner ("Driving? Start drive") while Roamr is open.
    var showBanner = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var notificationsAllowed = true
    /// Bumped to re-evaluate the one-time "Set Location to Always" card.
    private var cardTick = 0

    /// Show the one-time card once we've asked for Always and iOS still says "While Using".
    var showAlwaysCard: Bool {
        _ = cardTick
        let d = UserDefaults.standard
        return enabled && !TrackDemo.isOn && authorization == .authorizedWhenInUse
            && d.bool(forKey: Self.alwaysAskedKey) && !d.bool(forKey: Self.alwaysCardKey)
    }

    func dismissAlwaysCard() {
        UserDefaults.standard.set(true, forKey: Self.alwaysCardKey)
        cardTick += 1
    }
    /// Set by the app: true while a route is being recorded.
    @ObservationIgnored var isTracking: @MainActor () -> Bool = { false }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var bursting = false
    @ObservationIgnored private var burstTask: Task<Void, Never>?
    @ObservationIgnored private var fastReadings = 0
    @ObservationIgnored private var lastBurst: Date?
    @ObservationIgnored private var wantsAlways = false
    @ObservationIgnored private var lastAutomotive: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false
        authorization = manager.authorizationStatus
    }

    // MARK: Settings

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var hasAlways: Bool { authorization == .authorizedAlways }

    var thresholdMph: Double {
        let v = UserDefaults.standard.double(forKey: Self.thresholdKey)
        return v > 0 ? v : Self.defaultMph
    }

    private var thresholdMps: Double { thresholdMph * 0.44704 }

    nonisolated static func registerCategory() {
        let start = UNNotificationAction(identifier: startActionID, title: "Start Drive", options: [.foreground])
        let later = UNNotificationAction(identifier: laterActionID, title: "Not now", options: [])
        let cat = UNNotificationCategory(identifier: categoryID, actions: [start, later], intentIdentifiers: [], options: [])
        let finishNow = UNNotificationAction(identifier: AutoFinish.finishActionID, title: "Finish now", options: [])
        let keep = UNNotificationAction(identifier: AutoFinish.keepActionID, title: "Keep going", options: [])
        let fin = UNNotificationCategory(identifier: AutoFinish.categoryID, actions: [finishNow, keep], intentIdentifiers: [], options: [])
        let done = UNNotificationCategory(identifier: DriveFinishedNotifier.categoryID, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat, fin, done])
    }

    /// Called when the toggle turns on: asks for notifications, Always location and motion.
    func enable() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsAllowed = granted
        wantsAlways = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()   // Always is asked right after (see delegate)
        case .authorizedWhenInUse:
            wantsAlways = false
            UserDefaults.standard.set(true, forKey: Self.alwaysAskedKey)
            manager.requestAlwaysAuthorization()
        default: break
        }
        if CMMotionActivityManager.isActivityAvailable() {
            // Triggers the Motion & Fitness prompt the first time.
            motion.queryActivityStarting(from: Date().addingTimeInterval(-60), to: Date(), to: .main) { _, _ in }
        }
        refresh()
    }

    /// Start or stop watching to match the toggle. Safe to call often.
    func refresh() {
        Task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            self.notificationsAllowed = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        }
        if enabled && !TrackDemo.isOn { startWatching() } else { stopWatching() }
    }

    /// Remember when a drive ended so we don't nag right after you park.
    func trackingEnded() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastDriveEndKey)
        showBanner = false
    }

    func dismissBanner() {
        withAnimationIfNeeded { showBanner = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastPromptKey)
    }

    // MARK: Watching

    private func startWatching() {
        guard !watching else { return }
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
        watching = true
        if authorization == .authorizedAlways, CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity, activity.automotive, activity.confidence != .low else { return }
                MainActor.assumeIsolated { self?.lastAutomotive = Date(); self?.maybeBurst() }
            }
        }
    }

    private func stopWatching() {
        guard watching else { return }
        watching = false
        manager.stopMonitoringSignificantLocationChanges()
        motion.stopActivityUpdates()
        endBurst()
    }

    private var quiet: Bool {
        if isTracking() { return true }
        let now = Date().timeIntervalSince1970
        let d = UserDefaults.standard
        if now - d.double(forKey: Self.lastPromptKey) < Self.promptCooldown { return true }
        if now - d.double(forKey: Self.lastDriveEndKey) < Self.afterDriveQuiet { return true }
        return false
    }

    /// A short GPS burst to read the speed. Never more often than once a minute.
    private func maybeBurst() {
        guard enabled, watching, !bursting, !quiet else { return }
        // At most one short GPS check every 3 minutes, so the location arrow isn't constantly on.
        if let lastBurst, Date().timeIntervalSince(lastBurst) < 180 { return }
        lastBurst = Date()
        bursting = true
        fastReadings = 0
        if authorization == .authorizedAlways { manager.allowsBackgroundLocationUpdates = true }
        manager.startUpdatingLocation()
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.burstLength * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.endBurst()
        }
    }

    private func endBurst() {
        burstTask?.cancel()
        burstTask = nil
        guard bursting else { return }
        bursting = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func handle(_ loc: CLLocation) {
        guard bursting else { return }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100,
              abs(loc.timestamp.timeIntervalSinceNow) < 15, loc.speed >= 0 else { return }
        if loc.speed >= thresholdMps {
            fastReadings += 1
            if fastReadings >= 2 { endBurst(); prompt(speed: loc.speed) }
        } else {
            fastReadings = 0
        }
    }

    private func prompt(speed: Double) {
        guard !quiet else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastPromptKey)
        if UIApplication.shared.applicationState == .active {
            withAnimationIfNeeded { showBanner = true }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "🛻 Looks like you're driving"
        content.body = "Start drive? Tap to start tracking your route."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Asks the app to start a drive (from the notification or the banner).
    nonisolated static func requestStartDrive() {
        UserDefaults.standard.set(true, forKey: pendingStartKey)
        NotificationCenter.default.post(name: startDriveNote, object: nil)
    }

    private func withAnimationIfNeeded(_ change: () -> Void) {
        change()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locs = locations
        Task { @MainActor in
            if self.bursting {
                for l in locs { self.handle(l) }
            } else {
                // Woken by a significant location change: only check speed if the motion chip
                // says we're in a vehicle (walking around town shouldn't turn GPS on).
                if let t = self.lastAutomotive, Date().timeIntervalSince(t) < 120 { self.maybeBurst() }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse && self.wantsAlways {
                self.wantsAlways = false
                UserDefaults.standard.set(true, forKey: Self.alwaysAskedKey)
                self.manager.requestAlwaysAuthorization()
            }
            self.cardTick += 1
            self.watching = false
            self.manager.stopMonitoringSignificantLocationChanges()
            self.motion.stopActivityUpdates()
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Routes taps on the "Start drive?" notification into the app.
final class DriveNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DriveNotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.categoryIdentifier
        if id == DriveDetector.categoryID && response.actionIdentifier != DriveDetector.laterActionID
            && response.actionIdentifier != UNNotificationDismissActionIdentifier {
            DispatchQueue.main.async { DriveDetector.requestStartDrive() }
        } else if id == DriveFinishedNotifier.categoryID {
            if let raw = response.notification.request.content.userInfo[DriveFinishedNotifier.activityKey] as? String {
                DispatchQueue.main.async { DriveFinishedNotifier.requestOpen(raw) }
            }
        } else if id == AutoFinish.categoryID {
            let action = response.actionIdentifier
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if action == AutoFinish.keepActionID { AutoFinish.shared.keepGoing() }
                    else { AutoFinish.shared.finishNow() }   // "Finish now" or a tap on the banner
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}


/// Finishes a recording on its own after you've been stopped for a while: asks first
/// (banner in the app, or a notification with "Finish now" / "Keep going"), then finishes
/// 60 s later if you don't answer. The idle tail is trimmed off either way.
@MainActor
@Observable
final class AutoFinish {
    static let shared = AutoFinish()
    nonisolated static let categoryID = "AUTO_FINISH"
    nonisolated static let finishActionID = "FINISH_NOW"
    nonisolated static let keepActionID = "KEEP_GOING"
    nonisolated static let requestID = "auto-finish"
    /// Posted when the recording should be finished (the Track screen does the saving).
    nonisolated static let finishNote = Notification.Name("roamr.autoFinish")

    /// Countdown shown in the in-app banner (nil = not asking).
    private(set) var secondsLeft: Int?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tracker: RouteTracker?

    func attach(_ t: RouteTracker) { tracker = t }

    /// Call whenever the tracker's `autoFinishDue` flips to true.
    func ask() {
        guard secondsLeft == nil else { return }
        secondsLeft = 60
        if UIApplication.shared.applicationState != .active {
            let content = UNMutableNotificationContent()
            content.title = "Looks like your \(tracker?.kind.title.lowercased() ?? "drive") ended"
            content.body = "Finishing in 60s. Tap Keep going if you're not done."
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.interruptionLevel = .timeSensitive
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil))
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let s = secondsLeft else { stop(); return }
        guard let t = tracker, t.isActive else { stop(); return }
        if !t.autoFinishDue { stop(); return }   // started moving again
        if s <= 1 { finishNow() } else { secondsLeft = s - 1 }
    }

    func keepGoing() {
        tracker?.dismissAutoFinish()
        stop()
    }

    func finishNow() {
        stop()
        NotificationCenter.default.post(name: Self.finishNote, object: nil)
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        secondsLeft = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }
}


/// "Drive finished" notification after auto-finish saves a drive on its own. Tapping it opens that drive.
/// Off/on from Settings (on by default).
final class DriveFinishedNotifier {
    static let shared = DriveFinishedNotifier()
    static let enabledKey = "notifyDriveFinished"
    static let categoryID = "DRIVE_FINISHED"
    static let activityKey = "activityID"
    static let pendingOpenKey = "pendingOpenActivity"
    static let requestID = "drive-finished"
    /// Posted when the app should show the activity saved under `pendingOpenKey`.
    static let openActivityNote = Notification.Name("RoamrOpenActivity")

    private var token: NSObjectProtocol?

    /// Starts listening for saved recordings. Safe to call more than once.
    func start() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(forName: .activitySaved, object: nil, queue: .main) { note in
            guard let info = note.userInfo,
                  let auto = info["auto"] as? Bool, auto,
                  let id = info["id"] as? String,
                  let kind = info["kind"] as? String,
                  let distance = info["distanceM"] as? Double,
                  let seconds = info["seconds"] as? Double else { return }
            DriveFinishedNotifier.notify(id: id, kind: kind, distanceM: distance, seconds: seconds)
        }
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func notify(id: String, kind: String, distanceM: Double, seconds: Double) {
        guard enabled, !TrackDemo.isOn else { return }
        let title = (ActivityKind(rawValue: kind) ?? .drive).title
        let content = UNMutableNotificationContent()
        content.title = "\(title) finished"
        content.body = "\(Format.distance(distanceM)) in \(Format.duration(seconds)). Tap to see the route."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [activityKey: id]
        let req = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Asks the app to show an activity (from a tap on the notification).
    static func requestOpen(_ id: String) {
        UserDefaults.standard.set(id, forKey: pendingOpenKey)
        NotificationCenter.default.post(name: openActivityNote, object: nil)
    }
}
