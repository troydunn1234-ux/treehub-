import SwiftUI
import Charts

struct TodayScreen: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        let notes = Insights.build(store)
        let streak = Insights.streak(store)
        LabScroll(kicker: Date().formatted(.dateTime.weekday(.wide).month().day()), title: "Today") {
            ReadyDuelCard(readiness: store.readinessToday, recovery: store.recoveryToday,
                          sleepHours: lastNightHours, fromYesterday: store.readinessUsesYesterday) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if Unlock.shared.gate("The VS lab") { store.go(.compare, metric: .hrv) }
            }
            RivalryHero(rounds: Rivalry.rounds(store),
                        watchBPM: store.today(.watch)?.rhr, whoopBPM: store.today(.whoop)?.rhr,
                        readiness: store.readinessToday, recovery: store.recoveryToday,
                        note: gaugeNote)
            if streak >= 2 { StreakChip(days: streak) }
            quickTiles
            LabNotesCard(insights: notes)
            hero
            sleepDuel
            sparkCard
            ShareVSButton()
            if !store.whoopConnected { whoopNudge }
        }
    }

    /// Every number people check, Watch over WHOOP, in one scannable grid. A value from an
    /// earlier day (today's isn't in yet) is shown dimmer with a "yday"-style tag instead of a dash.
    private var quickTiles: some View {
        let wn = store.lastNight(.watch), hn = store.lastNight(.whoop)
        let kcalW = store.latest(.watch, \.totalKcal), kcalH = store.latest(.whoop, \.totalKcal)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s), count: 3), spacing: Lab.S.s) {
            tile("Resting HR", "bpm", store.latest(.watch, \.rhr), store.latest(.whoop, \.rhr), .rhr)
            tile("HRV", "ms", store.latest(.watch, \.hrv), store.latest(.whoop, \.hrv), .hrv, note: "SDNN · RMSSD")
            tile("Sleep", "h", wn.map { ($0.asleepMin / 60, $0.night >= Date().dayStart.adding(days: -1)) }, hn.map { ($0.asleepMin / 60, $0.night >= Date().dayStart.adding(days: -1)) }, .sleep, decimals: 1)
            tile("Resp rate", "br/min", store.latest(.watch, \.resp), store.latest(.whoop, \.resp), .resp, decimals: 1)
            tile("Blood O₂", "%", store.latest(.watch, \.spo2), store.latest(.whoop, \.spo2), .spo2)
            tile("Skin temp", Units.fahrenheit ? "°F vs base" : "°C vs base", store.latest(.watch, \.tempDev).map { (Units.tempDelta($0.0).0 ?? $0.0, $0.1) }, store.latest(.whoop, \.tempDev).map { (Units.tempDelta($0.0).0 ?? $0.0, $0.1) }, .temp, decimals: 1, signed: true)
            tile("Calories", "kcal", kcalW, kcalH, .calories)
            tile("Strain", "/ 21", nil, store.latest(.whoop, \.strain), .recovery, decimals: 1, only: .whoop)
            tile("Steps", "steps", store.latest(.watch, \.steps), nil, .steps, only: .watch)
        }
    }

    /// `a` / `b` are (value, isToday). `only` = the other tracker doesn't measure this at all.
    private func tile(_ title: String, _ unit: String, _ a: (Double, Bool)?, _ b: (Double, Bool)?, _ m: MetricKey,
                      decimals: Int = 0, signed: Bool = false, note: String? = nil, only: Source? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.detail = m
        } label: {
            VStack(alignment: .leading, spacing: Lab.S.xs) {
                HStack(spacing: 4) {
                    Text(title.uppercased()).font(Lab.label(9)).tracking(1.2).foregroundStyle(Lab.dim).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if let a, let b, a.1 || b.1 { gapChip(a.0 - b.0, decimals: decimals) }
                }
                if only == .whoop { notMeasured(.watch) } else { tileValue(a, .watch, decimals, signed: signed) }
                if only == .watch { notMeasured(.whoop) } else { tileValue(b, .whoop, decimals, signed: signed) }
                Text(note ?? unit).font(Lab.label(8)).foregroundStyle(Lab.faint).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Lab.S.m - 4)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lab.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(title): Apple Watch \(a.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit), WHOOP \(b.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit)")
        .accessibilityHint("Opens the \(title.lowercased()) chart")
    }

    /// Watch − WHOOP, coloured by who reads higher. Small on purpose.
    private func gapChip(_ d: Double, decimals: Int) -> some View {
        let txt = (d >= 0 ? "+" : "−") + abs(d).formatted(.number.precision(.fractionLength(decimals)))
        return Text(txt).font(Lab.mono(8, .heavy)).foregroundStyle(abs(d) < 0.05 ? Lab.faint : (d > 0 ? Lab.watch : Lab.whoop))
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func notMeasured(_ s: Source) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(s).opacity(0.35)).frame(width: 5, height: 5)
            Text(s == .watch ? "not on Watch" : "not on WHOOP").font(Lab.label(8)).foregroundStyle(Lab.faint)
        }
        .frame(height: 24)
    }

    private func tileValue(_ v: (Double, Bool)?, _ s: Source, _ decimals: Int, signed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(s)).frame(width: 5, height: 5)
            let f = v.map { (signed && $0.0 > 0 ? "+" : "") + $0.0.formatted(.number.precision(.fractionLength(decimals))) }
            Text(f ?? "—")
                .font(Lab.number(20, .black)).foregroundStyle(v == nil ? Lab.faint : Lab.color(s).opacity(v?.1 == false ? 0.6 : 1))
                .lineLimit(1).minimumScaleFactor(0.6)
            if let v, !v.1 { Text("prev").font(Lab.label(7)).foregroundStyle(Lab.faint) }
        }
    }

    /// Last night's hours asleep, preferring whichever tracker has it (mean when both do).
    private var lastNightHours: Double? {
        let v = Source.allCases.compactMap { store.lastNight($0) }.filter { $0.night >= Date().dayStart.adding(days: -1) }.map { $0.asleepMin / 60 }
        return Stats.mean(v)
    }

    private var gaugeNote: String {
        guard let a = store.readinessToday, let b = store.recoveryToday else {
            return "Readiness is Pulse Lab's score from your Watch: HRV vs your 7-day baseline, resting HR and sleep."
        }
        let d = Int((a - b).rounded())
        if abs(d) <= 8 { return "Both trackers agree on how ready you are today." }
        return d > 0 ? "Your Watch thinks you're \(d) points fresher than WHOOP does." : "WHOOP rates you \(-d) points more recovered than your Watch."
    }

    private var hero: some View {
        let w = store.today(.watch), h = store.today(.whoop)
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SourceChip(source: .watch)
                    Spacer()
                    SectionTag("Head to head")
                    Spacer()
                    SourceChip(source: .whoop)
                }
                tap(.rhr) { VSRow(title: "Resting HR", unit: "bpm", watch: w?.rhr, whoop: h?.rhr) }
                Divider().overlay(Lab.line)
                tap(.hrv) { VSRow(title: "HRV", unit: "ms", watch: w?.hrv, whoop: h?.hrv, note: "SDNN vs RMSSD") }
                Divider().overlay(Lab.line)
                tap(.resp) { VSRow(title: "Respiratory", unit: "br/min", watch: w?.resp, whoop: h?.resp, decimals: 1) }
                Divider().overlay(Lab.line)
                tap(.calories) { VSRow(title: "Calories", unit: "kcal", watch: w?.totalKcal, whoop: h?.totalKcal) }
                if store.reason(.watch) == nil && store.reason(.whoop) == nil {
                    Text("Tap a row for the full chart").font(Lab.label(9)).foregroundStyle(Lab.faint)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: Lab.S.s) {
                        ForEach(Source.allCases) { s in
                            if let r = store.reason(s) { ReasonChip(source: s, text: r) }
                        }
                        Spacer()
                    }
                }
            }
        }
        .visualEffect { [still = Lab.reduceMotion] content, proxy in
            // Gentle depth: the card eases back a touch as it scrolls under the top edge (off with Reduce Motion).
            let y = proxy.frame(in: .scrollView).minY
            return content.scaleEffect(still || y >= 0 ? 1 : max(0.94, 1 + y / 3000))
        }
    }

    private func tap<V: View>(_ m: MetricKey, @ViewBuilder _ v: () -> V) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.detail = m
        } label: { v().contentShape(Rectangle()) }
        .buttonStyle(PressScale())
        .accessibilityHint("Opens the \(m.title.lowercased()) chart")
    }

    private var sleepDuel: some View {
        let w = store.lastNight(.watch), h = store.lastNight(.whoop)
        return LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTag("Last night")
                    Spacer()
                    Button { store.detail = .sleep } label: {
                        Text("DETAILS").font(Lab.label(9)).foregroundStyle(Lab.watch)
                    }
                }
                HStack(alignment: .top) {
                    sleepColumn(w, .watch)
                    Rectangle().fill(Lab.line).frame(width: 1, height: 70)
                    sleepColumn(h, .whoop)
                }
            }
        }
    }

    private func sleepColumn(_ n: SleepNight?, _ s: Source) -> some View {
        VStack(alignment: s == .watch ? .leading : .trailing, spacing: 4) {
            Text(fmtHM(n?.asleepMin)).font(Lab.mono(26, .heavy)).foregroundStyle(Lab.color(s))
                .shadow(color: Lab.color(s).opacity(0.5), radius: 8)
            Text("ASLEEP").font(Lab.label(9)).foregroundStyle(Lab.color(s).opacity(0.7))
            HStack(spacing: 8) {
                stat("DEEP", n?.deepMin)
                stat("REM", n?.remMin)
            }
        }
        .frame(maxWidth: .infinity, alignment: s == .watch ? .leading : .trailing)
    }

    private func stat(_ l: String, _ m: Double?) -> some View {
        VStack(spacing: 0) {
            Text(fmtHM(m)).font(Lab.mono(12)).foregroundStyle(Lab.text)
            Text(l).font(Lab.label(8)).foregroundStyle(Lab.faint)
        }
    }

    /// 14-day resting HR, both lines.
    private var sparkCard: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTag("Resting HR · 14 days")
                    Spacer()
                    Button { store.detail = .rhr } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(Lab.watch)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Open resting heart rate details")
                }
                DuelChart(watch: spark(.watch), whoop: spark(.whoop), unit: "bpm", height: 130, showAverages: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rhrSummary)
            }
        }
    }

    private func spark(_ s: Source) -> [DuelPoint] {
        store.days(s).recent(14).compactMap { d in d.rhr.map { DuelPoint(day: d.day, value: $0, source: s) } }
    }

    private var rhrSummary: String {
        let w = Stats.mean(store.days(.watch).recent(14).compactMap(\.rhr)), h = Stats.mean(store.days(.whoop).recent(14).compactMap(\.rhr))
        func f(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) bpm" } ?? "no data" }
        return "Resting heart rate, last 14 days. Apple Watch average \(f(w)), WHOOP average \(f(h))."
    }

    private var whoopNudge: some View {
        LabPanel(tint: Lab.whoop) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.heart.fill").font(.title2).foregroundStyle(Lab.whoop)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect WHOOP for the full duel").font(Lab.display(15, .heavy)).foregroundStyle(Lab.text)
                    Text("Recovery, strain and sleep stages straight from WHOOP. Settings → WHOOP.").font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim)
                }
            }
        }
    }
}

