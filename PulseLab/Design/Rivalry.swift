import SwiftUI

// MARK: - Rounds

/// One head-to-head "round" on Today: who won a metric.
struct RivalryRound: Identifiable {
    let name: String
    let winner: Source?
    let detail: String
    var id: String { name }
}

enum Rivalry {
    /// Today's rounds. Only metrics both trackers have count; exact ties count for nobody.
    @MainActor static func rounds(_ store: LabStore) -> [RivalryRound] {
        var out: [RivalryRound] = []
        func add(_ name: String, _ w: Double?, _ h: Double?, higherWins: Bool, _ fmt: (Double) -> String) {
            guard let w, let h else { return }
            let winner: Source? = w == h ? nil : ((w > h) == higherWins ? .watch : .whoop)
            out.append(RivalryRound(name: name, winner: winner, detail: "\(fmt(w)) vs \(fmt(h))"))
        }
        let int: (Double) -> String = { "\(Int($0.rounded()))" }
        add("Ready", store.readinessToday, store.recoveryToday, higherWins: true, int)
        let ws = store.lastNight(.watch), hs = store.lastNight(.whoop)
        add("Sleep", ws.map(\.asleepMin), hs.map(\.asleepMin), higherWins: true) { fmtHM($0) }
        add("Deep", ws.map(\.deepMin), hs.map(\.deepMin), higherWins: true) { fmtHM($0) }
        let w = store.today(.watch), h = store.today(.whoop)
        add("Resting HR", w?.rhr, h?.rhr, higherWins: false, int)
        add("HRV trend", hrvVsBaseline(store, .watch), hrvVsBaseline(store, .whoop), higherWins: true) { "\(Int(($0 * 100 - 100).rounded()))%" }
        add("Breathing", w?.resp, h?.resp, higherWins: false) { String(format: "%.1f", $0) }
        return out
    }

    /// Today's HRV ÷ the source's own 7-day average (so SDNN and RMSSD compare fairly).
    @MainActor private static func hrvVsBaseline(_ store: LabStore, _ s: Source) -> Double? {
        let recent = store.days(s).recent(8)
        guard let today = recent.last?.hrv else { return nil }
        guard let base = Stats.mean(recent.dropLast().compactMap(\.hrv)), base > 0 else { return nil }
        return today / base
    }
}

// MARK: - Hero

/// The Today hero: live EKG, rounds-won scoreboard, segmented readiness / recovery gauges,
/// over a split cyan/amber background with a moving perspective grid floor.
struct RivalryHero: View {
    let rounds: [RivalryRound]
    let watchBPM: Double?
    let whoopBPM: Double?
    let readiness: Double?
    let recovery: Double?
    let note: String

