import SwiftUI

// Small finishing touches for the iPhone app: drifting fireflies, a soft press on cards,
// the week-of-practice dots, and a short thought for the day.

/// A handful of warm specks that drift and breathe very slowly behind the content.
struct Fireflies: View {
    var count = 14
    var tint: Color = SP.gold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<count {
                    let k = Double(i)
                    let bx = Self.unit(k * 12.9898) * size.width
                    let by = Self.unit(k * 78.233) * size.height
                    let x = bx + sin(t / (11 + k.truncatingRemainder(dividingBy: 5)) + k) * 26
                    let y = by + cos(t / (14 + k.truncatingRemainder(dividingBy: 7)) + k * 1.7) * 34
                    let pulse = 0.5 + 0.5 * sin(t / (2.6 + k.truncatingRemainder(dividingBy: 3)) + k * 2.1)
                    let r = 1.2 + Self.unit(k * 3.7) * 1.8
                    let glow = CGRect(x: x - r * 5, y: y - r * 5, width: r * 10, height: r * 10)
                    ctx.fill(Path(ellipseIn: glow), with: .radialGradient(
                        Gradient(colors: [tint.opacity(0.22 * pulse), .clear]),
                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 5))
                    let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: dot), with: .color(tint.opacity(0.25 + 0.5 * pulse)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    /// Stable pseudo-random 0…1 from a seed, so the specks keep their places between launches.
    private static func unit(_ seed: Double) -> Double {
        let v = sin(seed) * 43758.5453
        return v - v.rounded(.down)
    }
}

/// Cards and tiles sink a touch and spring back, like pressing into something soft.
struct SoftPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Seven small dots for the last seven days. Practiced days glow gold; today wears a ring.
struct WeekDots: View {
    let days: [DayMinutes]

    private static let letters: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            ForEach(days) { d in
                let done = d.minutes > 0
                let today = Calendar.current.isDateInToday(d.day)
                VStack(spacing: 5) {
                    ZStack {
                        if done {
                            Circle().fill(SP.gold.opacity(0.25)).frame(width: 18, height: 18).blur(radius: 4)
                        }
                        Circle()
                            .fill(done ? AnyShapeStyle(SP.goldGlow) : AnyShapeStyle(Color.white.opacity(0.10)))
                            .frame(width: 9, height: 9)
                        if today {
                            Circle().stroke(SP.ink.opacity(0.55), lineWidth: 1).frame(width: 16, height: 16)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(Self.letters.string(from: d.day))
                        .font(SP.rounded(10, today ? .semibold : .regular))
                        .foregroundStyle(today ? SP.ink.opacity(0.8) : SP.faint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practiced \(days.filter { $0.minutes > 0 }.count) of the last 7 days")
    }
}

/// One short line a day, the same all day, changing at midnight.
enum DailyThought {
    static let lines = [
        "The breath is always here. Come back to it.",
        "Nothing to fix. Just notice.",
        "Slow is a kind of strength.",
        "Let the shoulders fall. Let the jaw soften.",
        "You don't have to finish anything to rest.",
        "Each exhale is a small letting go.",
        "Feel your feet. You are held.",
        "Thoughts are weather. You are the sky.",
        "One kind breath is enough for now.",
        "Quiet isn't empty. It's full of room.",
        "Begin again. Begin again.",
        "Listen to the space between sounds.",
        "Tension is a message, not a verdict.",
        "Soft eyes, soft belly, slow breath.",
    ]

    static var today: String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return lines[day % lines.count]
    }
}
