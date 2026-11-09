import SwiftUI

/// "WATCH VS WHOOP" title that slams in like a fighting-game intro (fades in under Reduce Motion).
struct VSSlam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inPlace = false

    var body: some View {
        HStack(spacing: 10) {
            fighter("applewatch", "WATCH", Lab.watch)
                .offset(x: inPlace || reduceMotion ? 0 : -140)
            Text("VS")
                .font(.system(size: 54, weight: .black, design: .rounded).width(.compressed))
                .italic()
                .foregroundStyle(LinearGradient(colors: [Lab.watch, .white, Lab.whoop], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Lab.violet, radius: inPlace ? 14 : 0)
                .scaleEffect(inPlace || reduceMotion ? 1 : 2.6)
                .rotationEffect(.degrees(inPlace || reduceMotion ? -6 : 8))
                .opacity(inPlace || reduceMotion ? 1 : 0)
            fighter("bolt.heart.fill", "WHOOP", Lab.whoop)
                .offset(x: inPlace || reduceMotion ? 0 : 140)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear {
            guard !reduceMotion else { inPlace = true; return }
            inPlace = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { inPlace = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Watch versus WHOOP")
    }

    private func fighter(_ glyph: String, _ name: String, _ c: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: glyph).font(.system(size: 26, weight: .bold)).foregroundStyle(c)
                .frame(width: 56, height: 56)
                .background(Circle().fill(c.opacity(0.14)))
                .overlay(Circle().strokeBorder(c.opacity(0.6), lineWidth: 1.2))
                .shadow(color: c.opacity(0.7), radius: 12)
            Text(name).font(Lab.label(10)).tracking(2.4).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One metric as opposing health bars meeting in the middle. The tracker that reads higher pushes
/// the meeting point toward the other side. Agreement % sits in a center badge; the winner gets a crown.
struct FightRow: View {
    let round: Int
    let agreement: Agreement
    let winner: (Source, String)?
    let selected: Bool
    let action: () -> Void

    @State private var shown: Double = 0.5

    /// Watch share of the bar (0–1). Trend-only metrics (HRV) stay centered.
    private var share: Double {
        guard !agreement.trendOnly, let w = agreement.meanWatch, let h = agreement.meanWhoop, w + h > 0 else { return 0.5 }
        // Exaggerate small gaps so a 2 bpm difference is still visible, but clamp to keep both bars on screen.
        let raw = w / (w + h)
        return min(0.82, max(0.18, 0.5 + (raw - 0.5) * 6))
    }

    private var agreeColor: Color { agreement.score >= 70 ? Lab.good : agreement.score >= 45 ? Lab.warn : Lab.bad }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ROUND \(round)").font(Lab.label(9)).tracking(2).foregroundStyle(Lab.faint)
                    Text(agreement.metric.uppercased()).font(Lab.display(15, .heavy)).foregroundStyle(Lab.text)
                    Spacer()
                    if let w = winner { CrownChip(source: w.0, label: w.1) }
                }
                bars
                HStack {
                    value(agreement.meanWatch, Lab.watch, leading: true)
                    Spacer()
                    Text(agreement.verdict + " · \(agreement.n)d").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Lab.dim).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    value(agreement.meanWhoop, Lab.whoop, leading: false)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lab.panel.opacity(selected ? 1 : 0.8)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: selected ? 1.5 : 1)
            )
            .shadow(color: selected ? Lab.violet.opacity(0.35) : .clear, radius: 14)
        }
        .buttonStyle(.plain)
        .onAppear { animate() }
        .onChange(of: agreement.n) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Round \(round), \(agreement.metric). Apple Watch \(fmt(agreement.meanWatch)), WHOOP \(fmt(agreement.meanWhoop)) \(agreement.unit). \(agreement.agreePercent.map { "\(Int($0)) percent agreement" } ?? ""). \(winner.map { "\($0.0.name) \($0.1.lowercased())" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }

    private var bars: some View {
        GeometryReader { geo in
            let w = geo.size.width, split = w * shown
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.05))
                // Watch bar from the left.
                Capsule()
                    .fill(LinearGradient(colors: [Lab.watch.opacity(0.35), Lab.watch], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, split - 2))
                    .shadow(color: Lab.watch.opacity(0.7), radius: 6)
                // WHOOP bar from the right.
                Capsule()
                    .fill(LinearGradient(colors: [Lab.whoop, Lab.whoop.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, w - split - 2))
                    .offset(x: split + 2)
                    .shadow(color: Lab.whoop.opacity(0.7), radius: 6)
                // Center badge at the clash point.
                Text(agreement.agreePercent.map { "\(Int($0))%" } ?? "––")
                    .font(Lab.number(12, .black))
                    .foregroundStyle(agreeColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Lab.bg))
                    .overlay(Capsule().strokeBorder(agreeColor.opacity(0.8), lineWidth: 1))
                    .shadow(color: agreeColor.opacity(0.6), radius: 6)
                    .fixedSize()
                    .position(x: min(max(split, 26), w - 26), y: geo.size.height / 2)
            }
        }
        .frame(height: 22)
    }

    private func value(_ v: Double?, _ c: Color, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
            Text(fmt(v)).font(Lab.number(20, .black)).foregroundStyle(c).shadow(color: c.opacity(0.5), radius: 6)
            Text(agreement.unit).font(Lab.label(7)).foregroundStyle(Lab.faint)
        }
    }

    private func fmt(_ v: Double?) -> String {
        v.map { String(format: abs($0) < 10 ? "%.1f" : "%.0f", $0) } ?? "––"
    }

    private func animate() {
        let target = share
        if Lab.reduceMotion { shown = target; return }
        shown = 0.5
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.05 * Double(round))) { shown = target }
    }
}
