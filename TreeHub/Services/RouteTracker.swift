import Foundation
import CoreLocation
import CoreMotion
import Observation

/// Records a route with GPS, keeps going with the phone locked, and survives the app being closed.
@MainActor
@Observable
final class RouteTracker: NSObject, CLLocationManagerDelegate {
    enum State: String, Codable { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var kind: ActivityKind = .walk
    private(set) var points: [RoutePoint] = []
    private(set) var distance: Double = 0
    private(set) var elevGain: Double = 0
    private(set) var maxSpeed: Double = 0
    private(set) var movingSec: Double = 0
    private(set) var currentSpeed: Double = 0
    private(set) var accuracy: Double = -1
    private(set) var startDate: Date?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var recoveredFromCrash = false
    private(set) var motionCounts: [ActivityKind: Int] = [:]

    private(set) var accumulated: TimeInterval = 0
    private(set) var resumedAt: Date?
    @ObservationIgnored private var elevRef: Double?
    @ObservationIgnored private var lastAccepted: CLLocation?
    @ObservationIgnored private var unsavedCount = 0

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    @ObservationIgnored private var backgroundSession: AnyObject?   // CLBackgroundActivitySession

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        applyKindSettings()
        restoreIfNeeded()
    }

    // MARK: - Derived

    var elapsed: TimeInterval {
        guard let resumedAt, state == .recording else { return accumulated }
        return accumulated + Date().timeIntervalSince(resumedAt)
    }

    var isActive: Bool { state != .idle }
    var lastCoordinate: CLLocationCoordinate2D? { points.last?.coordinate }
    var canTrack: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var denied: Bool { authorization == .denied || authorization == .restricted }

    /// Best guess from the phone's motion chip, falling back to speed.
    var suggestedKind: ActivityKind {
        let sorted = motionCounts.sorted { $0.value > $1.value }
        if let top = sorted.first, top.value >= 3 {
            if top.key == .walk && elevGain > 90 { return .hike }
            return top.key
        }
        let avg = movingSec > 0 ? distance / movingSec : 0
        if maxSpeed > 13 || avg > 9 { return .drive }   // > ~30 mph
        if avg > 4.2 { return .bike }
        if avg > 2.3 { return .run }
        return elevGain > 90 ? .hike : kind
    }

    // MARK: - Controls

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start(kind: ActivityKind) {
        guard state == .idle else { return }
        reset()
        self.kind = kind
        applyKindSettings()
        startDate = Date()
        resumedAt = Date()
        state = .recording
        beginUpdates()
        startMotion()
        persist()
    }

    func pause() {
        guard state == .recording else { return }
        if let resumedAt { accumulated += Date().timeIntervalSince(resumedAt) }
        resumedAt = nil
        state = .paused
        lastAccepted = nil
        manager.stopUpdatingLocation()
        persist()
    }

    func resume() {
        guard state == .paused else { return }
        resumedAt = Date()
        state = .recording
        beginUpdates()
        persist()
    }

    /// Stops recording and returns a filled-in Activity (not yet inserted into the database).
    func finish() -> Activity? {
        guard state != .idle, let startDate else { return nil }
        if state == .recording, let resumedAt { accumulated += Date().timeIntervalSince(resumedAt) }
        stopUpdates()
        let a = Activity()
        a.kind = kind
        a.start = startDate
        a.end = startDate.addingTimeInterval(max(accumulated, 1))
        a.distanceM = distance
        a.movingSec = min(movingSec, accumulated)
        a.elevGainM = elevGain
        a.maxSpeed = maxSpeed
        a.route = Self.simplify(points, maxCount: 4000)
        reset()
        return a
    }

    /// Change the activity type while recording (e.g. a walk that became a hike).
    func setKind(_ k: ActivityKind) {
        kind = k
        applyKindSettings()
        persist()
    }

    func discard() {
        stopUpdates()
        reset()
    }

    // MARK: - Private

    private func applyKindSettings() {
        switch kind {
        case .drive:
            manager.activityType = .automotiveNavigation
            manager.distanceFilter = 15
        case .bike:
            manager.activityType = .otherNavigation
            manager.distanceFilter = 8
        default:
            manager.activityType = .fitness
            manager.distanceFilter = 4
        }
    }

