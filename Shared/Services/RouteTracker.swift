import Foundation
import CoreLocation
import CoreMotion
import UIKit
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
    /// Becomes the saved Activity's id, so things logged mid-recording (like hugs) can point at it.
    private(set) var sessionID = UUID()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var recoveredFromCrash = false
    private(set) var motionCounts: [ActivityKind: Int] = [:]
    /// Paused by the app because you stopped moving (GPS keeps running so it can resume itself).
    private(set) var autoPaused = false
    /// When you last stopped moving while recording (nil while moving). Drives auto-finish from this.
    private(set) var idleSince: Date?
    /// Set when you've been stopped longer than the auto-finish setting; the app asks, then finishes.
    private(set) var autoFinishDue = false
    /// Idle seconds dropped from the end of the last finished recording (shown once in the summary).
    private(set) var lastTrimmedSec: Double = 0
    @ObservationIgnored private var lastMovingAt: Date?
    /// Direction of travel in degrees from north, -1 when unknown.
    private(set) var course: Double = -1
    /// Posted limit for the road you're on (drives only).
    private(set) var speedLimit: SpeedLimitService.Limit?
    @ObservationIgnored private let limits = SpeedLimitService()
    @ObservationIgnored private var overWarned = false
    /// Lane changes on this drive, estimated from phone motion.
    private(set) var laneChanges: [LaneChange] = []
    var cutCount: Int { laneChanges.filter(\.quick).count }
    @ObservationIgnored private let gyro = CMMotionManager()
    @ObservationIgnored private var laneDetector = LaneChangeDetector()
    /// Road-relative detector (used whenever a map road is matched): ignores curves.
    @ObservationIgnored private var roadLaneDetector = RoadLaneDetector()
    @ObservationIgnored private var roadGeo: SpeedLimitService.RoadGeometry?
    /// How much the road ahead bends over the next ~200 m (degrees, + = left), for the lane HUD.
    private(set) var roadBend: Double = 0
    /// The road is curving here (so the HUD can say CURVE instead of guessing lane changes).
    private(set) var onCurve = false

    /// Live lane picture for the lane HUD (drives only). Lane 0 is the leftmost lane going your way.
    /// GPS can't see lanes, so the starting lane is a guess; lane changes from the motion sensors
    /// move it, turns re-anchor it, and you can tap the HUD to correct it.
    struct LaneShift: Equatable {
        let id = UUID(); let from: Int; let to: Int; let left: Bool; let quick: Bool; let at: Date
        /// You tapped the lane yourself (no "LANE CHANGE" pill for these).
        var manual = false
    }
    private(set) var laneCount = 2
    private(set) var laneIndex = 1
    private(set) var laneCountEstimated = true
    private(set) var lastLaneShift: LaneShift?
    @ObservationIgnored private var laneCourses: [(t: Double, c: Double)] = []
    @ObservationIgnored private var laneTurnCooldown = 0.0
    @ObservationIgnored private var demoLaneTimer: Timer?
    @ObservationIgnored private var demoLaneStep = 0
    @ObservationIgnored private var laneAnchored = false

    /// Typical starting lane: second from the right on 3+ lanes, rightmost on 2.
    private static func anchorLane(_ count: Int) -> Int { count >= 3 ? count - 2 : count - 1 }

    /// You tapped a lane on the HUD: that's where you are.
    func setLane(_ i: Int) {
        let to = max(0, min(laneCount - 1, i))
        laneAnchored = true
        guard to != laneIndex else { return }
        lastLaneShift = LaneShift(from: laneIndex, to: to, left: to < laneIndex, quick: false, at: Date(), manual: true)
        laneIndex = to
    }

    /// A confirmed lane change from either detector.
    private func recordLaneChange(_ e: LaneChangeDetector.Event) {
        guard let here = points.last else { return }
        laneChanges.append(LaneChange(t: e.t, lat: here.lat, lng: here.lng, left: e.left, speed: e.speed, quick: e.quick))
        applyLaneChange(left: e.left, quick: e.quick)
        if e.quick { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6) }
    }

    /// New matched road shape from the latest fix.
    private func updateRoadShape(_ g: SpeedLimitService.RoadGeometry?) {
        let isNew = g != nil && g?.at != roadGeo?.at
        roadGeo = g
        guard let g else {
            if roadBend != 0 { roadBend = 0 }
            if onCurve { onCurve = false }
            return
        }
        let bend = (-LaneMath.signedAngle(g.bearingAhead200, g.bearing)).rounded()
        if bend != roadBend { roadBend = bend }
        let curving = abs(g.curvatureWide) > 1.0 / 700 || abs(bend) >= 12
        if curving != onCurve { onCurve = curving }
        if isNew, let e = roadLaneDetector.addFix(t: g.at.timeIntervalSince1970, crossTrack: g.crossTrack, accuracy: g.accuracy) {
            recordLaneChange(e)
        }
    }

    private func applyLaneChange(left: Bool, quick: Bool) {
        var to = laneIndex + (left ? -1 : 1)
        if to < 0 || to >= laneCount {
            // Motion says you changed lanes but we thought you were at the edge: the lane count
            // (or our guess of your lane) was off. Grow the road if it's a guess, else shift.
            if laneCountEstimated && laneCount < 6 {
                laneCount += 1
                if to < 0 { laneIndex += 1; to = 0 }
            } else {
                to = max(0, min(laneCount - 1, to))
            }
        }
        guard to != laneIndex else { return }
        lastLaneShift = LaneShift(from: laneIndex, to: to, left: left, quick: quick, at: Date())
        laneIndex = to
    }

    private func updateLaneCount(_ raw: Int?, estimated: Bool) {
        guard let raw, raw > 0, demoLaneTimer == nil else { return }
        let n = min(raw, 8)
        laneCountEstimated = estimated
        if !laneAnchored {
            // First real road of the drive: start in the usual lane for that many lanes.
            laneAnchored = true
            laneCount = n
            laneIndex = Self.anchorLane(n)
            return
        }
        guard n != laneCount else { return }
        // Keep your distance from the right edge (merges usually drop the left or right lane;
        // right-relative is the better guess for exits/on-ramps).
        let fromRight = laneCount - 1 - laneIndex
        laneCount = n
        laneIndex = max(0, min(n - 1, n - 1 - fromRight))
    }

    /// A real turn (not a curve) puts you in the outside lane you turned into.
    private func checkTurnForLanes(_ c: Double) {
        let t = Date().timeIntervalSince1970
        laneCourses.append((t, c))
        laneCourses.removeAll { t - $0.t > 8 }
        guard t > laneTurnCooldown, let old = laneCourses.first, t - old.t > 2 else { return }
        var d = (c - old.c).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        guard abs(d) > 60 else { return }
        // Still lined up with the matched road? Then the road bent (a sweeping curve or
        // interchange), you didn't turn off it, so keep your lane.
        if let g = roadGeo, Date().timeIntervalSince(g.at) < 3, abs(LaneMath.signedAngle(c, g.bearing)) < 25 { return }
        laneTurnCooldown = t + 8
        laneCourses.removeAll()
        laneIndex = d > 0 ? laneCount - 1 : 0   // right turn → right lane, left turn → left lane
    }

    private func resetLanes() {
        laneCount = 2; laneIndex = 1; laneCountEstimated = true; lastLaneShift = nil
        laneCourses = []; laneTurnCooldown = 0; laneAnchored = false
        demoLaneTimer?.invalidate(); demoLaneTimer = nil
    }

    /// Screenshots (-demo -autodrive): the simulator has no gyro, so wiggle lanes every ~4 s.
    private func startDemoLanes() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo"), args.contains("-autodrive"), demoLaneTimer == nil else { return }
        if laneCount < 4 { laneCount = 4; laneIndex = 2; laneAnchored = true }
        demoLaneStep = 0
        demoLaneTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .recording, self.kind == .drive else { return }
                self.demoLaneStep += 1
                let step = self.demoLaneStep
                let left = (step / 2) % 2 == 0
                let quick = step % 3 == 0
                self.applyLaneChange(left: left, quick: quick)
                if let here = self.points.last {
                    self.laneChanges.append(LaneChange(t: Date().timeIntervalSince1970, lat: here.lat, lng: here.lng,
                                                       left: left, speed: self.currentSpeed, quick: quick))
                }
            }
        }
    }

    /// More than 3 mph over a known limit right now.
    var isOverLimit: Bool {
        guard kind == .drive, state == .recording, let l = speedLimit else { return false }
        return currentSpeed > l.mps + 1.34
    }

    private(set) var accumulated: TimeInterval = 0
    private(set) var resumedAt: Date?
    @ObservationIgnored private var elevRef: Double?
    @ObservationIgnored private var lastAccepted: CLLocation?
    @ObservationIgnored private var unsavedCount = 0
    @ObservationIgnored private var slowSince: Date?
    @ObservationIgnored private var fastFixes = 0
    @ObservationIgnored private var lastRaw: CLLocation?
    @ObservationIgnored private var splitsAnnounced = 0
    @ObservationIgnored private var lastSplitElapsed: TimeInterval = 0
    @ObservationIgnored private var stillTimer: Timer?

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
        // Re-attach the Live Activity for a restored recording, or clear an orphaned one.
        LiveActivityController.shared.sync(with: self)
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
        sessionID = UUID()
        startDate = Date()
        resumedAt = Date()
        state = .recording
        beginUpdates()
        startMotion()
        persist()
        if let startDate { LiveActivityController.shared.start(kind: kind, startDate: startDate) }
    }

    func pause() {
        if state == .paused && autoPaused {
            // Turning an auto-pause into a manual one: stop GPS and never resume on our own.
            autoPaused = false
            lastAccepted = nil
            manager.stopUpdatingLocation()
            persist()
            LiveActivityController.shared.update(tracker: self, force: true)
            return
        }
        guard state == .recording else { return }
        if let resumedAt { accumulated += Date().timeIntervalSince(resumedAt) }
        resumedAt = nil
        state = .paused
        autoPaused = false
        lastAccepted = nil
        slowSince = nil
        manager.stopUpdatingLocation()
        persist()
        LiveActivityController.shared.update(tracker: self, force: true)
    }

    func resume() {
        guard state == .paused else { return }
        let wasAuto = autoPaused
        resumedAt = Date()
        state = .recording
        autoPaused = false
        slowSince = nil
        fastFixes = 0
        if !wasAuto { beginUpdates() }
        persist()
        LiveActivityController.shared.update(tracker: self, force: true)
    }

    /// Below this speed (m/s) you count as stopped for auto-pause.
    nonisolated static func autoPauseThreshold(for kind: ActivityKind) -> Double? {
        switch kind {
        case .drive: return nil
        case .run, .bike: return 1.0
        default: return 0.4
        }
    }

    private var autoPauseEnabled: Bool {
        TrackPrefs.autoPause && Self.autoPauseThreshold(for: kind) != nil
    }

    private func autoPause(since: Date) {
        guard state == .recording else { return }
        if let resumedAt { accumulated += max(0, since.timeIntervalSince(resumedAt)) }
        resumedAt = nil
        state = .paused
        autoPaused = true
        fastFixes = 0
        currentSpeed = 0
        persist()
        LiveActivityController.shared.update(tracker: self, force: true)
    }

    /// Handles auto-pause / auto-resume for each raw fix. Returns false if the fix should not be recorded.
    private func handleAutoPause(_ loc: CLLocation) -> Bool {
        let prev = lastRaw
        lastRaw = loc
        guard autoPauseEnabled, let threshold = Self.autoPauseThreshold(for: kind) else {
            return state == .recording
        }
        var speed = loc.speed
        if speed < 0, let prev {
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            speed = dt > 0 ? loc.distance(from: prev) / dt : 0
        }
        if state == .paused && autoPaused {
            if speed >= threshold { fastFixes += 1 } else { fastFixes = 0 }
            if fastFixes >= 2 { resume(); return true }
            return false
        }
        guard state == .recording else { return false }
        if speed < threshold {
            let since = slowSince ?? loc.timestamp
            slowSince = since
            if loc.timestamp.timeIntervalSince(since) >= 12 {
                autoPause(since: since)
                return false
            }
        } else {
            slowSince = nil
        }
        return true
    }

    private func checkSplits(previousDistance: Double) {
        guard TrackPrefs.announceSplits else { return }
        let metric = Units.metric
        let unit = metric ? 1000.0 : 1609.344
        let crossed = SplitAnnouncer.splitsCrossed(previous: previousDistance, current: distance, unit: unit)
        guard let split = crossed.last, split > splitsAnnounced else { return }
        let total = elapsed
        let splitTime = (total - lastSplitElapsed) / Double(split - splitsAnnounced)
        splitsAnnounced = split
        lastSplitElapsed = total
        SplitAnnouncer.shared.announce(split: split, metric: metric, splitTime: splitTime, total: total)
    }

    /// Stops recording and returns a filled-in Activity (not yet inserted into the database).
    /// With `trimIdle`, a stationary tail of 2+ minutes is cut off so it doesn't count as time or distance.
    func finish(trimIdle: Bool = TrackPrefs.trimIdle, auto: Bool = false) -> Activity? {
        guard state != .idle, let startDate else { return nil }
        if state == .recording, let resumedAt { accumulated += Date().timeIntervalSince(resumedAt) }
        stopUpdates()
        let a = Activity()
        a.id = sessionID
        a.kind = kind
        a.start = startDate
        a.end = startDate.addingTimeInterval(max(accumulated, 1))
        a.distanceM = distance
        a.movingSec = min(movingSec, accumulated)
        a.elevGainM = elevGain
        a.maxSpeed = maxSpeed
        a.route = Self.simplify(points, maxCount: 4000)
        a.laneChanges = laneChanges
        a.autoFinished = auto
        var trimmed = 0.0
        if trimIdle, let cut = Self.idleTailStart(points, kind: kind) {
            let tail = a.end.timeIntervalSince1970 - cut
            if tail >= 120 {
                a.trim(endT: cut)
                a.elevGainM = elevGain
                trimmed = tail
            }
        }
        reset()
        lastTrimmedSec = trimmed
        LiveActivityController.shared.end()
        if !auto { Reviews.noteWin() }
        return a
    }

    /// Time (seconds since 1970) when the final stationary stretch began, or nil if you were still moving.
    static func idleTailStart(_ pts: [RoutePoint], kind: ActivityKind) -> Double? {
        guard pts.count > 2 else { return nil }
        let still = kind == .drive ? 0.9 : 0.3   // m/s: ~2 mph for drives, ~0.7 mph on foot
        var i = pts.count - 1
        var cut: Double? = nil
        while i > 0 {
            let a = pts[i - 1], b = pts[i]
            let dt = b.t - a.t
            guard dt > 0 else { i -= 1; continue }
            let d = CLLocation(latitude: a.lat, longitude: a.lng).distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
            let v = b.speed >= 0 ? max(b.speed, d / dt) : d / dt
            if v > still { break }
            cut = a.t
            i -= 1
        }
        return cut
    }

    /// Minutes of standing still before a recording finishes itself (per kind; 0 = never).
    private var autoFinishAfter: TimeInterval {
        let m = TrackPrefs.autoFinishMinutes
        guard m > 0 else { return 0 }
        return Double(m) * 60
    }

    /// Call every few seconds while recording: tracks how long you've been stopped.
    private func idleCheck() {
        guard state == .recording || (state == .paused && autoPaused) else { idleSince = nil; return }
        let still = kind == .drive ? 0.9 : 0.25
        let now = Date()
        let lastFixAge = lastRaw.map { now.timeIntervalSince($0.timestamp) } ?? 0
        let moving = currentSpeed > still && lastFixAge < 20
        if moving {
            lastMovingAt = now
            if idleSince != nil { idleSince = nil; autoFinishDue = false }
            return
        }
        if idleSince == nil { idleSince = lastRaw?.timestamp ?? now }
        if autoFinishAfter > 0, let since = idleSince, !autoFinishDue,
           now.timeIntervalSince(since) >= autoFinishAfter {
            autoFinishDue = true
        }
    }

    /// "Keep going" on the auto-finish prompt: don't ask again until you've moved and stopped again.
    func dismissAutoFinish() {
        autoFinishDue = false
        idleSince = Date()
    }

    /// Change the activity type while recording (e.g. a walk that became a hike).
    func setKind(_ k: ActivityKind) {
        kind = k
        if k != .drive { speedLimit = nil; limits.reset(); stopLaneWatch() } else if state == .recording { startLaneWatch() }
        applyKindSettings()
        persist()
        if state != .idle { LiveActivityController.shared.update(tracker: self, force: true) }
    }

    func discard() {
        stopUpdates()
        reset()
        LiveActivityController.shared.end()
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

    /// With the distance filter, a standing phone may send no fixes at all, so check on a timer too.
    private func startStillTimer() {
        stillTimer?.invalidate()
        stillTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stillCheck() }
        }
    }

    private func stillCheck() {
        idleCheck()
        // Wait for a first GPS fix, so a slow start doesn't look like a stop.
        guard state == .recording, autoPauseEnabled, let resumedAt, let raw = lastRaw else { return }
        let lastFix = max(raw.timestamp, resumedAt)
        let since = max(slowSince ?? lastFix, resumedAt)
        if Date().timeIntervalSince(lastFix) >= 12 || Date().timeIntervalSince(since) >= 12 && slowSince != nil {
            autoPause(since: since)
        }
    }

    private func beginUpdates() {
        startStillTimer()
        if kind == .drive { startLaneWatch() }
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if #available(iOS 17.0, *), backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
    }

    private func stopUpdates() {
        stopLaneWatch()
        stillTimer?.invalidate()
        stillTimer = nil
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
        autoPaused = false
        idleSince = nil
        autoFinishDue = false
        lastMovingAt = nil
        slowSince = nil
        fastFixes = 0
        lastRaw = nil
        splitsAnnounced = 0
        lastSplitElapsed = 0
        course = -1
        speedLimit = nil
        overWarned = false
        limits.reset()
        laneChanges = []
        laneDetector = LaneChangeDetector()
        roadLaneDetector = RoadLaneDetector()
        roadGeo = nil
        roadBend = 0
        onCurve = false
        resetLanes()
    }

    // MARK: Lane changes (drives only)

    private func startLaneWatch() {
        startDemoLanes()
        guard gyro.isDeviceMotionAvailable, !gyro.isDeviceMotionActive else { return }
        gyro.deviceMotionUpdateInterval = 1.0 / 20
        gyro.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m, self.state == .recording, self.kind == .drive else { return }
            let g = m.gravity
            let gl = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
            guard gl > 0.5 else { return }
            // Rotation about "up" (opposite gravity): + = turning left.
            let r = m.rotationRate
            let yaw = -(r.x * g.x + r.y * g.y + r.z * g.z) / gl
            let t = Date().timeIntervalSince1970
            let a = m.userAcceleration
            if (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > 0.35 {
                self.laneDetector.handled(at: t)
                self.roadLaneDetector.handled(at: t)
            }
            let event: LaneChangeDetector.Event?
            if let g = self.roadGeo, Date().timeIntervalSince(g.at) < 3 {
                // Matched road: judge the swerve relative to the road so curves don't count.
                let he: Double? = self.course >= 0 ? LaneMath.signedAngle(self.course, g.bearing) : nil
                event = self.roadLaneDetector.add(RoadLaneDetector.Sample(t: t, yawRate: yaw, speed: self.currentSpeed,
                                                                         curvature: g.curvature, curvatureWide: g.curvatureWide,
                                                                         headingError: he))
            } else {
                event = self.laneDetector.add(t: t, yawRate: yaw, speed: self.currentSpeed, course: self.course)
            }
            if let e = event { self.recordLaneChange(e) }
        }
    }

    private func stopLaneWatch() {
        demoLaneTimer?.invalidate(); demoLaneTimer = nil
        if gyro.isDeviceMotionActive { gyro.stopDeviceMotionUpdates() }
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
        guard state == .recording || autoPaused else { return }
        // Throw away stale or fuzzy fixes.
        guard loc.horizontalAccuracy >= 0, abs(loc.timestamp.timeIntervalSinceNow) < 15 else { return }
        let maxAcc: Double = kind == .drive ? 65 : 35
        accuracy = loc.horizontalAccuracy
        guard loc.horizontalAccuracy <= maxAcc else { return }
        guard handleAutoPause(loc) else { return }
        let previousDistance = distance

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

        if loc.course >= 0 && currentSpeed > 1 { course = loc.course }
        if kind == .drive {
            if loc.course >= 0 && currentSpeed > 4 { checkTurnForLanes(loc.course) }
            limits.update(for: loc, speed: currentSpeed) { [weak self] l in
                guard let self, self.kind == .drive, self.state != .idle else { return }
                self.speedLimit = l
                if let l { self.updateLaneCount(l.lanes, estimated: l.lanesEstimated) }
            }
            updateRoadShape(limits.geometry)
        }
        lastAccepted = loc
        var pt = RoutePoint(loc)
        if kind == .drive, let l = speedLimit { pt.limit = l.mps }
        points.append(pt)
        // One gentle warning buzz each time you go over, not a buzz on every fix.
        if isOverLimit {
            if !overWarned { overWarned = true; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        } else if let l = speedLimit, currentSpeed < l.mps {
            overWarned = false
        }
        checkSplits(previousDistance: previousDistance)
        unsavedCount += 1
        if unsavedCount >= 10 { persist() }
        LiveActivityController.shared.update(tracker: self)
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
        var sessionID: UUID?
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
                            elevGain: elevGain, maxSpeed: maxSpeed, movingSec: movingSec, sessionID: sessionID)
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
        sessionID = snap.sessionID ?? UUID()
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
        splitsAnnounced = Int((distance / (Units.metric ? 1000.0 : 1609.344)).rounded(.down))
        lastSplitElapsed = accumulated
    }

    // MARK: - Helpers

    /// Keeps the route light for storage while keeping its shape.
    nonisolated static func simplify(_ pts: [RoutePoint], maxCount: Int) -> [RoutePoint] {
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
