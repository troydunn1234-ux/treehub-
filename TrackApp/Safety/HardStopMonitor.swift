import Foundation
import CoreMotion
import CoreLocation
import UIKit
import UserNotifications
import AudioToolbox

/// Hard-stop alert: while a DRIVE is recording (and only then), watches for a likely crash —
/// a big jolt (userAcceleration over ~3 g) together with the speed falling from over 25 mph to
/// about zero within a couple of seconds. Then it asks "Are you OK?" for 30 seconds and, if
/// nobody answers, offers a pre-filled text to the emergency contact with a map link.
///
/// It never turns on location by itself: it reads the speed and position the drive recording
/// already has. The motion sensor is only sampled while a drive is recording with this on.
/// Not a replacement for the iPhone's built-in Crash Detection or for calling 911.
@MainActor
@Observable
final class HardStopMonitor {
    static let shared = HardStopMonitor()

    nonisolated static let enabledKey = "hardStop.enabled"
    nonisolated static let contactNameKey = "hardStop.contactName"
    nonisolated static let contactPhoneKey = "hardStop.contactPhone"
    nonisolated static let categoryID = "HARD_STOP"
    nonisolated static let okActionID = "HARD_STOP_OK"
    nonisolated static let helpActionID = "HARD_STOP_HELP"
    nonisolated static let askRequestID = "hard-stop-ask"
    nonisolated static let noAnswerRequestID = "hard-stop-no-answer"

    /// Thresholds (tuned to be conservative; a pothole or a dropped phone alone is not enough).
    nonisolated static let spikeG = 3.0               // userAcceleration magnitude, in g
    nonisolated static let fastMps = 25 * 0.44704     // 25 mph
    nonisolated static let stoppedMps = 1.3           // about 3 mph: "about zero" for GPS speed
    nonisolated static let countdownSeconds = 30

    enum Phase: Equatable { case idle, asking, help }

    private(set) var phase: Phase = .idle
    private(set) var secondsLeft = HardStopMonitor.countdownSeconds
    /// Where the drive was when the hard stop happened.
    private(set) var location: CLLocationCoordinate2D?
    /// Monitoring right now (drive recording + setting on).
    private(set) var watching = false

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var contactName: String? { UserDefaults.standard.string(forKey: Self.contactNameKey) }
    var contactPhone: String? { UserDefaults.standard.string(forKey: Self.contactPhoneKey) }

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let queue: OperationQueue = {
        let q = OperationQueue(); q.name = "roamr.hardstop"; q.maxConcurrentOperationCount = 1; return q
    }()
    @ObservationIgnored private weak var tracker: RouteTracker?
    @ObservationIgnored private var speeds: [(t: Date, v: Double)] = []
    @ObservationIgnored private var spikeAt: Date?
    @ObservationIgnored private var sampler: Timer?
    @ObservationIgnored private var countdown: Timer?
    @ObservationIgnored private var lastSpikeSent = Date.distantPast

    nonisolated static func makeCategory() -> UNNotificationCategory {
        let ok = UNNotificationAction(identifier: okActionID, title: String(localized: "I'm OK"), options: [])
        let help = UNNotificationAction(identifier: helpActionID, title: String(localized: "Get help"), options: [.foreground])
        return UNNotificationCategory(identifier: categoryID, actions: [help, ok], intentIdentifiers: [], options: [])
    }

    func setContact(name: String, phone: String) {
        UserDefaults.standard.set(name, forKey: Self.contactNameKey)
        UserDefaults.standard.set(phone, forKey: Self.contactPhoneKey)
    }

    func clearContact() {
        UserDefaults.standard.removeObject(forKey: Self.contactNameKey)
        UserDefaults.standard.removeObject(forKey: Self.contactPhoneKey)
    }

    // MARK: Watching (drives only)

    /// Call whenever the recording state, the activity kind or the setting changes.
    func update(tracker: RouteTracker) {
        self.tracker = tracker
        let should = enabled && tracker.state == .recording && tracker.kind == .drive && !TrackDemo.isOn
        if should && !watching { startWatching() } else if !should && watching { stopWatching() }
    }

    private func startWatching() {
        guard motion.isDeviceMotionAvailable else { return }
        watching = true
        speeds = []
        spikeAt = nil
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: queue) { [weak self] m, _ in
            guard let a = m?.userAcceleration else { return }
            let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard g > HardStopMonitor.spikeG else { return }
            Task { @MainActor in self?.spike() }
        }
        // Speed comes from the drive recording's own GPS fixes (about once a second).
        sampler = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    private func stopWatching() {
        watching = false
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        sampler?.invalidate(); sampler = nil
        speeds = []
        spikeAt = nil
    }

    private func spike() {
        guard watching, phase == .idle, spikeAt == nil else { return }
        spikeAt = Date()
        evaluate()
    }

