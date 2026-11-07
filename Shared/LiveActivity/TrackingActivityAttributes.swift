import Foundation
import ActivityKit

/// Live Activity data for a route being recorded.
/// Compiled into BOTH the apps and the widget extensions, so it must stay dependency-free
/// (no Theme, Format, ActivityKind or other app-only types).
struct TrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Now minus elapsed", so `Text(timerInterval: startedAt...distantFuture, countsDown: false)`
        /// shows the recording's elapsed time and keeps ticking on its own while recording.
        var startedAt: Date
        var isPaused: Bool
        /// Frozen elapsed seconds, shown while paused.
        var elapsed: TimeInterval
        var distanceM: Double
        /// Pace ("12:34 /mi") for on-foot kinds, speed ("23 mph") for rides and drives.
        var paceOrSpeed: String
        /// Formatted distance, e.g. "1.23 mi".
        var distanceText: String
        /// Trees hugged during this recording (Rootbound only).
        var hugs: Int
    }

    var kindTitle: String
    var kindSymbol: String
    var appName: String
}

extension TrackingActivityAttributes {
    /// True when the activity shows a pace (on-foot kinds use `figure.*` symbols).
    var showsPace: Bool { kindSymbol.hasPrefix("figure") }

    /// "12:34" or "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let safe: Double = seconds.isFinite ? max(0, seconds) : 0
        let s: Int = Int(safe.rounded(.down))
        let h: Int = s / 3600
        let m: Int = (s % 3600) / 60
        let sec: Int = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    /// Splits "1.23 mi" into ("1.23", "mi"); text without a space comes back as (text, "").
    static func valueAndUnit(_ text: String) -> (value: String, unit: String) {
        guard let space = text.firstIndex(of: " ") else { return (text, "") }
        let value: String = String(text[text.startIndex..<space])
        let unit: String = String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (value, unit)
    }
}

extension TrackingActivityAttributes.ContentState {
    /// Lower bound for a live timer, never in the future (a ClosedRange with lower > upper traps).
    var timerStart: Date { min(startedAt, Date()) }
}
