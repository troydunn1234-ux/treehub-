import UIKit
import CoreHaptics

/// iPhone haptics: a slow swell that rises through the in-breath and falls through the out-breath (Core Haptics),
/// with simple taps as a fallback.
final class PhoneHaptics: BreathFeedback {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private let light = UIImpactFeedbackGenerator(style: .soft)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let note = UINotificationFeedbackGenerator()

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak e] in try? e?.start() }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    func phaseBegan(_ phase: BreathPhase, duration: Double, style: HapticStyle) {
        guard style != .off else { return }
        stopPlayer()
        let strength: Float = style == .strong ? 0.75 : 0.4
        switch phase {
        case .inhale: swell(rising: true, duration: duration, peak: strength)
        case .exhale: swell(rising: false, duration: duration, peak: strength)
        case .holdIn, .holdOut: light.impactOccurred(intensity: CGFloat(strength))
        case .still: break
        }
    }

    func exhaleTick(style: HapticStyle) {
        guard style != .off else { return }
        light.impactOccurred(intensity: 0.35)
    }

    func topUp(style: HapticStyle) {
        guard style != .off else { return }
        light.impactOccurred(intensity: 0.6)
    }

    func bell(_ kind: BellKind) {
        switch kind {
        case .start: medium.impactOccurred(intensity: 0.6)
        case .interval: light.impactOccurred(intensity: 0.8)
        case .end: note.notificationOccurred(.success)
        }
    }

    func stepBegan(style: HapticStyle) {
        guard style != .off else { return }
        medium.impactOccurred(intensity: style == .strong ? 0.8 : 0.45)
    }

    func sideSwitchSoon(style: HapticStyle) {
        guard style != .off else { return }
        light.impactOccurred(intensity: 0.7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [light] in light.impactOccurred(intensity: 0.7) }
    }

    func stopAll() { stopPlayer() }

    private func stopPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// A continuous vibration whose intensity ramps up (inhale) or down (exhale) over the phase.
    private func swell(rising: Bool, duration: Double, peak: Float) {
        guard let engine, duration > 0.3 else {
            light.impactOccurred(intensity: CGFloat(peak))
            return
        }
        let d = min(duration, 29)
        let low: Float = 0.05
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: peak),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08),
        ], relativeTime: 0, duration: d)
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: rising ? low : 1.0),
            CHHapticParameterCurve.ControlPoint(relativeTime: d, value: rising ? 1.0 : low),
        ], relativeTime: 0)
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            let p = try engine.makeAdvancedPlayer(with: pattern)
            try p.start(atTime: CHHapticTimeImmediate)
            player = p
        } catch {
            light.impactOccurred(intensity: CGFloat(peak))
        }
    }
}
