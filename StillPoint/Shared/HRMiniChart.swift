import SwiftUI

/// A tiny heart-rate line drawn with a Path (no Charts on watchOS needed).
struct HRMiniChart: View {
    let samples: [HRSample]
    var tint: Color = SP.teal

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let lo = (samples.map(\.bpm).min() ?? 50) - 3
            let hi = (samples.map(\.bpm).max() ?? 90) + 3
            let span = max(1, hi - lo)
            let tMax = max(1, samples.last?.t ?? 1)
            let pts: [CGPoint] = samples.map { s in
                CGPoint(x: CGFloat(s.t / tMax) * w, y: h - CGFloat((s.bpm - lo) / span) * h)
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: h))
                    p.addLine(to: f)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: pts.last?.x ?? w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                if let low = pts.max(by: { $0.y < $1.y }) {
                    Circle().fill(SP.amber).frame(width: 5, height: 5).position(low)
                }
            }
        }
        .accessibilityLabel("Heart rate over the session")
    }
}
