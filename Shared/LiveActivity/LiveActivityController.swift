import Foundation
import ActivityKit

/// Drives the Lock Screen / Dynamic Island Live Activity for a route recording.
/// Compiled into the apps only (not the widget extensions).
///
/// Note: the app module has its own SwiftData `Activity` model, so ActivityKit's type is always
/// written as `ActivityKit.Activity<...>` here.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    typealias LiveActivity = ActivityKit.Activity<TrackingActivityAttributes>

    /// Minimum seconds between routine (unforced) updates.
    private let minInterval: TimeInterval = 10

    private var current: LiveActivity?
    private var lastUpdate: Date = .distantPast
    private var lastPaused: Bool?
    private var hugs: Int = 0

    private init() {
        // Pick up an activity that is still running from before the app was relaunched.
        current = LiveActivity.activities.first
        if let current {
            hugs = current.content.state.hugs
            lastPaused = current.content.state.isPaused
        }
    }

    private var enabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private var appName: String {
        #if TRACK_APP
        return "Roamr"
        #else
        return "Rootbound"
        #endif
    }

    // MARK: - Public

    /// Starts a Live Activity for a new recording (ending any leftover one first).
    func start(kind: ActivityKind, startDate: Date) {
        hugs = 0
        let state = TrackingActivityAttributes.ContentState(
            startedAt: startDate,
            isPaused: false,
            elapsed: max(0, Date().timeIntervalSince(startDate)),
            distanceM: 0,
            paceOrSpeed: "--",
            distanceText: Format.distance(0),
            hugs: 0
        )
        request(kind: kind, state: state)
    }

    /// Pushes the tracker's latest numbers. Throttled to once every 10 s unless the paused state
    /// changed or `force` is true. Pass `hugs` to change the hug count; omit it to keep the last one.
    func update(tracker: RouteTracker, hugs newHugs: Int? = nil, force: Bool = false) {
        if tracker.state == .idle {
            end()
            return
        }
        var hugsChanged = false
        if let newHugs, newHugs != hugs {
            hugs = newHugs
            hugsChanged = true
        }
        guard enabled else { return }

        let state = makeState(tracker: tracker)
        let now = Date()

        guard let activity = liveCurrent() else {
            // No activity on screen (e.g. after a relaunch); only try to create one on deliberate updates,
            // since requests from the background are refused.
            if force || hugsChanged || lastPaused != state.isPaused {
                request(kind: tracker.kind, state: state)
            }
            return
        }

        // Kind changed mid-recording (attributes are fixed): replace the activity.
        if activity.attributes.kindTitle != tracker.kind.title || activity.attributes.kindSymbol != tracker.kind.symbol {
            if force {
                request(kind: tracker.kind, state: state)
                return
            }
        }

        let pausedChanged = lastPaused != state.isPaused
        guard force || pausedChanged || hugsChanged || now.timeIntervalSince(lastUpdate) >= minInterval else { return }

        lastUpdate = now
        lastPaused = state.isPaused
        let content = ActivityContent<TrackingActivityAttributes.ContentState>(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    /// Sets the number of trees hugged during the current recording (Rootbound).
    func setHugs(_ count: Int) {
        guard count != hugs else { return }
        hugs = count
        guard enabled, let activity = liveCurrent() else { return }
        var state = activity.content.state
        state.hugs = count
        lastUpdate = Date()
        let content = ActivityContent<TrackingActivityAttributes.ContentState>(state: state, staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    /// Ends every recording Live Activity. `dismissAfter` > 0 leaves the final numbers on the
    /// Lock Screen for that many seconds.
    func end(dismissAfter: TimeInterval = 0) {
        let all: [LiveActivity] = LiveActivity.activities
        let known: LiveActivity? = current
        current = nil
        lastPaused = nil
        lastUpdate = .distantPast
        hugs = 0
        var toEnd: [LiveActivity] = all
        if let known, !all.contains(where: { (a: LiveActivity) -> Bool in a.id == known.id }) {
            toEnd.append(known)
        }
        guard !toEnd.isEmpty else { return }
        let policy: ActivityUIDismissalPolicy = dismissAfter > 0
            ? .after(Date().addingTimeInterval(dismissAfter))
            : .immediate
        for activity in toEnd {
            Task {
                await activity.end(activity.content, dismissalPolicy: policy)
            }
        }
    }

    /// Call once on launch: ends an orphaned activity if nothing is being recorded,
    /// otherwise refreshes it (or creates one) for the restored recording.
    func sync(with tracker: RouteTracker) {
        if tracker.state == .idle {
            if !LiveActivity.activities.isEmpty || current != nil { end() }
        } else {
            update(tracker: tracker, force: true)
        }
    }

    // MARK: - Private

    private func liveCurrent() -> LiveActivity? {
        if let current {
            switch current.activityState {
            case .active, .stale:
                return current
            default:
                self.current = nil
            }
        }
        if let existing = LiveActivity.activities.first(where: { (a: LiveActivity) -> Bool in
            a.activityState == .active || a.activityState == .stale
        }) {
            current = existing
            return existing
        }
        return nil
    }

    private func makeState(tracker: RouteTracker) -> TrackingActivityAttributes.ContentState {
        let elapsed: TimeInterval = max(0, tracker.elapsed)
        let paused: Bool = tracker.state == .paused
        let kind: ActivityKind = tracker.kind
        let paceOrSpeed: String
        if kind.isOnFoot {
            let seconds: Double = tracker.movingSec > 0 ? tracker.movingSec : elapsed
            paceOrSpeed = Format.paceOrSpeed(distance: tracker.distance, seconds: seconds, kind: kind)
        } else if !paused && tracker.currentSpeed > 0 {
            paceOrSpeed = Format.speed(tracker.currentSpeed)
        } else {
            let seconds: Double = tracker.movingSec > 0 ? tracker.movingSec : elapsed
            paceOrSpeed = Format.paceOrSpeed(distance: tracker.distance, seconds: seconds, kind: kind)
        }
        return TrackingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-elapsed),
            isPaused: paused,
            elapsed: elapsed,
            distanceM: tracker.distance,
            paceOrSpeed: paceOrSpeed,
            distanceText: Format.distance(tracker.distance),
            hugs: hugs
        )
    }

    /// Ends any existing activity and requests a new one. Never throws; failures are ignored.
    private func request(kind: ActivityKind, state: TrackingActivityAttributes.ContentState) {
        guard enabled else { return }
        let previous: [LiveActivity] = LiveActivity.activities
        let attributes = TrackingActivityAttributes(kindTitle: kind.title, kindSymbol: kind.symbol, appName: appName)
        let content = ActivityContent<TrackingActivityAttributes.ContentState>(state: state, staleDate: nil)
        do {
            let activity: LiveActivity = try LiveActivity.request(attributes: attributes, content: content, pushType: nil)
            current = activity
            lastUpdate = Date()
            lastPaused = state.isPaused
            for old in previous where old.id != activity.id {
                Task {
                    await old.end(nil, dismissalPolicy: .immediate)
                }
            }
        } catch {
            // Not allowed right now (background, disabled, too many activities). Keep whatever is showing.
        }
    }
}
