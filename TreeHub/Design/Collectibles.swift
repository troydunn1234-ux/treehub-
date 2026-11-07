import SwiftUI

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
