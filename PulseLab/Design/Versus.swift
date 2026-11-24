import SwiftUI

// The face-off look, used by the Today hero (AgreementCard): Watch on the left in cyan, WHOOP on the right in
// amber. Decorative only: nothing here reads or saves data.

// MARK: - Wordmark

/// "Watch vs WHOOP" in the two data colours: Watch cyan, a quiet "vs", WHOOP amber.
struct VersusWordmark: View {
    var font: Font = .subheadline.weight(.bold)

    var body: some View {
        (Text(verbatim: Source.watch.label).foregroundStyle(Lab.watch)
            + Text(verbatim: " vs ").foregroundStyle(Lab.faint)
            + Text(verbatim: Source.whoop.label).foregroundStyle(Lab.whoop))
            .font(font)
            .lineLimit(1)
            .accessibilityLabel(Text("Watch versus WHOOP"))
    }
}

// MARK: - Hero panel

/// The hero card: the one card style plus a faint cyan wash on the Watch side, amber on the WHOOP side and a
/// two-tone hairline. `scan` plays one faint scanner line across it each time it changes.
struct VersusPanel<Content: View>: View {
    var scan = 0
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Lab.radius, style: .continuous)
        content
            .padding(Lab.S.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(Lab.panel)
                    .overlay(shape.fill(LinearGradient(stops: [
                        .init(color: Lab.watch.opacity(0.09), location: 0),
                        .init(color: .clear, location: 0.42),
                        .init(color: .clear, location: 0.58),
                        .init(color: Lab.whoop.opacity(0.09), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)))
            }
            .overlay(ScanSweep(trigger: scan).clipShape(shape))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.32), Lab.line, Lab.whoop.opacity(0.32)],
                                                       startPoint: .leading, endPoint: .trailing), lineWidth: 1))
    }
}

/// One faint scanner line across a card, played when `trigger` changes (the score loading). Nothing under
/// Reduce Motion.
struct ScanSweep: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Position of the line as a share of the width; parked off the trailing edge between runs.
    @State private var x: CGFloat = 1.3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(colors: [.clear, Color.white.opacity(0.055), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w * 0.3)
                Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1)
            }
            .frame(height: geo.size.height)
            .offset(x: x * w - w * 0.15)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if trigger > 0 { run() } }
        .onChange(of: trigger) { _, _ in run() }
    }

    private func run() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { x = -0.25 }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 1.15)) { x = 1.3 }
        }
    }
}

// MARK: - Score ring

/// Today's agreement score as two arcs that start together at the bottom, Watch up the left in cyan and WHOOP up
/// the right in amber, and meet at the top only when the two trackers fully agree (the gap at the top is what they
/// disagree on). Sweeps in when it appears or the score changes, beats gently at about your resting heart rate,
/// and sparks where the arcs meet when `celebrate` changes. Lab-dial ticks around the outside. Still under
/// Reduce Motion.
struct VersusRing: View {
    /// 0–100; nil = no score yet.
    let score: Double?
    var size: CGFloat = 104
    /// Resting heart rate for the beat (kept to 40–100 bpm); nil beats at a calm 60.
    var bpm: Double? = nil
    /// A sync is running and there's no score yet: a slow scanning arc instead.
    var scanning = false
    /// Bumped by the card when the two fully agree: sparks at the top, once.
    var celebrate = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    /// False while the ring is scrolled out of sight (iOS 18+): the beat stops there instead of redrawing every
    /// frame for nobody.
    @State private var onScreen = true
    /// The first sweep (in from zero) has run for this view.
    @State private var swept = false

    private struct Beat { var pump: Double = 0 }

    private var line: CGFloat { max(6, (size * 0.08).rounded()) }
    /// Room outside the ring for the dial ticks.
    private var inset: CGFloat { max(6, (size * 0.07).rounded()) }
    /// Radius of the ring's centre line, measured from the middle of the view.
    private var ringRadius: CGFloat { size / 2 - inset - line / 2 }
    private var target: Double { min(100, max(0, score ?? 0)) }
    private var period: Double { 60 / min(100, max(40, bpm ?? 60)) }

