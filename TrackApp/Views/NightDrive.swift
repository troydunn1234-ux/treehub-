import SwiftUI

// Roamr's night-drive feel (looks only): a violet "night cruise" tint after sunset, a headlight sweep across
// Start drive, a quick ignition sweep as a drive starts, and the "Drive saved" moment with the distance rolling up.
// Reads nothing but the clock; stores nothing.

enum NightCruise {
    static let violet = Color(red: 0.36, green: 0.20, blue: 0.70)
    static let neon = Color(red: 1.0, green: 0.30, blue: 0.60)
    static let teal = Color(red: 0.20, green: 0.80, blue: 0.95)

    /// After sunset until dawn. Sunset follows the time of year roughly (mid-latitudes, local clock): about 5 pm
    /// in late December, 8:30 pm in late June.
    static func isOn(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let season = sin(2 * Double.pi * (day - 80) / 365)   // +1 late June, -1 late December
        let sunset = 18.75 + 1.75 * season
        let sunrise = 6.25 - 1.0 * season
        return hour >= sunset || hour < sunrise
    }

    /// The Track screen's hello for the time of day ("Night cruise" after sunset).
    static func greeting(at date: Date = Date(), calendar: Calendar = .current) -> (text: String, symbol: String) {
        if isOn(at: date, calendar: calendar) { return (String(localized: "Night cruise"), "moon.stars.fill") }
        switch calendar.component(.hour, from: date) {
        case 0..<12: return (String(localized: "Good morning"), "sunrise.fill")
        case 12..<17: return (String(localized: "Good afternoon"), "sun.max.fill")
        default: return (String(localized: "Good evening"), "sunset.fill")
        }
    }
}

/// Every Roamr screen after sunset: a little more violet from the top, a faint neon and teal city glow along the
/// bottom corners (ForestBackground). Checks the clock once a minute.
struct NightCruiseWash: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            ZStack {
                if NightCruise.isOn(at: ctx.date) {
                    LinearGradient(colors: [NightCruise.violet.opacity(0.24), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5))
                    RadialGradient(colors: [NightCruise.neon.opacity(0.10), .clear],
                                   center: .bottomTrailing, startRadius: 10, endRadius: 380)
                    RadialGradient(colors: [NightCruise.teal.opacity(0.07), .clear],
                                   center: .bottomLeading, startRadius: 10, endRadius: 320)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Start drive

/// A soft headlight beam that sweeps across a button every few seconds (none with Reduce Motion, or while the
/// button is disabled).
struct HeadlightSweep: ViewModifier {
    var cornerRadius: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion && enabled {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    LinearGradient(colors: [.clear, .white.opacity(0.38), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(56, w * 0.22), height: h * 1.8)
                        .rotationEffect(.degrees(18))
                        .phaseAnimator([false, true]) { beam, across in
                            beam.position(x: across ? w * 1.25 : -w * 0.25, y: h / 2)
                        } animation: { across in
                            across ? .easeInOut(duration: 1.0) : .linear(duration: 0.01).delay(3.2)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Start drive's headlight sweep (HeadlightSweep).
    func headlightSweep(cornerRadius: CGFloat = 14) -> some View { modifier(HeadlightSweep(cornerRadius: cornerRadius)) }

    /// A thin glowing bezel just outside a button, like a lit dashboard control.
    func dashGlowRing(cornerRadius: CGFloat = 14, inset: CGFloat = -5) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius - inset, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.glow.opacity(0.7), Theme.leaf.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(inset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The moment a drive starts: a band of headlight sweeps up the screen and speed lines streak out and fade
/// (about a second). Plays once per start, armed by the Start buttons; nothing with Reduce Motion.
enum Ignition {
    static var armedAt: Date?

    static func arm() { armedAt = Date() }

    /// True once, within a few seconds of a start (a later return to the Track tab doesn't replay it).
    static func take() -> Bool {
        defer { armedAt = nil }
        guard let t = armedAt else { return false }
        return Date().timeIntervalSince(t) < 4
    }
}

struct IgnitionFX: View {
    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration: Double = 1.1
    private static let lines: [(angle: Double, length: Double, delay: Double)] = {
        var rng = SeededRNG(seed: "ignition")
        return (0..<30).map { i in
            (Double(i) / 30 * 2 * Double.pi + rng.next() * 0.18, 0.08 + rng.next() * 0.1, rng.next() * 0.18)
        }
    }()

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSince(start)
                    Canvas { gc, size in
                        let w = size.width
                        let h = size.height
                        let p = min(1, max(0, t / Self.duration))
                        let fade = 1 - p
                        let rise = 1 - pow(1 - p, 3)
                        // Headlight band rising from the bottom.
                        let bandY = h * CGFloat(1.05 - 1.3 * rise)
                        let band = CGRect(x: 0, y: bandY - h * 0.2, width: w, height: h * 0.4)
                        gc.fill(Path(band), with: .linearGradient(
                            Gradient(colors: [.clear, Theme.glow.opacity(0.32 * fade), .clear]),
                            startPoint: CGPoint(x: w / 2, y: band.minY), endPoint: CGPoint(x: w / 2, y: band.maxY)))
                        // Speed lines streaking out from the middle.
                        let center = CGPoint(x: w / 2, y: h * 0.45)
                        let reach = max(w, h)
                        for l in Self.lines {
                            let q = min(1, max(0, (t - l.delay) / Self.duration))
                            guard q > 0 else { continue }
                            let r0 = reach * CGFloat(0.12 + 0.75 * q)
                            let r1 = r0 + reach * CGFloat(l.length)
                            let dx = CGFloat(cos(l.angle)), dy = CGFloat(sin(l.angle))
                            var line = Path()
                            line.move(to: CGPoint(x: center.x + dx * r0, y: center.y + dy * r0))
                            line.addLine(to: CGPoint(x: center.x + dx * r1, y: center.y + dy * r1))
                            gc.stroke(line, with: .color(Color.white.opacity(0.5 * (1 - q))),
                                      style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                    }
                }
                .blendMode(.plusLighter)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard Ignition.take(), !reduceMotion else { return }
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.3) { start = nil }
        }
    }
}

// MARK: - Drive saved

/// The "Drive saved" chip on a just-finished drive: the seal pops and the distance rolls up from zero
/// (shown at once with Reduce Motion), then a light tap when it lands.
struct DriveSavedBadge: View {
    let distanceM: Double
    @State private var shown: Double = 0
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Theme.glow)
                .symbolEffect(.bounce, value: landed)
            Text("Drive saved")
            if distanceM > 0 {
                Text(verbatim: "·").foregroundStyle(.white.opacity(0.5))
                Text(verbatim: Format.distance(shown))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shown))
                    .foregroundStyle(Theme.glow)
            }
        }
        .font(Theme.rounded(14, .heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glow.opacity(landed ? 0.8 : 0.4)))
        .shadow(color: Theme.glow.opacity(landed ? 0.45 : 0), radius: 8)
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Drive saved, \(Format.distance(distanceM))"))
        .task { await rollUp() }
    }

    private func rollUp() async {
        guard !reduceMotion, distanceM > 0 else {
            shown = distanceM
            landed = true
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        let steps = 20
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: 45_000_000)
            let p = Double(i) / Double(steps)
            let eased = 1 - pow(1 - p, 3)
            withAnimation(.snappy(duration: 0.15)) { shown = distanceM * eased }
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { landed = true }
    }
}
