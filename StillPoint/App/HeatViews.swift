import SwiftUI
import Charts

enum HeatRoute: Hashable { case log }

// MARK: - Today card

/// Small "Heat" section: one tap as you walk into the sauna or steam room.
struct HeatCard: View {
    @EnvironmentObject var heat: HeatStore
    @State private var taps = 0

    var body: some View {
        Group {
            if let s = heat.active {
                ActiveHeatCard(session: s)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Heat").font(SP.serif(22)).foregroundStyle(SP.ink)
                        Spacer()
                        NavigationLink(value: HeatRoute.log) {
                            HStack(spacing: 4) {
                                Text(heat.history.isEmpty ? "Log" : "Log · \(heat.history.count)")
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                            .font(SP.rounded(13)).foregroundStyle(SP.dim)
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach(HeatKind.allCases) { k in
                            Button {
                                taps += 1
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { heat.start(k) }
                            } label: { HeatStartTile(kind: k) }
                            .buttonStyle(SoftPress())
                            .accessibilityLabel("Start \(k.title) timer")
                        }
                    }
                    Text("Tap as you walk in, or ask Siri to start the sauna. Heart rate from WHOOP fills in after.")
                        .font(SP.rounded(12)).foregroundStyle(SP.faint)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

struct HeatStartTile: View {
    let kind: HeatKind
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LinearGradient(colors: [kind.tint, kind.tint2], startPoint: .top, endPoint: .bottom))
                .frame(width: 38, height: 38)
                .background(Circle().fill(kind.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.short).font(SP.serif(18)).foregroundStyle(SP.ink)
                Text("Start timer").font(SP.rounded(11)).foregroundStyle(SP.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [kind.tint.opacity(0.20), kind.tint2.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(kind.tint.opacity(0.25), lineWidth: 1))
    }
}

/// The running session: big live clock, a gentle tip, Done.
struct ActiveHeatCard: View {
    let session: HeatSession
    @EnvironmentObject var heat: HeatStore
    @State private var confirmCancel = false
    @State private var doneTaps = 0

    var body: some View {
        let k = session.kind
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [k.tint.opacity(0.85), k.tint2.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HeatShimmer(color: .white)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: k.symbol)
                    Text("IN THE \(k.short.uppercased())").tracking(1.6)
                    Spacer()
                    Text("since \(session.start.formatted(date: .omitted, time: .shortened))")
                }
                .font(SP.rounded(12, .semibold)).foregroundStyle(.white.opacity(0.85))

                TimelineView(.periodic(from: session.start, by: 1)) { ctx in
                    let secs = ctx.date.timeIntervalSince(session.start)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spFormatClock(secs))
                            .font(SP.numbers(56)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text(tip(minutes: secs / 60, kind: k))
                            .font(SP.rounded(14)).foregroundStyle(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        doneTaps += 1
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { heat.finish() }
                    } label: {
                        Label("I'm out", systemImage: "checkmark")
                            .font(SP.rounded(16, .semibold))
                            .foregroundStyle(k.tint2)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(SoftPress())
                    .sensoryFeedback(.success, trigger: doneTaps)
                    Button("Cancel") { confirmCancel = true }
                        .font(SP.rounded(14)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: k.tint.opacity(0.35), radius: 24, y: 10)
        .confirmationDialog("Discard this session?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { withAnimation { heat.cancel() } }
        }
    }

    private func tip(minutes m: Double, kind: HeatKind) -> String {
        let limit = Double(kind.checkInMinutes)
        switch m {
        case ..<3: return "Settle in. Slow breaths through the nose."
        case ..<(limit * 0.5): return kind == .sauna ? "Sit low if it's too hot; heat rises." : "Let the steam open the airways. Breathe easy."
        case ..<limit: return "Listen to your body. Leave if you feel dizzy or sick."
        default: return "That's a full round. Step out, cool down, drink water."
        }
    }
}

/// Slow rising heat haze.
struct HeatShimmer: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                for i in 0..<14 {
                    let a = Double(i) * 1.37
                    let x = (0.5 + 0.45 * sin(a * 3.1 + t * 0.15)) * size.width
                    var y = (1 - (t * (0.03 + 0.01 * Double(i % 3)) + a).truncatingRemainder(dividingBy: 1)) * size.height
                    if y < 0 { y += size.height }
                    let r = 30 + 20 * abs(sin(a))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(0.05)))
                }
            }
        }
        .blur(radius: 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Log

struct HeatLogView: View {
    @EnvironmentObject var heat: HeatStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Heat log").font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                    Text(summary).font(SP.rounded(14)).foregroundStyle(SP.dim)
                }
                if let s = heat.active { ActiveHeatCard(session: s) }
                ForEach(heat.history) { s in
                    HeatSessionCard(session: s)
                        .contextMenu {
                            Button("Check Apple Health again", systemImage: "arrow.clockwise") { heat.lookUpHeart(s.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { heat.delete(s.id) } }
                        }
                }
                if heat.history.isEmpty && heat.active == nil {
                    Text("No sessions yet. Tap Sauna or Steam on the Today screen as you walk in.")
                        .font(SP.rounded(14)).foregroundStyle(SP.faint)
                }
                WhoopNote()
            }
            .padding(22)
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { heat.refreshMissing() }
        .onAppear { heat.refreshMissing() }
    }

    private var summary: String {
        let wk = Int(heat.thisWeekMinutes.rounded())
        return wk > 0 ? "\(wk) min of heat in the last 7 days." : "Sauna and steam sessions, with heart rate."
    }
}

struct HeatSessionCard: View {
    let session: HeatSession
    @EnvironmentObject var heat: HeatStore

