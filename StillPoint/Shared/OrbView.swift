import SwiftUI

/// The breathing orb: layered translucent rings around a soft luminous core, with a slow inner shimmer.
/// It fills on the in-breath and empties on the out-breath.
struct BreathOrb: View {
    var scale: Double            // 0.55 … 1.0
    var phase: BreathPhase
    var hum: Bool = false
    var simplified = false       // wrist-down / dimmed: quiet outline only
    var accent: Color? = nil     // tradition accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        if let accent { return phase == .exhale || phase == .holdOut ? SP.violet : accent }
        switch phase {
        case .inhale, .still: return SP.teal
        case .holdIn: return SP.amber
        case .exhale: return SP.violet
        case .holdOut: return SP.indigo
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let d = side * CGFloat(scale)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || simplified)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    if simplified {
                        Circle()
                            .stroke(tint.opacity(0.55), lineWidth: 1.5)
                            .frame(width: d * 0.86, height: d * 0.86)
                        Circle()
                            .fill(tint.opacity(0.18))
                            .frame(width: d * 0.5, height: d * 0.5)
                            .blur(radius: d * 0.08)
                    } else {
                        // Soft outer haze
                        Circle()
                            .fill(RadialGradient(colors: [tint.opacity(0.30), tint.opacity(0)], center: .center,
                                                 startRadius: d * 0.2, endRadius: d * 0.7))
                            .frame(width: d * 1.4, height: d * 1.4)
                        // Faint guide at "full"
                        Circle()
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            .frame(width: side * 0.98, height: side * 0.98)
                        // Layered translucent rings, each drifting very slowly
                        ForEach(0..<4, id: \.self) { i in
                            let k = CGFloat(1.0 - Double(i) * 0.14)
                            Circle()
                                .fill(tint.opacity(0.10 + Double(i) * 0.05))
                                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                                .frame(width: d * 0.92 * k, height: d * 0.92 * k)
                                .offset(x: reduceMotion ? 0 : CGFloat(sin(t / (9 + Double(i) * 3) + Double(i))) * d * 0.012,
                                        y: reduceMotion ? 0 : CGFloat(cos(t / (11 + Double(i) * 2) + Double(i))) * d * 0.012)
                        }
                        // Luminous core with a slow shimmer
                        Circle()
                            .fill(RadialGradient(colors: [Color.white.opacity(0.85), tint.opacity(0.75), tint.opacity(0.0)],
                                                 center: .center, startRadius: 0, endRadius: d * 0.30))
                            .frame(width: d * 0.6, height: d * 0.6)
                            .blur(radius: d * 0.02)
                        Circle()
                            .fill(AngularGradient(colors: [Color.white.opacity(0.0), Color.white.opacity(0.16), Color.white.opacity(0.0),
                                                           Color.white.opacity(0.10), Color.white.opacity(0.0)],
                                                  center: .center, angle: .degrees(reduceMotion ? 0 : t * 6)))
                            .frame(width: d * 0.62, height: d * 0.62)
                            .blendMode(.plusLighter)
                        if hum && phase == .exhale {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .stroke(SP.amber.opacity(0.30 - Double(i) * 0.08), lineWidth: 1)
                                    .frame(width: d * (1.0 + CGFloat(i) * 0.12), height: d * (1.0 + CGFloat(i) * 0.12))
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeInOut(duration: 1.6), value: phase)
        .accessibilityHidden(true)
    }
}

/// Thin progress ring around a phase or step.
struct CountdownRing: View {
    var progress: Double
    var color: Color = SP.gold
    var lineWidth: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.1), value: progress)
    }
}

/// L / R nostril or side indicator.
struct SideIndicator: View {
    var left: Bool
    var right: Bool
    var color: Color = SP.gold
    var body: some View {
        HStack(spacing: 10) {
            dot("L", on: left)
            dot("R", on: right)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left && right ? "Both sides" : left ? "Left side" : "Right side")
    }

    private func dot(_ t: String, on: Bool) -> some View {
        Text(t)
            .font(SP.rounded(12, .bold))
            .foregroundStyle(on ? Color.black.opacity(0.85) : SP.faint)
            .frame(width: 24, height: 24)
            .background(Circle().fill(on ? color : Color.white.opacity(0.06)))
            .overlay(Circle().stroke(on ? .clear : SP.stroke, lineWidth: 1))
    }
}

/// A short pattern strip: "In 4 · Hold 7 · Out 8".
struct PatternStrip: View {
    let pattern: BreathPattern
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            seg("In", pattern.inhale, SP.teal)
            if pattern.holdIn > 0 { seg("Hold", pattern.holdIn, SP.gold) }
            seg(pattern.hum ? "Hum" : "Out", pattern.exhale, SP.violet)
            if pattern.holdOut > 0 { seg("Rest", pattern.holdOut, SP.indigo) }
        }
    }

    private func seg(_ label: String, _ v: Double, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(BreathPattern.fmt(v)).font(SP.numbers(compact ? 15 : 22)).foregroundStyle(c)
            Text(label.uppercased()).font(SP.rounded(compact ? 8 : 9, .bold)).tracking(1).foregroundStyle(SP.faint)
        }
        .frame(minWidth: compact ? 30 : 46)
    }
}
