import SwiftUI

/// Soft "painted" landscapes drawn with gradients and shapes — one mood per tradition.
enum SceneKind: CaseIterable { case mountains, mist, water, moon, dunes, forest }

extension Tradition {
    var scene: SceneKind {
        let k = (id + " " + name + " " + region + " " + origin).lowercased()
        if k.contains("tibet") || k.contains("himalaya") || k.contains("bön") || k.contains("bon") { return .mountains }
        if k.contains("zen") || k.contains("japan") || k.contains("forest bathing") || k.contains("shinrin") { return .mist }
        if k.contains("sufi") || k.contains("islam") || k.contains("persia") || k.contains("arab") { return .dunes }
        if k.contains("dao") || k.contains("tao") || k.contains("china") || k.contains("qigong") { return .water }
        if k.contains("christ") || k.contains("hesych") || k.contains("monastic") || k.contains("prayer") { return .moon }
        if k.contains("thai") || k.contains("theravada") || k.contains("forest") || k.contains("vipassana") { return .forest }
        if k.contains("yoga") || k.contains("india") || k.contains("vedic") { return .water }
        let all = SceneKind.allCases
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return all[sum % all.count]
    }
}

struct PaintedScene: View {
    var kind: SceneKind
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [SP.nightTop, tint.opacity(0.55), SP.amber.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                // Low sun / moon
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.85), SP.amber.opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: h * 0.28))
                    .frame(width: h * 0.56, height: h * 0.56)
                    .position(x: w * (kind == .moon ? 0.72 : 0.62), y: h * (kind == .moon ? 0.28 : 0.52))
                    .blur(radius: 1)
                layers(w: w, h: h)
                Grain(opacity: 0.07)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func layers(w: CGFloat, h: CGFloat) -> some View {
        switch kind {
        case .mountains:
            ridge(w, h, base: 0.62, peaks: [0.15, 0.40, 0.68, 0.9], height: 0.36, color: SP.plum.opacity(0.75))
            ridge(w, h, base: 0.78, peaks: [0.05, 0.3, 0.55, 0.82], height: 0.30, color: SP.nightTop.opacity(0.9))
            mistBand(w, h, y: 0.72, color: .white.opacity(0.10))
        case .mist:
            hills(w, h, y: 0.66, amp: 0.05, color: SP.plum.opacity(0.55))
            mistBand(w, h, y: 0.62, color: .white.opacity(0.18))
            hills(w, h, y: 0.80, amp: 0.04, color: SP.nightTop.opacity(0.85))
            mistBand(w, h, y: 0.82, color: .white.opacity(0.10))
        case .water:
            hills(w, h, y: 0.60, amp: 0.06, color: SP.plum.opacity(0.6))
            Rectangle().fill(LinearGradient(colors: [tint.opacity(0.35), SP.nightBottom.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .frame(height: h * 0.38).position(x: w / 2, y: h * 0.81)
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.18 - Double(i) * 0.03))
                    .frame(width: w * (0.18 - CGFloat(i) * 0.02), height: 1.5)
                    .position(x: w * 0.62, y: h * (0.68 + CGFloat(i) * 0.06))
            }
        case .moon:
            ForEach(0..<14, id: \.self) { i in
                Circle().fill(Color.white.opacity(0.5))
                    .frame(width: 1.6, height: 1.6)
                    .position(x: w * CGFloat((i * 37 % 100)) / 100, y: h * CGFloat((i * 53 % 45)) / 100)
            }
            hills(w, h, y: 0.74, amp: 0.05, color: SP.nightTop.opacity(0.9))
        case .dunes:
            hills(w, h, y: 0.64, amp: 0.08, color: SP.amber.opacity(0.35))
            hills(w, h, y: 0.76, amp: 0.07, color: SP.plum.opacity(0.75))
            hills(w, h, y: 0.88, amp: 0.05, color: SP.nightTop.opacity(0.9))
        case .forest:
            hills(w, h, y: 0.70, amp: 0.04, color: SP.plum.opacity(0.6))
            ForEach(0..<9, id: \.self) { i in
                let x = w * (0.05 + CGFloat(i) * 0.115)
                let th = h * (0.22 + CGFloat((i * 7) % 5) * 0.03)
                Path { p in
                    p.move(to: CGPoint(x: x, y: h * 0.86 - th))
                    p.addLine(to: CGPoint(x: x - th * 0.22, y: h * 0.86))
                    p.addLine(to: CGPoint(x: x + th * 0.22, y: h * 0.86))
                    p.closeSubpath()
                }
                .fill(SP.nightTop.opacity(0.85))
            }
            Rectangle().fill(SP.nightBottom.opacity(0.9)).frame(height: h * 0.16).position(x: w / 2, y: h * 0.93)
            mistBand(w, h, y: 0.80, color: .white.opacity(0.08))
        }
    }

    private func ridge(_ w: CGFloat, _ h: CGFloat, base: CGFloat, peaks: [CGFloat], height: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: h * base))
            var lastX: CGFloat = 0
            for (i, px) in peaks.enumerated() {
                let peakH = h * (base - height * (i % 2 == 0 ? 1.0 : 0.7))
                p.addLine(to: CGPoint(x: (lastX + w * px) / 2, y: h * base * 0.98))
                p.addLine(to: CGPoint(x: w * px, y: peakH))
                lastX = w * px
            }
            p.addLine(to: CGPoint(x: w, y: h * base))
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: [color, color.opacity(0.95)], startPoint: .top, endPoint: .bottom))
    }

    private func hills(_ w: CGFloat, _ h: CGFloat, y: CGFloat, amp: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: h * y))
            let steps = 24
            for s in 0...steps {
                let x = w * CGFloat(s) / CGFloat(steps)
                let yy = h * (y - amp * CGFloat(sin(Double(s) / Double(steps) * .pi * 2.2 + Double(y) * 10)))
                p.addLine(to: CGPoint(x: x, y: yy))
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
        }
        .fill(color)
    }

    private func mistBand(_ w: CGFloat, _ h: CGFloat, y: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: w * 1.3, height: h * 0.08)
            .blur(radius: h * 0.04)
            .position(x: w / 2, y: h * y)
    }
}
