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

/// Today's rounds: who won each metric both trackers report, as a scoreboard plus one row per round.
struct RivalryHero: View {
    let rounds: [RivalryRound]
    let watchBPM: Double?
    let whoopBPM: Double?
    let readiness: Double?
    let recovery: Double?
    let note: String
    /// Off on Today, where the Recovery vs Readiness card above already shows both scores.
    var showGauges = true

    private var watchScore: Int { rounds.filter { $0.winner == .watch }.count }
    private var whoopScore: Int { rounds.filter { $0.winner == .whoop }.count }

    var body: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTag("Today's rounds")
                    Spacer()
                    if watchBPM != nil || whoopBPM != nil {
                        Text(bpmLabel).font(Lab.mono(12, .medium)).foregroundStyle(Lab.faint)
                            .accessibilityLabel("Resting heart rate, Watch then WHOOP: \(bpmLabel)")
                    }
                }
                scoreboard
                if showGauges {
                    HStack(alignment: .top) {
                        VStack(spacing: 6) {
                            ArcGauge(value: readiness, label: "Readiness", color: readiness.map(Lab.band) ?? Lab.faint, size: 120)
                            SourceChip(source: .watch)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 6) {
                            ArcGauge(value: recovery, label: "Recovery", color: recovery.map(Lab.band) ?? Lab.faint, size: 120)
                            SourceChip(source: .whoop)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if rounds.isEmpty {
                    EmptyNote(text: "Rounds appear when both trackers have today's numbers.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rounds.enumerated()), id: \.element.id) { i, r in
                            if i > 0 { Divider().overlay(Lab.line) }
                            roundRow(r)
                        }
                    }
                    .padding(.horizontal, Lab.S.sm)
                    .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
                }
                Text(note)
                    .font(.footnote).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bpmLabel: String {
        let w = watchBPM.map { "\(Int($0.rounded()))" } ?? "—", h = whoopBPM.map { "\(Int($0.rounded()))" } ?? "—"
        return "RHR \(w) / \(h) bpm"
    }

    private var scoreboard: some View {
        HStack(alignment: .center, spacing: 0) {
            side(.watch, watchScore, leading: true)
            Text("–").font(Lab.number(28)).foregroundStyle(Lab.faint).frame(width: 40)
            side(.whoop, whoopScore, leading: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rounds won today: Apple Watch \(watchScore), WHOOP \(whoopScore)")
    }

    private func side(_ s: Source, _ score: Int, leading: Bool) -> some View {
        let winning = (s == .watch ? watchScore > whoopScore : whoopScore > watchScore)
        return HStack(spacing: Lab.S.s) {
            if !leading { Spacer(minLength: 0) }
            if !leading { CountUp(value: Double(score), size: 40, color: Lab.color(s)) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                SourceChip(source: s)
                Text(winning ? String(localized: "Leading") : " ").font(.caption2.weight(.semibold)).foregroundStyle(Lab.color(s))
            }
            if leading { CountUp(value: Double(score), size: 40, color: Lab.color(s)) }
            if leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func roundRow(_ r: RivalryRound) -> some View {
        HStack(spacing: Lab.S.s) {
            Text(L(r.name)).font(.subheadline).foregroundStyle(Lab.text)
            Spacer(minLength: 4)
            Text(r.detail).font(Lab.mono(13, .medium)).foregroundStyle(Lab.dim)
                .lineLimit(1).minimumScaleFactor(0.8)
            Group {
                if let w = r.winner { SourceChip(source: w) }
                else {
                    Text("TIE").font(Lab.label(10)).foregroundStyle(Lab.faint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Lab.inset))
                }
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(r.name)): \(r.winner?.name ?? "tie"), \(r.detail)")
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

// MARK: - Arc gauge

/// 270° arc gauge (gap at the bottom), flat stroke, value in the middle.
struct ArcGauge: View {
    let value: Double?
    let label: String
    let color: Color
    var size: CGFloat = 128
    @State private var drawn: Double = 0

    var body: some View {
        let line = size * 0.085
        ZStack {
            SegmentArc(progress: 1, segments: 1)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .padding(line / 2)
            SegmentArc(progress: drawn / 100, segments: 1)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .padding(line / 2)
            VStack(spacing: 0) {
                CountUp(value: value, size: size * 0.27, color: Lab.text)
                Text(L(label)).font(Lab.label(10)).foregroundStyle(Lab.dim)
            }
            .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .onAppear { sweep() }
        .onChange(of: value) { _, _ in sweep() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(label)) \(value.map { Int($0.rounded()).description } ?? "not available")")
    }

    private func sweep() {
        let v = min(100, max(0, value ?? 0))
        if Lab.reduceMotion { drawn = v; return }
        drawn = 0
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.9)) { drawn = v } }
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
        let sweep = 270.0, seg = sweep / Double(segments), gap = segments > 1 ? 2.6 : 0
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