// MARK: - Recovery vs Readiness

/// Head-to-head at the top of Today: WHOOP recovery (latest cycle) and Pulse Lab's Watch readiness
/// as two half-arcs facing each other, with a one-line verdict. Tapping opens the VS tab (Pro).
struct ReadyDuelCard: View {
    let readiness: Double?
    let recovery: Double?
    /// Last night's hours asleep, used as the tie-breaker when the two scores disagree.
    let sleepHours: Double?
    /// Readiness is using yesterday's Watch readings (nothing recorded since midnight yet).
    var fromYesterday = false
    let action: () -> Void
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        Button(action: action) {
            LabPanel(tint: Lab.violet) {
                VStack(spacing: 12) {
                    HStack {
                        SectionTag("Recovery vs Readiness")
                        Spacer()
                        HStack(spacing: 4) {
                            if !unlock.isPro { Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)) }
                            Text("VS").font(Lab.label(9)).tracking(1.5)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(Lab.watch)
                    }
                    HStack(spacing: 0) {
                        FacingArc(value: readiness, label: "Readiness", source: .watch, color: Lab.watch, opensRight: true)
                        VStack(spacing: 2) {
                            Text("VS").font(Lab.display(22)).foregroundStyle(Lab.duel)
                            Text(gapText).font(Lab.label(8)).tracking(1.2).foregroundStyle(Lab.faint)
                        }
                        .frame(width: 72)
                        FacingArc(value: recovery, label: "Recovery", source: .whoop, color: recovery.map(Lab.band) ?? Lab.whoop, opensRight: false)
                    }
                    Text(read)
                        .font(Lab.body(13, .semibold)).foregroundStyle(Lab.dim)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery versus readiness. Apple Watch readiness \(fmt(readiness)), WHOOP recovery \(fmt(recovery)). \(read)")
        .accessibilityHint(unlock.isPro ? "Opens the VS tab" : "Opens the Pro unlock")
    }

    private func fmt(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) percent" } ?? "no score" }

    private var gapText: String {
        guard let a = readiness, let b = recovery else { return "TODAY" }
        let d = Int((a - b).rounded())
        return d == 0 ? "EVEN" : String(format: "%+d PTS", d)
    }

    /// One line in plain English. When the two split, last night's sleep breaks the tie.
    var read: String {
        let line = readLine
        guard fromYesterday, readiness != nil else { return line }
        return line + " Watch readiness is using yesterday's HRV; wear the Watch to bed for a fresh one each morning."
    }

    private var readLine: String {
        switch (readiness, recovery) {
        case (nil, nil): return "Connect Apple Health and WHOOP to see both scores here."
        case (nil, .some(let r)): return "Only WHOOP has a score today: \(Int(r.rounded()))% recovered. Your Watch has no HRV or resting HR from the last day. Wear it a few hours (or to bed) and readiness fills in."
        case (.some(let a), nil): return "Only your Watch has a score today: \(Int(a.rounded()))% ready. WHOOP recovery lands after your next cycle."
        case (.some(let a), .some(let r)):
            let aGo = a >= 67, rGo = r >= 67, aRest = a < 34, rRest = r < 34
            if aGo && rGo { return "Both say you're ready. Go." }
            if aRest && rRest { return "Both say rest. Keep today easy." }
            if abs(a - r) <= 10 { return "Both land in the same zone today — a middle day: train, but don't chase a record." }
            let whoopSays = rGo ? "go" : rRest ? "rest" : "take it easy"
            let watchSays = aGo ? "go" : aRest ? "rest" : "take it easy"
            let base = "WHOOP says \(whoopSays), Watch says \(watchSays)"
            guard let h = sleepHours else { return base + " — they split today. No sleep logged to break the tie." }
            let hm = fmtHM(h * 60)
            if h >= 7 { return base + " — trust sleep: \(hm) last night, lean toward go." }
            if h >= 6 { return base + " — trust sleep: \(hm) last night, a middle day." }
            return base + " — trust sleep: only \(hm) last night, lean toward rest."
        }
    }
}

/// A 180° arc on one side (the open side faces the opponent), filled top → bottom.
struct FacingArc: View {
    let value: Double?
    let label: String
    let source: Source
    let color: Color
    /// True for the left-hand arc (bulges left, opens to the right).
    let opensRight: Bool
    var size: CGFloat = 112
    @State private var drawn: Double = 0