    private var watchScore: Int { rounds.filter { $0.winner == .watch }.count }
    private var whoopScore: Int { rounds.filter { $0.winner == .whoop }.count }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                LiveDot(color: Lab.bad, size: 6)
                Text("LIVE RIVALRY").font(Lab.label(10)).tracking(2.4).foregroundStyle(Lab.text)
                Spacer()
                Text(bpmLabel).font(Lab.label(9)).tracking(1.2).foregroundStyle(Lab.dim)
            }
            EKGStrip(watchBPM: watchBPM ?? 60, whoopBPM: whoopBPM ?? (watchBPM ?? 60) + 1)
                .frame(height: 64)
            scoreboard
            HStack(alignment: .top) {
                VStack(spacing: 6) {
                    ArcGauge(value: readiness, label: "Readiness", color: Lab.watch, size: 128)
                    SourceChip(source: .watch)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 6) {
                    ArcGauge(value: recovery, label: "Recovery", color: recovery.map(Lab.band) ?? Lab.whoop, size: 128)
                    SourceChip(source: .whoop)
                }
                .frame(maxWidth: .infinity)
            }
            if !rounds.isEmpty { roundChips }
            Text(note)
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(HeroBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.8), Lab.violet.opacity(0.3), Lab.whoop.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
        )
        .shadow(color: Lab.watch.opacity(0.18), radius: 24, x: -8, y: 8)
        .shadow(color: Lab.whoop.opacity(0.16), radius: 24, x: 8, y: 8)
    }

    private var bpmLabel: String {
        let w = watchBPM.map { "\(Int($0.rounded()))" } ?? "––", h = whoopBPM.map { "\(Int($0.rounded()))" } ?? "––"
        return "\(w) / \(h) BPM"
    }

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 0) {
            side(.watch, "applewatch", watchScore, leading: true)
            VStack(spacing: 2) {
                Text("VS").font(Lab.display(20)).foregroundStyle(Lab.duel)
                Text("ROUNDS").font(Lab.label(7)).tracking(1.5).foregroundStyle(Lab.faint)
            }
            .frame(width: 70)
            side(.whoop, "bolt.heart.fill", whoopScore, leading: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rounds won today: Apple Watch \(watchScore), WHOOP \(whoopScore)")
    }

    private func side(_ s: Source, _ glyph: String, _ score: Int, leading: Bool) -> some View {
        let winning = (s == .watch ? watchScore > whoopScore : whoopScore > watchScore)
        return HStack(spacing: 10) {
            if !leading { Spacer(minLength: 0) }
            if leading { glyphView(s, glyph) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 0) {
                HStack(spacing: 4) {
                    if winning && !leading { Image(systemName: "crown.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.color(s)) }
                    Text(s.short).font(Lab.label(10)).tracking(2).foregroundStyle(Lab.color(s))
                    if winning && leading { Image(systemName: "crown.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.color(s)) }
                }
                CountUp(value: Double(score), size: 44, color: Lab.color(s))
            }
            if !leading { glyphView(s, glyph) }
            if leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func glyphView(_ s: Source, _ glyph: String) -> some View {
        Image(systemName: glyph)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Lab.color(s))
            .frame(width: 44, height: 44)
            .background(Circle().fill(Lab.color(s).opacity(0.14)))
            .overlay(Circle().strokeBorder(Lab.color(s).opacity(0.5), lineWidth: 1))
            .shadow(color: Lab.color(s).opacity(0.6), radius: 10)
    }

    private var roundChips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(rounds) { r in
                VStack(spacing: 2) {
                    Text(r.name.uppercased()).font(Lab.label(7)).tracking(1).foregroundStyle(Lab.dim).lineLimit(1)
                    Text(r.winner?.short ?? "TIE").font(Lab.label(9)).tracking(1.2)
                        .foregroundStyle(r.winner.map(Lab.color) ?? Lab.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill((r.winner.map(Lab.color) ?? Color.white).opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder((r.winner.map(Lab.color) ?? Color.white).opacity(0.25), lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.name): \(r.winner?.name ?? "tie"), \(r.detail)")
            }
        }
    }
}

/// Split diagonal background (cyan left, amber right), faint speckle, and a perspective grid floor that drifts toward you.
struct HeroBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Lab.panel.opacity(0.92)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    p.move(to: .zero); p.addLine(to: CGPoint(x: w * 0.58, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.42, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Lab.watch.opacity(0.22), Lab.watch.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.58, y: 0)); p.addLine(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w * 0.42, y: h)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Lab.whoop.opacity(0.20), Lab.whoop.opacity(0.02)], startPoint: .topTrailing, endPoint: .bottomLeading))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.58, y: 0)); p.addLine(to: CGPoint(x: w * 0.42, y: h))
                }
                .stroke(LinearGradient(colors: [Lab.watch.opacity(0.35), Lab.whoop.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            Canvas { ctx, size in
                // Fixed speckle "noise".
                var rng = DecoRandom(seed: 7)
                for _ in 0..<160 {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color.white.opacity(0.05 + rng.next() * 0.06)))
                }
            }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
                Canvas { ctx, size in
                    let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    GridFloor.draw(ctx, size: size, t: t)
                }
            }
            .mask(LinearGradient(colors: [.clear, .clear, .black], startPoint: .top, endPoint: .bottom))
        }
        .allowsHitTesting(false)
    }
}

enum GridFloor {
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: TimeInterval) {
        let horizon = size.height * 0.52
        let vanish = CGPoint(x: size.width / 2, y: horizon)
        var p = Path()
        for i in -10...10 {
            let x = size.width / 2 + CGFloat(i) * size.width / 7
            p.move(to: vanish); p.addLine(to: CGPoint(x: x, y: size.height))
        }
        let drift = CGFloat((t * 0.35).truncatingRemainder(dividingBy: 1))
        for k in 0..<9 {
            let f = (CGFloat(k) + drift) / 9          // 0 at horizon, 1 at bottom
            let y = horizon + (size.height - horizon) * f * f
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.stroke(p, with: .color(Lab.violet.opacity(0.22)), lineWidth: 0.7)
    }
}

/// Tiny deterministic random generator so decorative noise doesn't flicker between redraws.
struct DecoRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}

// MARK: - EKG

