import AVFoundation
import Combine
import Foundation

/// One line the guide will say at a set time. Counts are "droppable": skipped if the voice is still busy.
struct VoiceCue {
    var at: Date
    var text: String
    var droppable = false
}

/// Calm spoken guidance for sessions and the sauna / steam guide.
///
/// Speaks move names, short cues and breath counts ("in… 2… 3… 4") with a slow, slightly low voice.
/// Other audio (music, podcasts) is ducked, not stopped. While the guide is on, a silent audio loop keeps
/// the app running so the voice carries on with the screen locked (UIBackgroundModes: audio).
final class VoiceGuide: NSObject, ObservableObject {
    static let shared = VoiceGuide()

    /// Voice is on for the session in front of you (starts from the Settings toggle; the speaker button flips it).
    @Published private(set) var on = false

    private let synth = AVSpeechSynthesizer()
    private var pending: [VoiceCue] = []
    private var timer: DispatchSourceTimer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var audioActive = false
    private var inUse = 0
    private lazy var voice: AVSpeechSynthesisVoice? = Self.pickVoice()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: Session lifetime

    /// A session or the heat guide opened. Voice follows the Settings toggle.
    func begin() {
        inUse += 1
        let want = Prefs.shared.settings.voiceGuide && !ProcessInfo.processInfo.arguments.contains("-demo")
        if want { turnOn() } else { on = false }
    }

    /// The session or guide closed.
    func end() {
        inUse = max(0, inUse - 1)
        guard inUse == 0 else { return }
        turnOff()
    }

    /// The per-session speaker button.
    func toggle() { on ? turnOff() : turnOn() }

    private func turnOn() {
        on = true
        activateAudio()
        startTimer()
    }

    private func turnOff() {
        on = false
        pending.removeAll()
        synth.stopSpeaking(at: .word)
        timer?.cancel(); timer = nil
        deactivateAudio()
    }

    // MARK: Speaking

    /// Say something now (queued behind anything already being said).
    func say(_ text: String) {
        guard on, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.42
        u.pitchMultiplier = 0.92
        u.volume = 0.9
        u.preUtteranceDelay = 0.05
        u.postUtteranceDelay = 0.1
        if let voice { u.voice = voice }
        synth.speak(u)
    }

    /// Replace everything waiting with a new script.
    func play(_ cues: [VoiceCue]) {
        pending = cues.sorted { $0.at < $1.at }
    }

    /// Drop waiting counts and cues (e.g. on pause).
    func clearPending() { pending.removeAll() }

    /// Stop talking right away and forget what was waiting.
    func hush() {
        pending.removeAll()
        synth.stopSpeaking(at: .word)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(150), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        guard on, !pending.isEmpty else { return }
        let now = Date()
        while let first = pending.first, first.at <= now {
            pending.removeFirst()
            let late = now.timeIntervalSince(first.at)
            if first.droppable && (synth.isSpeaking || late > 0.8) { continue }
            if late > 4 { continue }
            say(first.text)
        }
    }

    // MARK: Breath sessions

    /// Words for a phase starting now, plus counts on the first few breaths.
    func breathPhase(_ phase: BreathPhase, duration: Double, label: String, cycle: Int, pattern: BreathPattern?) {
        guard on else { return }
        pending.removeAll { $0.droppable }
        // First breaths: full words and counts. Then just the words, and after a while only every few breaths.
        if cycle >= 12 && cycle % 4 != 0 { return }
        let special = (pattern?.nostril ?? false) || ((pattern?.hum ?? false) && phase == .exhale)
        let word: String
        if special || cycle < 2 {
            word = label.replacingOccurrences(of: " · ", with: ", ")
        } else {
            switch phase {
            case .inhale: word = String(localized: "In")
            case .exhale: word = String(localized: "Out")
            case .holdIn: word = String(localized: "Hold")
            case .holdOut: word = String(localized: "Rest")
            case .still: word = ""
            }
        }
        say(word)
        guard cycle < 4 else { return }
        play(pending + Self.counts(from: Date(), seconds: duration))
    }

    /// "2… 3… 4" one per second after the phase word.
    static func counts(from start: Date, seconds: Double) -> [VoiceCue] {
        let n = Int(seconds.rounded(.down))
        guard seconds >= 2.5, n >= 2, n <= 12 else { return [] }
        return (2...n).map { VoiceCue(at: start.addingTimeInterval(Double($0 - 1)), text: "\($0)", droppable: true) }
    }

    // MARK: Sauna & steam scripts

    /// Spoken script for one heat breath, from `start`, for `seconds`. Breaths before `firstCycle` stay
    /// quiet (the intro is being spoken); the next two get full words and counts, then just "in" / "out".
    static func heatBreath(_ b: HeatBreath, from start: Date, seconds: Double, firstCycle: Int = 0, countCycles: Int = 3) -> [VoiceCue] {
        var out: [VoiceCue] = []
        var t = 0.0
        var cycle = 0
        guard b.cycle > 0 else { return [] }
        while t < seconds - 1 {
            for (i, p) in b.phases.enumerated() {
                guard t < seconds - 1 else { break }
                let at = start.addingTimeInterval(t)
                let n = cycle - firstCycle
                if n >= 0 {
                    if !(n >= 10 && n % 3 != 0) {
                        let word: String
                        if n < 2 { word = p.label }
                        else if i > 0 && p.grow { word = String(localized: "More") }
                        else { word = p.grow ? String(localized: "In") : String(localized: "Out") }
                        out.append(VoiceCue(at: at, text: word))
                    }
                    if n < countCycles { out += counts(from: at, seconds: p.seconds) }
                }
                t += p.seconds
            }
            cycle += 1
        }
        return out
    }

