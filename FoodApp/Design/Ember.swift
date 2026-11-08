import SwiftUI

/// Food Book's look: warm charcoal with an ember glow (orange → hot pink), cream text.
enum Ember {
    static let bg = Color(red: 0.07, green: 0.05, blue: 0.05)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.09)
    static let cream = Color(red: 1.0, green: 0.95, blue: 0.88)
    static let dim = Color(red: 1.0, green: 0.95, blue: 0.88).opacity(0.55)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.47)
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let protein = Color(red: 0.42, green: 0.78, blue: 1.0)
    static let carbs = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let fat = Color(red: 1.0, green: 0.45, blue: 0.55)
    static let fire = LinearGradient(colors: [gold, orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func font(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .rounded) }
}

/// Slow drifting ember glows behind the app.
struct EmberBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduce)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ember.bg))
                for (c, x, y, ph) in [(Ember.orange, 0.15, 0.05, 0.0), (Ember.pink, 0.95, 0.3, 2.0), (Ember.gold, 0.4, 1.0, 4.0)] {
                    let cx = size.width * (x + 0.06 * sin(t * 0.12 + ph)), cy = size.height * (y + 0.05 * cos(t * 0.1 + ph))
                    let r = size.width * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r / 2, y: cy - r / 2, width: r, height: r)),
                             with: .radialGradient(Gradient(colors: [c.opacity(0.22), .clear]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r / 2))
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
