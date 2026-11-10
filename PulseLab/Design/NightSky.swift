import SwiftUI

/// Last night as a glowing stepped path over a night sky: stage bands, twinkling stars,
/// and a moon arc from bedtime to wake-up.
struct NightSkyHypnogram: View {
    let segments: [HypnoSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func color(_ s: SleepStage) -> Color {
        switch s {
        case .awake: Color(red: 1, green: 0.36, blue: 0.42)
        case .rem: Lab.violet
        case .core: Lab.watch
        case .deep: Color(red: 0.30, green: 0.36, blue: 1.0)
        }
    }

    private var start: Date { segments.map(\.start).min() ?? Date() }
    private var end: Date { segments.map(\.end).max() ?? Date() }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                timeLabel(start, "moon.stars.fill", "BED")
                Spacer()
                Text(fmtHM(end.timeIntervalSince(start) / 60)).font(Lab.number(18, .black)).foregroundStyle(Lab.text)
                    .shadow(color: Lab.violet.opacity(0.6), radius: 8)
                Spacer()
                timeLabel(end, "sun.max.fill", "UP")
            }
            ZStack {
                sky
                TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { tl in
                    Canvas { ctx, size in
                        drawStars(ctx, size, t: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                Canvas { ctx, size in
                    drawMoonArc(ctx, size)
                    drawBands(ctx, size)
                    drawPath(ctx, size)
                    drawTicks(ctx, size)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Lab.violet.opacity(0.35), lineWidth: 1))
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var sky: some View {
        LinearGradient(colors: [Color(red: 0.03, green: 0.02, blue: 0.12), Color(red: 0.08, green: 0.04, blue: 0.22), Color(red: 0.02, green: 0.02, blue: 0.06)],
                       startPoint: .top, endPoint: .bottom)
    }

    private func timeLabel(_ d: Date, _ icon: String, _ l: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Lab.warn)
            VStack(alignment: .leading, spacing: 0) {
                Text(l).font(Lab.label(7)).tracking(1.2).foregroundStyle(Lab.faint)
                Text(d.formatted(.dateTime.hour().minute())).font(Lab.mono(11, .heavy)).foregroundStyle(Lab.text)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([SleepStage.awake, .rem, .core, .deep]) { s in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(s)).frame(width: 10, height: 4).shadow(color: Self.color(s), radius: 3)
                    Text(s.title.uppercased()).font(Lab.label(8)).foregroundStyle(Lab.dim)
                }
            }
            Spacer()
        }
    }

    // Layout: the moon arc uses the top 26%, the stage rows the rest.
    private func rowY(_ level: Int, _ size: CGSize) -> CGFloat {
        let top = size.height * 0.30, bottom = size.height - 14
        let rowH = (bottom - top) / 4
        return top + rowH * (CGFloat(3 - level) + 0.5)
    }

    private func x(_ d: Date, _ size: CGSize) -> CGFloat {
        let total = max(1, end.timeIntervalSince(start))
        return 10 + (size.width - 20) * CGFloat(d.timeIntervalSince(start) / total)
    }

