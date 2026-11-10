import Foundation
import AVFoundation
import UIKit

/// Recording preferences that differ between the two apps.
enum TrackPrefs {
    static let announceSplitsKey = "announceSplits"
    static let autoPauseKey = "autoPause"
    /// Minutes of standing still before a drive finishes itself (0 = off).
    static let autoFinishKey = "autoFinishMinutes"
    /// Drop the idle minutes at the end when a recording is finished.
    static let trimIdleKey = "trimIdleEnd"

    #if TRACK_APP
    static let defaultOn = true
    #else
    static let defaultOn = false
    #endif

    static func register() {
        UserDefaults.standard.register(defaults: [announceSplitsKey: defaultOn, autoPauseKey: defaultOn,
                                                  autoFinishKey: defaultOn ? 5 : 0, trimIdleKey: true])
    }

    static var autoFinishMinutes: Int { register(); return UserDefaults.standard.integer(forKey: autoFinishKey) }
    static var trimIdle: Bool { register(); return UserDefaults.standard.bool(forKey: trimIdleKey) }

    static var announceSplits: Bool { register(); return UserDefaults.standard.bool(forKey: announceSplitsKey) }
    static var autoPause: Bool { register(); return UserDefaults.standard.bool(forKey: autoPauseKey) }
}

/// Speaks a short summary at every mile (or km) and taps a haptic.
@MainActor
final class SplitAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SplitAnnouncer()

    private let synth = AVSpeechSynthesizer()
    private let haptics = UINotificationFeedbackGenerator()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Split numbers whose boundary was crossed going from `previous` to `current` meters.
    nonisolated static func splitsCrossed(previous: Double, current: Double, unit: Double) -> [Int] {
        guard unit > 0, current > previous else { return [] }
        let before = Int((previous / unit).rounded(.down))
        let after = Int((current / unit).rounded(.down))
        guard after > before else { return [] }
        return Array((before + 1)...after)
    }

    /// "9 minutes 41 seconds", "1 hour 2 minutes", "45 seconds".
    nonisolated static func spoken(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var parts: [String] = []
        if h > 0 { parts.append(unit(h, "hour")) }
        if m > 0 { parts.append(unit(m, "minute")) }
        if h == 0 && (sec > 0 || parts.isEmpty) { parts.append(unit(sec, "second")) }
        return parts.joined(separator: " ")
    }

    nonisolated static func phrase(split: Int, metric: Bool, splitTime: TimeInterval, total: TimeInterval) -> String {
        "\(metric ? "Kilometer" : "Mile") \(split). Split \(spoken(splitTime)). Total \(spoken(total))."
    }

    func announce(split: Int, metric: Bool, splitTime: TimeInterval, total: TimeInterval) {
        haptics.notificationOccurred(.success)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: Self.phrase(split: split, metric: metric, splitTime: splitTime, total: total))
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synth.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