    var body: some View {
        let k = session.kind
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: k.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(k.tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(k.tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.title).font(SP.serif(18)).foregroundStyle(SP.ink)
                    Text(session.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                        .font(SP.rounded(12)).foregroundStyle(SP.faint)
                }
                Spacer()
                Text("\(Int(session.minutes.rounded())) min").font(SP.numbers(22)).foregroundStyle(SP.ink)
            }

            if let h = session.heart {
                HStack(spacing: 8) {
                    StatChip(label: "avg", value: Int(h.avg.rounded()), tint: k.tint)
                    StatChip(label: "peak", value: Int(h.max.rounded()), tint: k.tint2)
                    StatChip(label: "low", value: Int(h.min.rounded()), tint: SP.teal)
                    Spacer()
                }
                if h.points.count > 2 {
                    Chart(h.points, id: \.t) { p in
                        AreaMark(x: .value("min", p.t / 60), y: .value("bpm", p.bpm))
                            .foregroundStyle(LinearGradient(colors: [k.tint.opacity(0.35), k.tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("min", p.t / 60), y: .value("bpm", p.bpm))
                            .foregroundStyle(k.tint)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: max(40, h.min - 8)...(h.max + 8))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel().foregroundStyle(SP.faint) } }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisValueLabel().foregroundStyle(SP.faint) } }
                    .frame(height: 110)
                }
                Text("Heart rate from \(h.sources.joined(separator: ", ")) via Apple Health")
                    .font(SP.rounded(11)).foregroundStyle(SP.faint)
            } else {
                HStack {
                    Image(systemName: "heart.slash").foregroundStyle(SP.faint)
                    Text(session.checked == nil ? "Looking up heart rate…" : "No heart rate yet. WHOOP can take a few minutes to sync.")
                        .font(SP.rounded(12)).foregroundStyle(SP.faint)
                    Spacer()
                    Button("Check") { heat.lookUpHeart(session.id) }
                        .font(SP.rounded(12, .semibold)).foregroundStyle(k.tint)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SP.stroke, lineWidth: 1))
    }
}

struct StatChip: View {
    let label: String
    let value: Int
    let tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(value)").font(SP.numbers(17)).foregroundStyle(SP.ink)
            Text(label).font(SP.rounded(11)).foregroundStyle(SP.dim)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct WhoopNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(SP.dim)
            Text("Using WHOOP? Turn on the Apple Health integration in the WHOOP app and allow Heart Rate. Still Point reads the readings that fall inside each sauna or steam session. An Apple Watch or Garmin works the same way.")
                .font(SP.rounded(12)).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card))
    }
}