    private func beginUpdates() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if #available(iOS 17.0, *), backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if #available(iOS 17.0, *), let s = backgroundSession as? CLBackgroundActivitySession {
            s.invalidate()
        }
        backgroundSession = nil
        motion.stopActivityUpdates()
        clearPersisted()
    }

    private func reset() {
        state = .idle
        points = []
        distance = 0
        elevGain = 0
        maxSpeed = 0
        movingSec = 0
        currentSpeed = 0
        accumulated = 0
        resumedAt = nil
        startDate = nil
        elevRef = nil
        lastAccepted = nil
        motionCounts = [:]
        recoveredFromCrash = false
    }

    private func startMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motion.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity, activity.confidence != .low else { return }
            let k: ActivityKind?
            if activity.automotive { k = .drive }
            else if activity.cycling { k = .bike }
            else if activity.running { k = .run }
            else if activity.walking { k = .walk }
            else { k = nil }
            guard let k else { return }
            MainActor.assumeIsolated {
                self?.motionCounts[k, default: 0] += 1
            }
        }
    }

    private func accept(_ loc: CLLocation) {
        guard state == .recording else { return }
        // Throw away stale or fuzzy fixes.
        guard loc.horizontalAccuracy >= 0, abs(loc.timestamp.timeIntervalSinceNow) < 15 else { return }
        let maxAcc: Double = kind == .drive ? 65 : 35
        accuracy = loc.horizontalAccuracy
        guard loc.horizontalAccuracy <= maxAcc else { return }

        if let last = lastAccepted {
            let d = loc.distance(from: last)
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else { return }
            let v = d / dt
            if v > 95 { return }                      // impossible jump (> 210 mph)
            if d < max(2, loc.horizontalAccuracy * 0.4) && v < 0.4 { return } // standing still jitter
            distance += d
            if v > 0.5 && dt < 300 { movingSec += dt }
            let s = loc.speed >= 0 ? loc.speed : v
            currentSpeed = s
            if s < 95 { maxSpeed = max(maxSpeed, s) }
        } else {
            currentSpeed = max(0, loc.speed)
        }

        if loc.verticalAccuracy >= 0 && loc.verticalAccuracy < 20 {
            if let ref = elevRef {
                if loc.altitude - ref >= 3 { elevGain += loc.altitude - ref; elevRef = loc.altitude }
                else if ref - loc.altitude >= 3 { elevRef = loc.altitude }
            } else {
                elevRef = loc.altitude
            }
        }

        lastAccepted = loc
        points.append(RoutePoint(loc))
        unsavedCount += 1
        if unsavedCount >= 10 { persist() }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for loc in locations { self.accept(loc) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.state == .recording && (status == .authorizedWhenInUse || status == .authorizedAlways) {
                self.beginUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary GPS errors (e.g. in a tunnel) are ignored; updates continue when signal returns.
    }

    // MARK: - Crash / quit safety

    private struct Snapshot: Codable {
        var state: State
        var kind: ActivityKind
        var startDate: Date
        var accumulated: TimeInterval
        var resumedAt: Date?
        var points: [RoutePoint]
        var distance: Double
        var elevGain: Double
        var maxSpeed: Double
        var movingSec: Double
    }

    private static var snapshotURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("active-recording.json")
    }

    func persist() {
        unsavedCount = 0
        guard state != .idle, let startDate else { return }
        let snap = Snapshot(state: state, kind: kind, startDate: startDate, accumulated: accumulated,
                            resumedAt: resumedAt, points: points, distance: distance,
                            elevGain: elevGain, maxSpeed: maxSpeed, movingSec: movingSec)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: Self.snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func clearPersisted() {
        try? FileManager.default.removeItem(at: Self.snapshotURL)
    }

    private func restoreIfNeeded() {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        kind = snap.kind
        applyKindSettings()
        startDate = snap.startDate
        points = snap.points
        distance = snap.distance
        elevGain = snap.elevGain
        maxSpeed = snap.maxSpeed
        movingSec = snap.movingSec
        accumulated = snap.accumulated
        // If the app was closed mid-recording, count time up to the last saved point, then wait paused.
        if snap.state == .recording, let r = snap.resumedAt {
            let lastT = snap.points.last.map { Date(timeIntervalSince1970: $0.t) } ?? r
            accumulated += max(0, lastT.timeIntervalSince(r))
        }
        resumedAt = nil
        state = .paused
        recoveredFromCrash = true
    }

    // MARK: - Helpers

    /// Keeps the route light for storage while keeping its shape.
    static func simplify(_ pts: [RoutePoint], maxCount: Int) -> [RoutePoint] {
        guard pts.count > maxCount, maxCount > 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { pts[min(pts.count - 1, Int((Double($0) * step).rounded()))] }
    }
}

/// One-shot "where am I right now" used when logging a hug.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var waitingForAuth = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func current() async -> CLLocation? {
        if continuation != nil { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                waitingForAuth = true
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            default:
                finish(nil)
            }
            // Never hang the UI: give up after 15 s.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finish(nil)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(returning: loc)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let best = locations.min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        Task { @MainActor in self.finish(best) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.waitingForAuth, status != .notDetermined else { return }
            self.waitingForAuth = false
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else {
                self.finish(nil)
            }
        }
    }
}