    private func sample() {
        guard let tracker, watching else { return }
        let now = Date()
        speeds.append((now, max(0, tracker.currentSpeed)))
        speeds.removeAll { now.timeIntervalSince($0.t) > 15 }
        if spikeAt != nil { evaluate() }
    }

    /// A jolt counts when, around it, the speed went from over 25 mph to about zero within ~2 s
    /// (allowing a little slack for the once-a-second GPS speed).
    private func evaluate() {
        guard let at = spikeAt else { return }
        let now = Date()
        if now.timeIntervalSince(at) > 6 { spikeAt = nil; return }
        let before = speeds.filter { $0.t <= at.addingTimeInterval(1) && at.timeIntervalSince($0.t) <= 4 }
        guard let fast = before.filter({ $0.v > Self.fastMps }).last else {
            // Not fast just before the jolt: not a crash-like stop.
            if now.timeIntervalSince(at) > 1 { spikeAt = nil }
            return
        }
        let current = max(0, tracker?.currentSpeed ?? 0)
        if current < Self.stoppedMps && now.timeIntervalSince(fast.t) <= 6 {
            spikeAt = nil
            trigger()
        }
    }

    // MARK: Alert

    /// Starts the "Are you OK?" countdown (also used by the Test button in Settings).
    func trigger(test: Bool = false) {
        guard phase == .idle else { return }
        guard test || Date().timeIntervalSince(lastSpikeSent) > 120 else { return }
        lastSpikeSent = Date()
        location = tracker?.lastCoordinate ?? RoamrContext.tracker?.lastCoordinate
        secondsLeft = Self.countdownSeconds
        phase = .asking
        HardStopWindow.shared.show()
        alarmTick()
        scheduleNotifications()
        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard phase == .asking else { countdown?.invalidate(); return }
        secondsLeft -= 1
        if secondsLeft <= 0 {
            countdown?.invalidate(); countdown = nil
            getHelp()
        } else {
            alarmTick()
        }
    }

    /// Loud haptic + alert sound once a second while asking.
    private func alarmTick() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    func imOK() {
        countdown?.invalidate(); countdown = nil
        phase = .idle
        cancelNotifications()
        HardStopWindow.shared.hide()
    }

    /// No answer, or "Get help" tapped: show the help screen and open the pre-filled text.
    func getHelp() {
        countdown?.invalidate(); countdown = nil
        let wasAsking = phase == .asking
        phase = .help
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.askRequestID])
        HardStopWindow.shared.show()
        if UIApplication.shared.applicationState == .active {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.noAnswerRequestID])
            if wasAsking || contactPhone != nil { composeMessage() }
        }
    }

    func close() {
        countdown?.invalidate(); countdown = nil
        phase = .idle
        cancelNotifications()
        HardStopWindow.shared.hide()
    }

    /// Text for the emergency contact (iOS never lets an app send it silently; you tap Send).
    var messageBody: String {
        var s = String(localized: "I may have been in a car crash and didn't respond to my phone.")
        if let c = location {
            let lat = String(format: "%.5f", c.latitude), lng = String(format: "%.5f", c.longitude)
            s += " " + String(localized: "My location:") + " https://maps.google.com/?q=\(lat),\(lng)"
        }
        s += " " + String(localized: "(Sent from Roamr's hard-stop alert.)")
        return s
    }

    func composeMessage() {
        HardStopWindow.shared.composeText(to: contactPhone, body: messageBody)
    }

    // MARK: Notifications (for when the phone is locked or Roamr is in the background)

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        if UIApplication.shared.applicationState != .active {
            let ask = UNMutableNotificationContent()
            ask.title = String(localized: "Hard stop detected. Are you OK?")
            ask.body = String(localized: "Open Roamr within 30 seconds, or tap Get help to text your emergency contact.")
            ask.sound = .defaultCritical
            ask.categoryIdentifier = Self.categoryID
            ask.interruptionLevel = .timeSensitive
            center.add(UNNotificationRequest(identifier: Self.askRequestID, content: ask, trigger: nil))
        }
        let late = UNMutableNotificationContent()
        late.title = String(localized: "No answer after a hard stop")
        late.body = contactName.map { String(localized: "Tap to text \($0) your location. iOS needs you to press Send.") }
            ?? String(localized: "Tap to share your location. iOS needs you to press Send.")
        late.sound = .defaultCritical
        late.categoryIdentifier = Self.categoryID
        late.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(Self.countdownSeconds), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.noAnswerRequestID, content: late, trigger: trigger))
    }

    private func cancelNotifications() {
        let ids = [Self.askRequestID, Self.noAnswerRequestID]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// From DriveNotificationRouter: a tap or an action on one of the hard-stop notifications.
    func handleNotification(action: String) {
        if action == Self.okActionID { imOK(); return }
        countdown?.invalidate(); countdown = nil
        phase = .help
        cancelNotifications()
        HardStopWindow.shared.show()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.composeMessage()
        }
    }
}
