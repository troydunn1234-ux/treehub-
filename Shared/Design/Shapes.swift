import SwiftUI

enum LeafShape { case oval, heart, ginkgo, maple, oak, needle }

/// Hand-drawn leaf silhouettes for the collectible leaves.
struct LeafPath: Shape {
    var shape: LeafShape

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        switch shape {
        case .oval:
            path.move(to: p(0.5, 0.02))
            path.addCurve(to: p(0.5, 0.86), control1: p(0.98, 0.25), control2: p(0.85, 0.75))
            path.addCurve(to: p(0.5, 0.02), control1: p(0.15, 0.75), control2: p(0.02, 0.25))
            path.move(to: p(0.5, 0.84))
            path.addLine(to: p(0.5, 0.98))
        case .heart:
            path.move(to: p(0.5, 0.88))
            path.addCurve(to: p(0.5, 0.22), control1: p(0.0, 0.6), control2: p(0.02, 0.05))
            path.addCurve(to: p(0.5, 0.88), control1: p(0.98, 0.05), control2: p(1.0, 0.6))
            path.move(to: p(0.5, 0.86))
            path.addLine(to: p(0.5, 0.99))
        case .ginkgo:
            path.move(to: p(0.5, 0.98))
            path.addLine(to: p(0.47, 0.6))
            path.addCurve(to: p(0.04, 0.22), control1: p(0.3, 0.52), control2: p(0.04, 0.42))
            path.addQuadCurve(to: p(0.44, 0.1), control: p(0.22, 0.04))
            path.addLine(to: p(0.5, 0.22))
            path.addLine(to: p(0.56, 0.1))
            path.addQuadCurve(to: p(0.96, 0.22), control: p(0.78, 0.04))
            path.addCurve(to: p(0.53, 0.6), control1: p(0.96, 0.42), control2: p(0.7, 0.52))
            path.closeSubpath()
        case .maple:
            let pts: [(CGFloat, CGFloat)] = [
                (0.5, 0.02), (0.6, 0.22), (0.72, 0.16), (0.68, 0.36), (0.92, 0.26), (0.84, 0.44), (0.98, 0.5),
                (0.74, 0.62), (0.78, 0.74), (0.54, 0.68), (0.52, 0.98), (0.48, 0.98), (0.46, 0.68), (0.22, 0.74),
                (0.26, 0.62), (0.02, 0.5), (0.16, 0.44), (0.08, 0.26), (0.32, 0.36), (0.28, 0.16), (0.4, 0.22)]
            path.move(to: p(pts[0].0, pts[0].1))
            for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
            path.closeSubpath()
        case .oak:
            path.move(to: p(0.5, 0.02))
            let right: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.72, 0.12, 0.58, 0.24), (0.84, 0.3, 0.62, 0.42), (0.86, 0.52, 0.62, 0.6), (0.74, 0.74, 0.54, 0.8)]
            for s in right { path.addQuadCurve(to: p(s.2, s.3), control: p(s.0, s.1)) }
            path.addLine(to: p(0.52, 0.98))
            path.addLine(to: p(0.48, 0.98))
            path.addLine(to: p(0.46, 0.8))
            let left: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.26, 0.74, 0.38, 0.6), (0.14, 0.52, 0.38, 0.42), (0.16, 0.3, 0.42, 0.24), (0.28, 0.12, 0.5, 0.02)]
            for s in left { path.addQuadCurve(to: p(s.2, s.3), control: p(s.0, s.1)) }
            path.closeSubpath()
        case .needle:
            path.move(to: p(0.5, 0.02))
            path.addLine(to: p(0.5, 0.98))
            for i in 0..<9 {
                let y = 0.1 + CGFloat(i) * 0.09
                let len = 0.36 - abs(CGFloat(i) - 4) * 0.03
                path.move(to: p(0.5, y))
                path.addLine(to: p(0.5 + len, y + 0.07))
                path.move(to: p(0.5, y))
                path.addLine(to: p(0.5 - len, y + 0.07))
            }
        }
        return path
    }
}

/// Small deterministic random generator seeded from a string.
struct SeededRNG {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        state = h == 0 ? 0x9E3779B97F4A7C15 : h
    }

    mutating func next() -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}