    static func intro(_ b: HeatBreath) -> String {
        "\(b.title). \(b.pattern.replacingOccurrences(of: " · ", with: ", "))."
    }

    static func intro(_ m: HeatMove) -> String { "\(m.title). \(m.how)" }

    // MARK: Audio session

    private func activateAudio() {
        guard !audioActive else { return }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
            try s.setActive(true)
            audioActive = true
        } catch {
            audioActive = false
        }
        startSilence()
    }

    private func deactivateAudio() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        guard audioActive else { return }
        audioActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A looping silent buffer: keeps the app awake in the background so cues keep their timing.
    private func startSilence() {
        guard engine == nil, let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44_100) else { return }
        buf.frameLength = 44_100
        if let ch = buf.floatChannelData { ch[0].update(repeating: 0, count: Int(buf.frameLength)) }
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: fmt)
        do {
            try e.start()
            p.scheduleBuffer(buf, at: nil, options: .loops)
            p.play()
            engine = e
            player = p
        } catch {
            engine = nil
            player = nil
        }
    }

    @objc private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.on else { return }
            if type == .ended {
                self.audioActive = false
                self.player?.stop(); self.engine?.stop(); self.player = nil; self.engine = nil
                self.activateAudio()
            }
        }
    }

    /// The best installed voice in the app's language, avoiding novelty voices.
    private static func pickVoice() -> AVSpeechSynthesisVoice? {
        let lang = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        let code = current.hasPrefix(lang) ? current : (lang == "es" ? "es-ES" : "en-US")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(lang) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        let exact = voices.filter { $0.language == code }
        let best = (exact.isEmpty ? voices : exact).max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: code)
    }
}

/// iPhone session feedback: the usual haptics, plus the voice when it's on.
final class GuidedFeedback: BreathFeedback {
    let haptics = PhoneHaptics()
    private let voice = VoiceGuide.shared
    weak var breath: BreathSession?
    weak var movement: MovementSession?
    private var cueSink: AnyCancellable?

    func attach(_ b: BreathSession) {
        breath = b
        movement = nil
        b.feedback = self
        cueSink = b.$cue.removeDuplicates().dropFirst().sink { [weak self] c in
            guard let c, !c.isEmpty else { return }
            self?.voice.clearPending()
            self?.voice.say(c)
        }
        var intro = b.practice.title
        if let p = b.pattern, p.cycleLength > 0 {
            var parts = [String(localized: "In for \(Int(p.inhale))")]
            if p.holdIn > 0 { parts.append(String(localized: "hold for \(Int(p.holdIn))")) }
            parts.append(String(localized: "out for \(Int(p.exhale))"))
            if p.holdOut > 0 { parts.append(String(localized: "rest for \(Int(p.holdOut))")) }
            intro += ". " + parts.joined(separator: ", ") + "."
        }
        voice.say(intro)
    }

    func attach(_ m: MovementSession) {
        movement = m
        breath = nil
        cueSink = nil
        m.feedback = self
        voice.say(m.practice.title)
    }

    func phaseBegan(_ phase: BreathPhase, duration: Double, style: HapticStyle) {
        haptics.phaseBegan(phase, duration: duration, style: style)
        let st = breath?.state
        voice.breathPhase(phase, duration: duration, label: st?.label ?? phase.label, cycle: st?.cycle ?? 0, pattern: breath?.pattern)
    }

    func exhaleTick(style: HapticStyle) { haptics.exhaleTick(style: style) }

    func topUp(style: HapticStyle) {
        haptics.topUp(style: style)
        voice.say(String(localized: "Sip in more"))
    }

    func bell(_ kind: BellKind) {
        haptics.bell(kind)
        if kind == .end { voice.hush(); voice.say(String(localized: "Well done.")) }
    }

    func stepBegan(style: HapticStyle) {
        haptics.stepBegan(style: style)
        guard let m = movement, !m.isFinished else { return }
        let s = m.step
        var line = s.name
        switch s.side {
        case "left": line += String(localized: ", left side")
        case "right": line += String(localized: ", right side")
        default: break
        }
        line += ". " + s.breathCue + "."
        if m.index > 0 { voice.hush() }
        voice.say(line)
    }

    func sideSwitchSoon(style: HapticStyle) {
        haptics.sideSwitchSoon(style: style)
        voice.say(String(localized: "Other side next."))
    }

    func stopAll() {
        haptics.stopAll()
        voice.clearPending()
    }
}

import SwiftUI

/// The per-session speaker button: turns the voice on or off for this session only.
struct VoiceToggleButton: View {
    @ObservedObject private var voice = VoiceGuide.shared
    var size: CGFloat = 56

    var body: some View {
        Button { voice.toggle() } label: {
            Image(systemName: voice.on ? "speaker.wave.2" : "speaker.slash")
                .font(.system(size: 18, weight: .light))
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .accessibilityLabel(voice.on ? Text("Turn voice guide off") : Text("Turn voice guide on"))
        .accessibilityHint(Text("Speaks each step and counts the breath"))
    }
}
