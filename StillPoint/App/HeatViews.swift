import SwiftUI
import Charts

enum HeatRoute: Hashable { case log }

extension HeatKind {
    /// Names in the person's language (the shared enum keeps plain English for the Watch).
    var localizedTitle: String { NSLocalizedString(title, comment: "Sauna or steam room") }
    var localizedShort: String { NSLocalizedString(short, comment: "Sauna or steam, short") }
}

// MARK: - Today card

/// Small "Heat" section: one tap as you walk into the sauna or steam room.
struct HeatCard: View {
    @EnvironmentObject var heat: HeatStore
    @State private var taps = 0
    @State private var finishes = 0
    @State private var showGuide = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let s = heat.active {
                ActiveHeatCard(session: s, openGuide: { showGuide = true }, onFinish: { finishes += 1 })
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.97).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: SP.s3) {
                    header
                    HeatStartRow { k in
                        taps += 1
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) { heat.start(k) }
                        showGuide = true
                    }
                    Text("Tap as you walk in: the timer and a heat-safe guide start together. Heart rate fills in after.")
                        .font(.footnote).foregroundStyle(SP.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    // Just finished a round: a soft "round done", then cooling down outside with a tree (Rootbound).
                    if let last = heat.history.first, let end = last.end, Date().timeIntervalSince(end) < 45 * 60 {
                        HeatJustDoneRow(session: last)
                        RootboundLinkCard(title: "Cool down outside",
                                          subtitle: "Step out, breathe the fresh air and hug a tree. Rootbound logs it.")
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        // "I'm out" on the live card: the card itself is gone by then, so the success tap is played from here.
        .sensoryFeedback(.success, trigger: finishes)
        .fullScreenCover(isPresented: $showGuide) {
            HeatGuideView().environmentObject(heat)
        }
    }

    /// "Sauna & steam" with the log link on the right, like the other Today sections.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sauna & steam").font(.headline).foregroundStyle(SP.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: SP.s2)
            NavigationLink(value: HeatRoute.log) {
                HStack(spacing: SP.s1) {
                    if heat.history.isEmpty {
                        Text("Log")
                    } else {
                        Text("Log · \(heat.history.count)").contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
                }
                .font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(SP.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(heat.history.isEmpty ? Text("Heat log") : Text("Heat log, \(heat.history.count) sessions"))
        }
    }
}

/// Sauna and steam, one tap each: side by side, stacked at the largest text sizes.
struct HeatStartRow: View {
    let start: (HeatKind) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: SP.s3)) : AnyLayout(HStackLayout(spacing: SP.s3))
        layout {
            ForEach(HeatKind.allCases) { k in
                Button { start(k) } label: { HeatStartTile(kind: k) }
                    .buttonStyle(SoftPress())
                    .accessibilityLabel(Text("Start \(k.localizedTitle) timer"))
            }
        }
    }
}

struct HeatStartTile: View {
    let kind: HeatKind
    var body: some View {
        HStack(spacing: SP.s3) {
            Image(systemName: kind.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(kind.tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(kind.tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.localizedShort).font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink)
                Text("Start timer").font(.footnote).foregroundStyle(SP.faint)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SP.s3)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SP.radius, style: .continuous)
                .fill(LinearGradient(colors: [kind.tint.opacity(0.16), SP.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: SP.radius, style: .continuous))
    }
}

/// Just out of the heat: "Round done" with a soft ripple (only in the first moments after I'm out).
struct HeatJustDoneRow: View {
    let session: HeatSession
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// I'm out was tapped moments ago (not a revisit of Today later on).
    private var fresh: Bool { session.end.map { Date().timeIntervalSince($0) < 30 } ?? false }