    var body: some View {
        ZStack {
            DialTicks().stroke(Color.white.opacity(0.10), lineWidth: 1)
            DialTicks(major: true).stroke(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            Group {
                if reduceMotion || score == nil || !onScreen {
                    face(pump: 0)
                } else {
                    KeyframeAnimator(initialValue: Beat(), repeating: true) { beat in
                        face(pump: beat.pump)
                    } keyframes: { _ in
                        // Lub-dub, then rest: one beat per period.
                        KeyframeTrack(\.pump) {
                            CubicKeyframe(1, duration: period * 0.09)
                            CubicKeyframe(0.2, duration: period * 0.11)
                            CubicKeyframe(0.6, duration: period * 0.09)
                            CubicKeyframe(0, duration: period * 0.21)
                            LinearKeyframe(0, duration: period * 0.50)
                        }
                    }
                }
            }
            .padding(inset)
            if celebrate > 0 {
                SparkBurst(trigger: celebrate, distance: size * 0.17)
                    .offset(y: -ringRadius)
            }
        }
        .frame(width: size, height: size)
        .modifier(ScrollVisibility(visible: $onScreen))
        // A task belongs to the view on screen: the sweep can't be lost the way a main-queue hop after onAppear was
        // when the view was rebuilt during launch (QA caught the ring stuck at "0%" under "They agree on 3 of 4").
        .task(id: score) { await sweep() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { String(localized: "Agreement \(Int($0)) percent") } ?? String(localized: "No agreement score yet"))
    }

    /// Everything that beats: the arcs (and their halo), the number and the heart where both arcs begin.
    private func face(pump: Double) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: line)
                .padding(line / 2)
            if scanning && score == nil {
                ScanArc(line: line).padding(line / 2)
            }
            // A soft halo that swells on each beat.
            arcs(width: line * 2.4)
                .opacity(0.16 * pump)
                .padding(line / 2)
            arcs(width: line)
                .padding(line / 2)
            center
            heart(pump: pump)
        }
        .scaleEffect(1 + 0.02 * pump)
    }

    private func arcs(width: CGFloat) -> some View {
        let p = shown / 100
        return ZStack {
            Circle().trim(from: 0, to: 0.5 * p)
                .stroke(Lab.watch, style: StrokeStyle(lineWidth: width, lineCap: .round))
            Circle().trim(from: 1 - 0.5 * p, to: 1)
                .stroke(Lab.whoop, style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // Circle paths start at 3 o'clock and run clockwise: turned a quarter, both start at the bottom.
        .rotationEffect(.degrees(90))
    }

    /// Sized from the ring, not the text size: the ring is a fixed graphic (the card draws it bigger at
    /// accessibility sizes, and VoiceOver reads the score).
    private var center: some View {
        let number = Font.system(size: size * 0.25, weight: .bold, design: .rounded).monospacedDigit()
        let caption = Font.system(size: max(11, size * 0.1), weight: .semibold)
        return VStack(spacing: 0) {
            if score != nil {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(Int(shown.rounded()))")
                        .font(number)
                        .foregroundStyle(Lab.text)
                        .contentTransition(.numericText(value: shown))
                    Text(verbatim: "%")
                        .font(.system(size: size * 0.12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Lab.dim)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text("agree").font(caption).foregroundStyle(Lab.faint)
            } else {
                Text(verbatim: "–").font(number).foregroundStyle(Lab.faint)
                Group {
                    if scanning { Text("checking") } else { Text("no score") }
                }
                .font(caption).foregroundStyle(Lab.faint)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, line * 1.4)
    }

    /// Where both arcs start: a small heart that pops on each beat.
    private func heart(pump: Double) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: max(7, line * 0.95), weight: .bold))
            .foregroundStyle(Lab.accent)
            .scaleEffect(1 + 0.3 * pump)
            .frame(width: line * 2.2, height: line * 2.2)
            .background(Circle().fill(Lab.panel))
            .overlay(Circle().strokeBorder(Lab.line))
            .offset(y: size / 2 - inset - line / 2)
            .accessibilityHidden(true)
    }

    /// First run for this view: sweep in from zero. Later runs (the score changed): move from where it is.
    private func sweep() async {
        let t = target
        if reduceMotion { shown = t; return }
        if !swept {
            swept = true
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { shown = 0 }
            await Task.yield()
        }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.82)) { shown = t }
    }
}

