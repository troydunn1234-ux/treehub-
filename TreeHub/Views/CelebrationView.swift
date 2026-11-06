import SwiftUI
import UIKit

/// The reward screen after logging a hug: XP tally, leaf reveal, new badges, level up.
struct CelebrationView: View {
    let data: CelebrationData
    var onDone: () -> Void

    @State private var step = 0
    @State private var xpShown = 0
    @State private var leafFlipped = false
    @State private var burst = false

    private var leveledUp: Bool { data.levelAfter.level > data.levelBefore.level }

    var body: some View {
        ZStack {
            ForestBackground()
            if burst { LeafBurst().allowsHitTesting(false) }
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55))
                            .symbolEffect(.bounce, value: step)
                        Text("Hug logged!").font(Theme.title(34)).foregroundStyle(.white)
                        Text("\(data.treeName) felt that.").font(Theme.rounded(16, .medium)).foregroundStyle(Theme.textDim)
                    }
                    .padding(.top, 40)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("+\(xpShown) XP").font(.system(size: 40, weight: .black, design: .rounded))
                                    .foregroundStyle(Theme.goldGradient)
                                    .contentTransition(.numericText())
                                Spacer()
                                if leveledUp && step >= 1 {
                                    VStack(alignment: .trailing) {
                                        Text("LEVEL UP").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                                        Text("\(data.levelAfter.level) · \(data.levelAfter.title)").font(Theme.rounded(15, .bold))
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            ForEach(Array(data.breakdown.lines.enumerated()), id: \.offset) { _, line in
                                HStack {
                                    Text(line.0).font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim)
                                    Spacer()
                                    Text("+\(line.1)").font(Theme.rounded(14, .bold)).foregroundStyle(Theme.glow)
                                }
                            }
                        }
                    }

                    if let leaf = data.leaf, step >= 1 {
                        VStack(spacing: 10) {
                            Text(leafFlipped ? "You found a leaf!" : "A leaf is falling…")
                                .font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                            ZStack {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(leafFlipped
                                          ? AnyShapeStyle(RadialGradient(colors: [leaf.rarity.color.opacity(0.55), Theme.forestDeep],
                                                                         center: .center, startRadius: 5, endRadius: 140))
                                          : AnyShapeStyle(Theme.moss))
                                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(leafFlipped ? leaf.rarity.color : Theme.cardStroke, lineWidth: 2))
                                if leafFlipped {
                                    VStack(spacing: 10) {
                                        LeafView(leaf: leaf, size: 96)
                                        Text(leaf.name).font(Theme.title(22)).foregroundStyle(.white)
                                        RarityLabel(rarity: leaf.rarity)
                                        Text(leaf.blurb).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding()
                                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                                } else {
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 54, weight: .black, design: .rounded))
                                        .foregroundStyle(Theme.glow.opacity(0.7))
                                }
                            }
                            .frame(width: 230, height: 260)
                            .rotation3DEffect(.degrees(leafFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                            .onTapGesture { flip() }
                            if !leafFlipped {
                                Text("Tap to reveal").font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if !data.newBadges.isEmpty && leafFlipped {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: data.newBadges.count == 1 ? "Badge unlocked" : "\(data.newBadges.count) badges unlocked",
                                          symbol: "rosette")
                            ForEach(data.newBadges) { b in
                                HStack(spacing: 14) {
                                    Medallion(symbol: b.symbol, rarity: b.rarity, earned: true, size: 56)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(b.name).font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                                        Text(b.detail).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                                        RarityLabel(rarity: b.rarity)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button("Back to the forest", action: onDone)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .task { await run() }
    }

    private func flip() {
        guard !leafFlipped else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { leafFlipped = true }
        if let leaf = data.leaf, leaf.rarity >= .rare {
            burst = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func run() async {
        burst = true
        let target = data.breakdown.total
        let steps = 24
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: 35_000_000)
            withAnimation(.snappy) { xpShown = Int(Double(target) * Double(i) / Double(steps)) }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { step = 1 }
        if leveledUp { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        burst = false
        if data.leaf == nil || DemoData.isOn { withAnimation { leafFlipped = true } }
    }
}

/// Leaves bursting out from the center.
struct LeafBurst: View {
    @State private var start = Date()
    private let pieces: [(angle: Double, dist: Double, spin: Double, color: Int, size: Double)] = {
        var r = SeededRNG(seed: "burst")
        return (0..<36).map { _ in (r.next() * .pi * 2, 160 + r.next() * 260, (r.next() - 0.5) * 8, Int(r.next() * 4), 12 + r.next() * 16) }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = min(1.6, ctx.date.timeIntervalSince(start))
                let p = 1 - pow(1 - min(1, t / 1.1), 3)
                let colors: [Color] = [Theme.glow, Theme.gold, Color(red: 1, green: 0.5, blue: 0.3), Theme.leaf]
                for piece in pieces {
                    var g = gc
                    let x = size.width / 2 + cos(piece.angle) * piece.dist * p
                    let y = size.height * 0.35 + sin(piece.angle) * piece.dist * p + 120 * t * t
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(piece.spin * t))
                    g.opacity = max(0, 1 - t / 1.6)
                    let s = piece.size
                    g.fill(LeafPath(shape: .oval).path(in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s)), with: .color(colors[piece.color]))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }
}