    var body: some View {
        let k = session.kind
        HStack(spacing: SP.s3) {
            Image(systemName: "drop.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(k.tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(k.tint.opacity(0.16)))
                .background {
                    if fresh { CalmRipple(tint: k.tint, rings: 2, duration: 2.4).frame(width: 76, height: 76) }
                }
                .symbolEffect(.bounce, value: shown)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Round done · \(k.localizedShort) \(Int(session.minutes.rounded())) min")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink)
                    .monospacedDigit()
                Text("Cool down slowly and drink some water.")
                    .font(.footnote).foregroundStyle(SP.dim)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .spCard(padding: SP.s3, tint: k.tint)
        .accessibilityElement(children: .combine)
        .onAppear { if fresh && !reduceMotion { shown = true } }
    }
}

/// The running session: big live clock, a gentle tip, I'm out.
struct ActiveHeatCard: View {
    let session: HeatSession
    /// Opens the breathing & movement guide; nil when already inside it.
    var openGuide: (() -> Void)? = nil
    /// Told when I'm out is tapped (the Today card plays the success tap, as this card disappears with it).
    var onFinish: (() -> Void)? = nil
    @EnvironmentObject var heat: HeatStore
    @State private var confirmCancel = false
    @State private var doneTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let k = session.kind
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack(spacing: SP.s2) {
                Image(systemName: k.symbol)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: !reduceMotion)
                    .accessibilityHidden(true)
                Group {
                    if k == .sauna { Text("In the sauna") } else { Text("In the steam room") }
                }
                .textCase(.uppercase).tracking(1.2)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: SP.s2)
                Text("since \(session.start.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(SP.dim)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(k.tint)

            TimelineView(.periodic(from: session.start, by: 1)) { ctx in
                let secs = max(0, ctx.date.timeIntervalSince(session.start))
                VStack(alignment: .leading, spacing: SP.s1) {
                    Text(spFormatClock(secs))
                        .font(SP.numbers(54)).foregroundStyle(SP.ink)
                        .contentTransition(.numericText())
                        .accessibilityLabel(Text("\(Int(secs / 60)) minutes so far"))
                    Text(tip(minutes: secs / 60, kind: k))
                        .font(.subheadline).foregroundStyle(SP.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // One row of buttons; stacked when big text needs the room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SP.s2) {
                    outButton(fullWidth: false)
                    if let openGuide { guideButton(openGuide, fullWidth: false) }
                    Spacer(minLength: 0)
                    cancelButton
                }
                VStack(alignment: .leading, spacing: SP.s2) {
                    outButton(fullWidth: true)
                    if let openGuide { guideButton(openGuide, fullWidth: true) }
                    cancelButton
                }
            }
            .padding(.top, SP.s1)
        }
        .padding(SP.s4 + SP.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Warm and alive: the heat's colour, a low ember (sauna) or lit-mist (steam) glow that swells slowly,
            // and the rising haze. All of it holds still with Reduce Motion.
            ZStack {
                RoundedRectangle(cornerRadius: SP.radius, style: .continuous)
                    .fill(LinearGradient(colors: [k.tint.opacity(0.22), k.tint2.opacity(0.10), SP.card],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                EmberGlow(kind: k)
                HeatShimmer(color: k.tint, second: k.tint2)
            }
            .clipShape(RoundedRectangle(cornerRadius: SP.radius, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(k.tint.opacity(0.30), lineWidth: 1))
        // On Today the parent plays it (onFinish); in the heat log this card does.
        .sensoryFeedback(.success, trigger: onFinish == nil ? doneTaps : 0)
        .confirmationDialog("Discard this session?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { withAnimation { heat.cancel() } }
        }
    }

    private func outButton(fullWidth: Bool) -> some View {
        Button {
            doneTaps += 1
            onFinish?()
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) { heat.finish() }
        } label: {
            Label("I'm out", systemImage: "checkmark")
        }
        .buttonStyle(SPPrimaryButtonStyle(fullWidth: fullWidth))
    }

    private func guideButton(_ open: @escaping () -> Void, fullWidth: Bool) -> some View {
        Button(action: open) {
            Label("Guide", systemImage: "wind").frame(minHeight: 50)
        }
        .buttonStyle(SPSecondaryButtonStyle(fullWidth: fullWidth))
    }

    private var cancelButton: some View {
        Button { confirmCancel = true } label: {
            Text("Cancel").font(.subheadline).foregroundStyle(SP.dim)
                .padding(.horizontal, SP.s2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tip(minutes m: Double, kind: HeatKind) -> LocalizedStringKey {
        let limit = Double(kind.checkInMinutes)
        switch m {
        case ..<3: return "Settle in. Slow breaths through the nose."
        case ..<(limit * 0.5): return kind == .sauna ? "Sit low if it's too hot; heat rises." : "Let the steam open the airways. Breathe easy."
        case ..<limit: return "Listen to your body. Leave if you feel dizzy or sick."
        default: return "That's a full round. Step out, cool down, drink water."
        }
    }
}

/// Slow rising heat haze, with a gentle side-to-side waver; every other wisp in the second colour.
struct HeatShimmer: View {
    var color: Color
    /// The deeper heat colour for every other wisp (nil: all in `color`).
    var second: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                for i in 0..<16 {
                    let a = Double(i) * 1.37
                    let waver: Double = 0.04 * sin(t * 0.9 + a * 2.3)
                    let fx: Double = 0.5 + 0.45 * sin(a * 3.1 + t * 0.15) + waver
                    let x = fx * size.width
                    var y = (1 - (t * (0.03 + 0.01 * Double(i % 3)) + a).truncatingRemainder(dividingBy: 1)) * size.height
                    if y < 0 { y += size.height }
                    let r = 30 + 20 * abs(sin(a))
                    let c = (i % 2 == 1 ? second : nil) ?? color
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(c.opacity(i % 2 == 1 ? 0.06 : 0.05)))
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
    @EnvironmentObject var router: Router
    @State private var starts = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SP.s6) {
                VStack(alignment: .leading, spacing: SP.s1) {
                    Text("Heat log").font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(summary).font(.subheadline).foregroundStyle(SP.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, SP.s2)

                if let s = heat.active {
                    ActiveHeatCard(session: s, openGuide: { router.showHeatGuide = true })
                }

                if heat.history.isEmpty && heat.active == nil {
                    emptyState
                }

                if !heat.history.isEmpty {
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Sessions", detail: "\(heat.history.count)")
                        ForEach(heat.history) { s in
                            HeatSessionCard(session: s)
                                .contextMenu {
                                    Button("Check Apple Health again", systemImage: "arrow.clockwise") { heat.lookUpHeart(s.id) }
                                    Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { heat.delete(s.id) } }
                                }
                        }
                    }
                    RecoveryCard()
                }
                WhoopNote()
            }
            .padding(.horizontal, SP.screenPadding)
            .padding(.bottom, SP.s8)
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { heat.refreshMissing() }
        .onAppear { heat.refreshMissing() }
        .sensoryFeedback(.impact(weight: .medium), trigger: starts)
    }

    /// Nothing logged yet: say what this is, and offer both timers right here.
    private var emptyState: some View {
        VStack(spacing: SP.s3) {
            SPEmptyState(symbol: "flame",
                         title: String(localized: "No heat sessions yet"),
                         hint: String(localized: "Start a timer as you walk in. Heart rate from your Watch or WHOOP fills in after."))
            HeatStartRow { k in
                starts += 1
                router.handle(heat: k)
            }
        }
        .spCard()
    }

    private var summary: String {
        let wk = Int(heat.thisWeekMinutes.rounded())
        return wk > 0 ? String(localized: "\(wk) min of heat in the last 7 days.")
                      : String(localized: "Sauna and steam sessions, with heart rate.")
    }
}

struct HeatSessionCard: View {
    let session: HeatSession
    @EnvironmentObject var heat: HeatStore
    @State private var checks = 0

    var body: some View {
        let k = session.kind
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack(spacing: SP.s3) {
                Image(systemName: k.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(k.tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(k.tint.opacity(0.15)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.localizedTitle).font(.headline).foregroundStyle(SP.ink)
                    Text(session.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                        .font(.footnote).foregroundStyle(SP.faint)
                }
                Spacer(minLength: SP.s2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(session.minutes.rounded()))")
                        .font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                        .foregroundStyle(SP.ink)
                    Text("min").font(.footnote).foregroundStyle(SP.dim)
                }
                .accessibilityElement(children: .combine)
            }

            if let h = session.heart {
                SPFlow(spacing: SP.s2) {
                    StatChip(label: String(localized: "avg"), value: Int(h.avg.rounded()), tint: k.tint)
                    StatChip(label: String(localized: "peak"), value: Int(h.max.rounded()), tint: k.tint2)
                    StatChip(label: String(localized: "low"), value: Int(h.min.rounded()), tint: SP.teal)
                }
                if h.points.count > 2 {
                    chart(h, tint: k.tint)
                }
                Text("Heart rate from \(h.sources.joined(separator: ", ")) via Apple Health")
                    .font(.caption).foregroundStyle(SP.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } else if session.checked == nil {
                // Still asking Apple Health: placeholders instead of a spinner.
                HStack(spacing: SP.s2) {
                    SPSkeleton(height: 28, width: 76, radius: 14)
                    SPSkeleton(height: 28, width: 76, radius: 14)
                    Spacer(minLength: 0)
                }
                Text("Looking up heart rate…").font(.footnote).foregroundStyle(SP.faint)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SP.s3) {
                        missingNote
                        Spacer(minLength: SP.s2)
                        checkButton
                    }
                    VStack(alignment: .leading, spacing: SP.s2) {
                        missingNote
                        checkButton
                    }
                }
            }
        }
        .spCard()
        .sensoryFeedback(.impact(weight: .light), trigger: checks)
    }

    private var missingNote: some View {
        HStack(alignment: .top, spacing: SP.s2) {
            Image(systemName: "heart.slash").foregroundStyle(SP.faint).accessibilityHidden(true)
            Text("No heart rate yet. WHOOP can take a few minutes to sync.")
                .font(.footnote).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checkButton: some View {
        Button {
            checks += 1
            heat.lookUpHeart(session.id)
        } label: {
            Label("Check again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(SPSecondaryButtonStyle())
    }

    private func chart(_ h: HeartWindow, tint: Color) -> some View {
        Chart(h.points, id: \.t) { p in
            AreaMark(x: .value("min", p.t / 60), y: .value("bpm", p.bpm))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("min", p.t / 60), y: .value("bpm", p.bpm))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: max(40, h.min - 8)...(h.max + 8))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(.caption2, design: .rounded).monospacedDigit()).foregroundStyle(SP.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().font(.system(.caption2, design: .rounded).monospacedDigit()).foregroundStyle(SP.faint)
            }
        }
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate during the session, \(Int(h.min.rounded())) to \(Int(h.max.rounded())) bpm"))
    }
}

struct StatChip: View {
    let label: String
    let value: Int
    let tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(value)").font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(SP.ink)
            Text(label).font(.caption).foregroundStyle(SP.dim)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) \(value) bpm"))
    }
}

struct WhoopNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: SP.s3) {
            Image(systemName: "info.circle").foregroundStyle(SP.accent).accessibilityHidden(true)
            Text("Using WHOOP? Turn on the Apple Health integration in the WHOOP app and allow Heart Rate. Still Pointz reads the readings that fall inside each sauna or steam session. An Apple Watch or Garmin works the same way.")
                .font(.footnote).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .spCard(padding: SP.s3 + 2)
    }
}
