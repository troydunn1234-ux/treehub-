import SwiftUI

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

struct LeafView: View {
    let leaf: LeafType
    var size: CGFloat = 60
    var collected: Bool = true

    var body: some View {
        let grad = LinearGradient(colors: leaf.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            if leaf.shape == .needle {
                LeafPath(shape: .needle)
                    .stroke(collected ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.18)),
                            style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
            } else {
                LeafPath(shape: leaf.shape)
                    .fill(collected ? AnyShapeStyle(grad) : AnyShapeStyle(Color.white.opacity(0.12)))
                LeafPath(shape: leaf.shape)
                    .stroke(Color.white.opacity(collected ? 0.25 : 0.1), lineWidth: 1)
                // Center vein
                Path { p in
                    p.move(to: CGPoint(x: size / 2, y: size * 0.18))
                    p.addLine(to: CGPoint(x: size / 2, y: size * 0.92))
                }
                .stroke(Color.white.opacity(collected ? 0.35 : 0.08), lineWidth: max(1, size * 0.02))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: collected && leaf.rarity >= .epic ? leaf.colors[0].opacity(0.8) : .clear, radius: size * 0.18)
    }
}

/// Round badge medallion with rarity ring.
struct Medallion: View {
    let symbol: String
    let rarity: Rarity
    var earned: Bool
    var size: CGFloat = 64
    @State private var shimmer = false

    var body: some View {
        ZStack {
            Circle()
                .fill(earned
                      ? AnyShapeStyle(RadialGradient(colors: [rarity.color.opacity(0.95), rarity.color.opacity(0.35)],
                                                     center: .topLeading, startRadius: 2, endRadius: size))
                      : AnyShapeStyle(Color.white.opacity(0.06)))
            Circle()
                .strokeBorder(earned
                              ? AnyShapeStyle(AngularGradient(colors: [rarity.color, .white, rarity.color, rarity.color.opacity(0.5), rarity.color],
                                                              center: .center, angle: .degrees(shimmer ? 360 : 0)))
                              : AnyShapeStyle(Color.white.opacity(0.15)),
                              lineWidth: size * 0.07)
            Image(systemName: earned ? symbol : "lock.fill")
                .font(.system(size: size * (earned ? 0.4 : 0.3), weight: .bold))
                .foregroundStyle(earned ? .white : Color.white.opacity(0.35))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: earned ? rarity.color.opacity(rarity >= .epic ? 0.7 : 0.35) : .clear, radius: size * 0.15)
        .onAppear {
            guard earned, rarity >= .epic else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { shimmer = true }
        }
    }
}

struct RarityLabel: View {
    let rarity: Rarity
    var body: some View {
        Text(rarity.title.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(rarity == .common ? Theme.forestDeep : .white)
            .background(rarity.color, in: Capsule())
    }
}

struct HeartsView: View {
    let filled: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < filled ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < filled ? Color(red: 1, green: 0.45, blue: 0.55) : Color.white.opacity(0.25))
            }
        }
    }
}

/// XP ring with level number in the middle.
struct LevelRing: View {
    let info: LevelInfo
    var size: CGFloat = 96
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.glow.opacity(0.6), radius: 6)
            VStack(spacing: -2) {
                Text("LVL").font(.system(size: size * 0.12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textDim)
                Text("\(info.level)").font(.system(size: size * 0.36, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = info.progress } }
        .onChange(of: info.progress) { _, new in withAnimation(.easeOut(duration: 0.8)) { shown = new } }
    }
}
