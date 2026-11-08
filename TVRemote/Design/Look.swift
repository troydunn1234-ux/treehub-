import SwiftUI

/// Clicker's look: deep midnight with electric magenta → violet → cyan accents.
enum Look {
    static let bg = Color(red: 0.035, green: 0.03, blue: 0.075)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.10)
    static let magenta = Color(red: 1.0, green: 0.24, blue: 0.62)
    static let violet = Color(red: 0.55, green: 0.33, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 1.0)
    static let dim = Color.white.opacity(0.55)
    static let accent = LinearGradient(colors: [magenta, violet, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// Slowly drifting color blobs behind everything.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Look.bg))
                let blobs: [(Color, Double, Double, Double)] = [(Look.magenta, 0.2, 0.15, 0.0), (Look.violet, 0.8, 0.35, 2.0), (Look.cyan, 0.4, 0.85, 4.0)]
                for (c, x, y, ph) in blobs {
                    let cx = size.width * (x + 0.08 * sin(t * 0.13 + ph))
                    let cy = size.height * (y + 0.06 * cos(t * 0.11 + ph))
                    let r = size.width * 0.75
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r / 2, y: cy - r / 2, width: r, height: r)),
                             with: .radialGradient(Gradient(colors: [c.opacity(0.28), .clear]), center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r / 2))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Springy press feel for any button.
struct SquishStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