/// Two scrolling heartbeat traces (Watch cyan above, WHOOP amber below), each beating at that tracker's resting HR.
struct EKGStrip: View {
    let watchBPM: Double
    let whoopBPM: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 1.3 : tl.date.timeIntervalSinceReferenceDate
                Self.trace(ctx, size: size, t: t, bpm: watchBPM, color: Lab.watch, yOffset: -size.height * 0.12, phase: 0)
                Self.trace(ctx, size: size, t: t, bpm: whoopBPM, color: Lab.whoop, yOffset: size.height * 0.16, phase: 0.37)
            }
        }
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }

    /// One beat: P wave, sharp QRS, T wave. `f` is the position inside the beat (0–1).
    static func wave(_ f: Double) -> Double {
        func g(_ c: Double, _ w: Double, _ a: Double) -> Double { a * exp(-pow((f - c) / w, 2)) }
        return g(0.18, 0.025, 0.12) + g(0.29, 0.008, -0.14) + g(0.31, 0.009, 1.0) + g(0.335, 0.010, -0.28) + g(0.52, 0.040, 0.26)
    }

    static func trace(_ ctx: GraphicsContext, size: CGSize, t: TimeInterval, bpm: Double, color: Color, yOffset: CGFloat, phase: Double) {
        let window = 3.2                         // seconds visible
        let beatsPerSec = max(30, min(200, bpm)) / 60
        let mid = size.height / 2 + yOffset
        let amp = size.height * 0.36
        var path = Path()
        var x: CGFloat = 0
        var last = CGPoint.zero
        while x <= size.width {
            let time = t - (1 - Double(x / size.width)) * window
            let beats = time * beatsPerSec + phase
            let f = beats - floor(beats)
            last = CGPoint(x: x, y: mid - CGFloat(wave(f)) * amp)
            if x == 0 { path.move(to: last) } else { path.addLine(to: last) }
            x += 2
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.stroke(path, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        let dot = Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(dot, with: .color(color))
        }
        ctx.fill(dot, with: .color(.white))
    }
}

// MARK: - Segmented arc gauge

/// 270° gauge made of segments, with tick marks, an inner glow and a sweep-up animation.
struct ArcGauge: View {
    let value: Double?
    let label: String
    let color: Color
    var size: CGFloat = 128
    @State private var drawn: Double = 0

    var body: some View {
        let line = size * 0.11
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.22), .clear], center: .center, startRadius: 2, endRadius: size * 0.45))
                .padding(line)
            SegmentArc(progress: 1)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .padding(line / 2)
            SegmentArc(progress: drawn / 100)
                .stroke(AngularGradient(colors: [color.opacity(0.45), color, color], center: .center, startAngle: .degrees(135), endAngle: .degrees(405)),
                        style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .padding(line / 2)
                .shadow(color: color.opacity(0.75), radius: 9)
            GaugeTicks()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .padding(-3)
            VStack(spacing: 0) {
                CountUp(value: value, size: size * 0.27, color: Lab.text)
                Text(label.uppercased()).font(Lab.label(8)).tracking(1.4).foregroundStyle(color)
            }
            .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear { sweep() }
        .onChange(of: value) { _, _ in sweep() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value.map { Int($0).description } ?? "not available")")
    }

    private func sweep() {
        let v = min(100, max(0, value ?? 0))
        if Lab.reduceMotion { drawn = v; return }
        drawn = 0
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 1.1)) { drawn = v } }
        guard value != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        }
    }
}

/// The filled part of a segmented 270° arc (gap at the bottom). Animatable.
struct SegmentArc: Shape {
    var progress: Double
    var segments = 28
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), radius = min(r.width, r.height) / 2
        let sweep = 270.0, seg = sweep / Double(segments), gap = 2.6
        let filled = min(1, max(0, progress)) * Double(segments)
        for i in 0..<segments {
            let part = min(1, filled - Double(i))
            guard part > 0 else { break }
            let a0 = 135 + Double(i) * seg
            let a1 = a0 + (seg - gap) * part
            let start = CGPoint(x: c.x + radius * CGFloat(cos(a0 * .pi / 180)), y: c.y + radius * CGFloat(sin(a0 * .pi / 180)))
            p.move(to: start)
            p.addArc(center: c, radius: radius, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
        }
        return p
    }
}

/// Short ticks every 10% just outside the arc.
struct GaugeTicks: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), outer = min(r.width, r.height) / 2, inner = outer - 4
        for i in 0...10 {
            let a = (135 + Double(i) * 27) * .pi / 180
            p.move(to: CGPoint(x: c.x + inner * CGFloat(cos(a)), y: c.y + inner * CGFloat(sin(a))))
            p.addLine(to: CGPoint(x: c.x + outer * CGFloat(cos(a)), y: c.y + outer * CGFloat(sin(a))))
        }
        return p
    }
}