/// Tracks whether a view is on screen inside a scroll view (iOS 18+; always "visible" on iOS 17).
private struct ScrollVisibility: ViewModifier {
    @Binding var visible: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        } else {
            content
        }
    }
}

/// Lab-dial tick marks around the edge of a ring: short minor ticks, longer major ones every `every`.
struct DialTicks: Shape {
    var count = 48
    var every = 6
    var major = false

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2 - 0.5
        let len: CGFloat = major ? 4.5 : 2.5
        for i in 0..<count where (i % every == 0) == major {
            let a = Double(i) / Double(count) * 2 * Double.pi - Double.pi / 2
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            p.move(to: CGPoint(x: c.x + dx * r, y: c.y + dy * r))
            p.addLine(to: CGPoint(x: c.x + dx * (r - len), y: c.y + dy * (r - len)))
        }
        return p
    }
}

/// While a sync runs with no score yet: one short arc circling the track like a scanner. Still under Reduce Motion.
private struct ScanArc: View {
    let line: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(AngularGradient(colors: [Lab.watch.opacity(0), Lab.watch, Lab.whoop], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(80)),
                    style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { spin = true }
            }
            .accessibilityHidden(true)
    }
}

/// A small burst of Watch- and WHOOP-coloured sparks, played once each time `trigger` changes (and when it first
/// appears). Nothing under Reduce Motion.
struct SparkBurst: View {
    let trigger: Int
    var distance: CGFloat = 16
    var count = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = gathered at the centre, 1 = flown out and faded.
    @State private var t: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i % 2 == 0 ? Lab.watch : Lab.whoop)
                    .frame(width: i % 3 == 0 ? 4 : 3, height: i % 3 == 0 ? 4 : 3)
                    .offset(y: -distance * t)
                    .rotationEffect(.degrees(Double(i) * 360 / Double(count)))
            }
        }
        .opacity(Double(1 - t))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { fire() }
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { t = 0 }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.9)) { t = 1 }
        }
    }
}

// MARK: - Row connector

/// The line between a row's two readings with the verdict in the middle: cyan from the Watch side, amber from the
/// WHOOP side, solid when they agree or split, dashed while one side is missing.
struct AgreeConnector<Verdict: View>: View {
    let agree: Bool?
    @ViewBuilder var verdict: Verdict

    var body: some View {
        HStack(spacing: 4) {
            bar(Lab.watch, towardTrailing: true)
            verdict
            bar(Lab.whoop, towardTrailing: false)
        }
        .frame(minWidth: 60, maxWidth: .infinity)
    }

    @ViewBuilder
    private func bar(_ color: Color, towardTrailing: Bool) -> some View {
        if agree == nil {
            DashLine()
                .stroke(Lab.faint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(minWidth: 8, maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(LinearGradient(colors: towardTrailing ? [color, color.opacity(agree == true ? 0.55 : 0.15)]
                                                            : [color.opacity(agree == true ? 0.55 : 0.15), color],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(minWidth: 8, maxWidth: .infinity, minHeight: 2, maxHeight: 2)
                .accessibilityHidden(true)
        }
    }
}

/// A horizontal line through the middle of its frame (for dashed strokes).
struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Moments

/// In-memory only (nothing saved): the hero's scanner line plays the first time the score shows in a launch, and
/// the "they fully agree" sparks at most once a day per launch.
@MainActor
enum AgreementMoments {
    private static var scanned = false
    private static var celebratedDay: Date?

    /// True the first time it's asked in this launch.
    static func firstLook() -> Bool {
        guard !scanned else { return false }
        scanned = true
        return true
    }

    /// True once per day (per launch).
    static func celebrateToday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        guard celebratedDay != today else { return false }
        celebratedDay = today
        return true
    }
}
