import SwiftUI

/// "Watch vs WHOOP" title that slams in like a fighting-game intro (fades in under Reduce Motion).
struct VSSlam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inPlace = false

    var body: some View {
        HStack(spacing: 10) {
            fighter("applewatch", "Watch", Lab.watch)
                .offset(x: inPlace || reduceMotion ? 0 : -140)
            Text("VS")
                .font(.system(size: 54, weight: .bold, design: .rounded).width(.compressed))
                .italic()
                .foregroundStyle(LinearGradient(colors: [Lab.watch, .white, Lab.whoop], startPoint: .topLeading, endPoint: .bottomTrailing))
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
            Text(name).font(.footnote.weight(.semibold)).foregroundStyle(c)
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
            VStack(alignment: .leading, spacing: Lab.S.s) {
                HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Round \(round)").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
                        Text(L(agreement.metric)).font(.headline).foregroundStyle(Lab.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Lab.S.xs)
                    if let w = winner { CrownChip(source: w.0, label: w.1) }
                }
                bars
                HStack(alignment: .firstTextBaseline) {
                    value(agreement.meanWatch, Lab.watch, leading: true)
                    Spacer(minLength: Lab.S.xs)
                    VStack(spacing: 1) {
                        Text(agreement.verdict).font(.caption.weight(.medium)).foregroundStyle(Lab.dim)
                            .multilineTextAlignment(.center)
                            .lineLimit(2).minimumScaleFactor(0.85)
                        Text("\(agreement.n) days").font(.caption2).foregroundStyle(Lab.faint)
                    }
                    Spacer(minLength: Lab.S.xs)
                    value(agreement.meanWhoop, Lab.whoop, leading: false)
                }
            }
            .padding(Lab.S.m - 2)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Lab.radius, style: .continuous)
                    .strokeBorder(selected ? Lab.accent : Lab.line, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onAppear { animate() }
        .onChange(of: agreement.n) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Shows the day-by-day detail below")
    }

    private var spoken: String {
        var parts = [String(localized: "Round \(round), \(L(agreement.metric))"),
                     "\(Source.watch.name) \(fmt(agreement.meanWatch)) \(agreement.unit), \(Source.whoop.name) \(fmt(agreement.meanWhoop)) \(agreement.unit)",
                     agreement.verdict]
        if let p = agreement.agreePercent { parts.append(String(localized: "\(Int(p.rounded())) percent agreement")) }
        if let w = winner { parts.append("\(w.0.name) \(w.1)") }
        return parts.joined(separator: ". ")
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
                // WHOOP bar from the right.
                Capsule()
                    .fill(LinearGradient(colors: [Lab.whoop, Lab.whoop.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, w - split - 2))
                    .offset(x: split + 2)
                // Center badge at the clash point.
                Text(agreement.agreePercent.map { "\(Int($0))%" } ?? "—")
                    .font(Lab.number(12, .black))
                    .foregroundStyle(agreeColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Lab.bg))
                    .overlay(Capsule().strokeBorder(agreeColor.opacity(0.8), lineWidth: 1))
                    .fixedSize()
                    .position(x: min(max(split, 26), w - 26), y: geo.size.height / 2)
            }
        }
        .frame(height: 22)
    }

    private func value(_ v: Double?, _ c: Color, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
            Text(fmt(v)).font(Lab.number(20)).foregroundStyle(v == nil ? Lab.faint : c)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(agreement.unit).font(Lab.label(9)).foregroundStyle(Lab.faint)
        }
    }

    private func fmt(_ v: Double?) -> String {
        v.map { String(format: abs($0) < 10 ? "%.1f" : "%.0f", $0) } ?? "—"
    }

    private func animate() {
        let target = share
        if Lab.reduceMotion { shown = target; return }
        shown = 0.5
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.05 * Double(round))) { shown = target }
    }
}
