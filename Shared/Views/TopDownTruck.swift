import SwiftUI

/// Bird's-eye 90s regular-cab, long-bed pickup that always points down the road.
/// `bearing` is the direction of travel relative to the screen (course − map heading),
/// and `pitch` is the map camera tilt, so the truck lies flat on the 3D road.
struct TopDownTruck: View {
    let bearing: Double      // degrees, 0 = up the screen
    let pitch: Double        // camera pitch in degrees
    let speed: Double        // m/s
    var overLimit = false

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce || speed < 0.3)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // Ground glow + soft shadow
                Ellipse()
                    .fill(RadialGradient(colors: [(overLimit ? Color.red : Theme.glow).opacity(0.55), .clear],
                                         center: .center, startRadius: 2, endRadius: 46))
                    .frame(width: 92, height: 92)
                    .scaleEffect(overLimit ? 1 + 0.08 * sin(t * 8) : 1)
                Canvas { ctx, size in draw(&ctx, size, t: t) }
                    .frame(width: 34, height: 74)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 3)
            }
            .rotationEffect(.degrees(shown))
            .rotation3DEffect(.degrees(min(70, pitch) * 0.85), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        }
        .frame(width: 96, height: 96)
        .onAppear { shown = bearing }
        .onChange(of: bearing) { _, new in
            // Turn the short way round (359° → 1° is a 2° turn, not a full spin).
            var delta = (new - shown).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
            withAnimation(.easeOut(duration: 0.6)) { shown += delta }
        }
        .accessibilityLabel("Your truck")
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let red = Color(red: 0.55, green: 0.06, blue: 0.08)
        let redHi = Color(red: 0.78, green: 0.14, blue: 0.16)
        let chrome = Color(white: 0.85)
        func rr(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: ww, height: hh), cornerRadius: r)
        }
        // Tires peeking out
        for (x, y) in [(0.0, 0.16), (w - 4, 0.16), (0.0, 0.70), (w - 4, 0.70)] {
            ctx.fill(rr(x, h * y, 4, h * 0.13, 1.5), with: .color(.black))
        }
        // Body
        ctx.fill(rr(2, 2, w - 4, h - 4, 6), with: .linearGradient(Gradient(colors: [redHi, red]),
                                                                  startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: 0)))
        // Hood with center crease
        ctx.stroke(Path { p in p.move(to: CGPoint(x: w / 2, y: 6)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.22)) },
                   with: .color(.white.opacity(0.18)), lineWidth: 1)
        // Front bumper + headlights
        ctx.fill(rr(3, 1, w - 6, 3, 1.5), with: .color(chrome))
        let beam = speed > 0.3 ? 0.85 + 0.15 * sin(t * 3) : 0.7
        ctx.fill(rr(4, 4, 7, 3, 1), with: .color(Color(red: 1, green: 0.97, blue: 0.8).opacity(beam)))
        ctx.fill(rr(w - 11, 4, 7, 3, 1), with: .color(Color(red: 1, green: 0.97, blue: 0.8).opacity(beam)))
        // Windshield, roof, back glass
        ctx.fill(rr(5, h * 0.24, w - 10, h * 0.07, 2), with: .color(Color(white: 0.1).opacity(0.9)))
        ctx.fill(rr(5, h * 0.31, w - 10, h * 0.13, 2), with: .linearGradient(Gradient(colors: [redHi, red]),
                                                                              startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: 0)))
        ctx.fill(rr(6, h * 0.44, w - 12, h * 0.025, 1), with: .color(Color(white: 0.1).opacity(0.9)))
        // Mirrors
        ctx.fill(rr(-2, h * 0.25, 3, 4, 1), with: .color(chrome))
        ctx.fill(rr(w - 1, h * 0.25, 3, 4, 1), with: .color(chrome))
        // Long bed: rails + floor
        ctx.fill(rr(5, h * 0.49, w - 10, h * 0.44, 2), with: .color(Color(white: 0.12)))
        ctx.stroke(rr(5, h * 0.49, w - 10, h * 0.44, 2), with: .color(chrome.opacity(0.8)), lineWidth: 1)
        for i in 1..<4 {
            let x = 5 + (w - 10) * CGFloat(i) / 4
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: h * 0.50)); p.addLine(to: CGPoint(x: x, y: h * 0.92)) },
                       with: .color(.white.opacity(0.08)), lineWidth: 1)
        }
        // Silver lower band along the sides
        ctx.fill(rr(2, h * 0.5, 2, h * 0.42, 1), with: .color(chrome.opacity(0.7)))
        ctx.fill(rr(w - 4, h * 0.5, 2, h * 0.42, 1), with: .color(chrome.opacity(0.7)))
        // Rear bumper + tail lights (glow when over the limit)
        ctx.fill(rr(3, h - 4, w - 6, 3, 1.5), with: .color(chrome))
        let tail = overLimit ? (0.6 + 0.4 * sin(t * 10)) : 0.55
        ctx.fill(rr(3, h - 8, 5, 4, 1), with: .color(Color.red.opacity(tail)))
        ctx.fill(rr(w - 8, h - 8, 5, 4, 1), with: .color(Color.red.opacity(tail)))
    }
}