    var body: some View {
        let line = size * 0.10
        ZStack {
            HalfArc(progress: 1, leftSide: opensRight)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .padding(line / 2)
            HalfArc(progress: drawn / 100, leftSide: opensRight)
                .stroke(LinearGradient(colors: [color.opacity(0.45), color], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .padding(line / 2)
                .shadow(color: color.opacity(0.7), radius: 8)
            VStack(spacing: 2) {
                CountUp(value: value, size: size * 0.26, color: Lab.text)
                Text(label.uppercased()).font(Lab.label(8)).tracking(1.3).foregroundStyle(color)
                SourceChip(source: source).scaleEffect(0.85)
            }
            .offset(x: opensRight ? size * 0.06 : -size * 0.06)
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .onAppear { sweep() }
        .onChange(of: value) { _, _ in sweep() }
        .accessibilityHidden(true)
    }

    private func sweep() {
        let v = min(100, max(0, value ?? 0))
        if Lab.reduceMotion { drawn = v; return }
        drawn = 0
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 1.0)) { drawn = v } }
    }
}

/// Half circle: the left side runs from 12 o'clock down through 9 to 6; the right side mirrors it. Animatable.
struct HalfArc: Shape {
    var progress: Double
    var leftSide: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), radius = min(r.width, r.height) / 2
        let part = min(1, max(0, progress))
        guard part > 0 else { return p }
        // SwiftUI angles: 0° = 3 o'clock, 90° = 6 o'clock, 270° = 12 o'clock.
        if leftSide {
            // 270° → 180° → 90°, i.e. counter-clockwise on screen from the top down the left side.
            let start = Angle.degrees(270), end = Angle.degrees(270 - 180 * part)
            p.addArc(center: c, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        } else {
            // 270° → 360° → 450°, clockwise on screen from the top down the right side.
            let start = Angle.degrees(270), end = Angle.degrees(270 + 180 * part)
            p.addArc(center: c, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        }
        return p
    }
}