    private func drawStars(_ ctx: GraphicsContext, _ size: CGSize, t: TimeInterval) {
        var rng = DecoRandom(seed: 42)
        for i in 0..<46 {
            let px = rng.next() * size.width, py = rng.next() * size.height * 0.85
            let base = 0.25 + rng.next() * 0.5
            let tw = 0.5 + 0.5 * sin(t * (0.8 + Double(i % 5) * 0.35) + Double(i))
            let r = 0.6 + rng.next() * 1.1
            ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(base * (0.45 + 0.55 * tw))))
        }
    }

    private func drawMoonArc(_ ctx: GraphicsContext, _ size: CGSize) {
        let a = CGPoint(x: 18, y: size.height * 0.28), b = CGPoint(x: size.width - 18, y: size.height * 0.28)
        let ctrl = CGPoint(x: size.width / 2, y: -size.height * 0.05)
        var arc = Path()
        arc.move(to: a)
        arc.addQuadCurve(to: b, control: ctrl)
        ctx.stroke(arc, with: .color(Lab.warn.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        // Moon sits at the middle of the night (top of the arc).
        let m = CGPoint(x: size.width / 2, y: (a.y + 2 * ctrl.y + b.y) / 4)
        let moon = Path(ellipseIn: CGRect(x: m.x - 8, y: m.y - 8, width: 16, height: 16))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 8))
            l.fill(moon, with: .color(Lab.warn.opacity(0.8)))
        }
        ctx.fill(moon, with: .color(Color(red: 1, green: 0.95, blue: 0.8)))
        ctx.fill(Path(ellipseIn: CGRect(x: m.x - 3, y: m.y - 9, width: 14, height: 14)), with: .color(Color(red: 0.08, green: 0.04, blue: 0.22)))
    }

    private func drawBands(_ ctx: GraphicsContext, _ size: CGSize) {
        for s in SleepStage.allCases {
            let y = rowY(s.level, size)
            let rowH = (size.height - 14 - size.height * 0.30) / 4
            let r = CGRect(x: 0, y: y - rowH / 2, width: size.width, height: rowH)
            ctx.fill(Path(r), with: .color(Self.color(s).opacity(0.07)))
        }
    }

    private func drawPath(_ ctx: GraphicsContext, _ size: CGSize) {
        let segs = segments.sorted { $0.start < $1.start }
        // Thin white risers between stages.
        var risers = Path()
        for (i, seg) in segs.enumerated() where i > 0 {
            let xx = x(seg.start, size)
            risers.move(to: CGPoint(x: xx, y: rowY(segs[i - 1].stage.level, size)))
            risers.addLine(to: CGPoint(x: xx, y: rowY(seg.stage.level, size)))
        }
        ctx.stroke(risers, with: .color(Color.white.opacity(0.28)), lineWidth: 1)
        // Glowing stage runs.
        for seg in segs {
            var p = Path()
            let y = rowY(seg.stage.level, size)
            p.move(to: CGPoint(x: x(seg.start, size), y: y))
            p.addLine(to: CGPoint(x: max(x(seg.start, size) + 1.5, x(seg.end, size)), y: y))
            let c = Self.color(seg.stage)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.stroke(p, with: .color(c.opacity(0.9)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    /// Whole-hour ticks and labels along the bottom, on the same x scale as the stages.
    private func drawTicks(_ ctx: GraphicsContext, _ size: CGSize) {
        let cal = Calendar.current
        guard var h = cal.date(bySetting: .minute, value: 0, of: start).flatMap({ cal.date(bySetting: .second, value: 0, of: $0) }) else { return }
        if h < start { h = cal.date(byAdding: .hour, value: 1, to: h) ?? h }
        let f = DateFormatter(); f.dateFormat = "ha"
        var n = 0
        while h <= end && n < 16 {
            let xx = x(h, size)
            var tick = Path()
            tick.move(to: CGPoint(x: xx, y: size.height - 14))
            tick.addLine(to: CGPoint(x: xx, y: size.height - 9))
            ctx.stroke(tick, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
            if n % 2 == 0 || end.timeIntervalSince(start) < 5 * 3600 {
                let label = Text(f.string(from: h).lowercased()).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                ctx.draw(label, at: CGPoint(x: xx, y: size.height - 4), anchor: .center)
            }
            h = cal.date(byAdding: .hour, value: 1, to: h) ?? end.addingTimeInterval(1)
            n += 1
        }
    }

    private var summary: String {
        var mins: [SleepStage: Double] = [:]
        for s in segments { mins[s.stage, default: 0] += s.end.timeIntervalSince(s.start) / 60 }
        let parts = [SleepStage.deep, .core, .rem, .awake].map { "\($0.title) \(fmtHM(mins[$0]))" }
        return "Last night from \(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened)). " + parts.joined(separator: ", ")
    }
}
