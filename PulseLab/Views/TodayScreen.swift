import SwiftUI
import Charts

struct TodayScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showAllData = false
    /// A stat with no `MetricKey` (WHOOP strain), opened in place.
    @State private var statSheet: StatDef?

    var body: some View {
        let notes = Insights.build(store)
        let streak = Insights.streak(store)
        LabScroll(kicker: Date().formatted(.dateTime.weekday(.wide).month().day()), title: "Today") {
            BriefingCard()
            ReadyDuelCard(readiness: store.readinessToday, recovery: store.recoveryToday,
                          sleepHours: lastNightHours, fromYesterday: store.readinessUsesYesterday,
                          onReadiness: { openDetail(.readiness) },
                          onRecovery: { openDetail(.recovery) },
                          action: {
                              UIImpactFeedbackGenerator(style: .light).impactOccurred()
                              if Unlock.shared.gate("The VS lab") { store.go(.compare, metric: .hrv) }
                          })
            LogWhoopCard()
            numbersHeader
            headToHead
            quickTiles
            if streak >= 2 { StreakChip(days: streak) }
            sleepDuel
            RivalryHero(rounds: Rivalry.rounds(store),
                        watchBPM: store.today(.watch)?.rhr, whoopBPM: store.today(.whoop)?.rhr,
                        readiness: store.readinessToday, recovery: store.recoveryToday,
                        note: gaugeNote, showGauges: false)
            InsightsButton()
            LabNotesCard(insights: notes)
            sparkCard
            ShareVSButton()
            if !store.whoopConnected { whoopNudge }
        }
        .sheet(isPresented: $showAllData) {
            AllDataScreen().environment(store).presentationBackground(Lab.bg)
        }
        .sheet(item: $statSheet) { def in
            StatDetailSheet(def: def).environment(store).presentationBackground(Lab.bg)
        }
    }

    private func openDetail(_ m: MetricKey) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.detail = m
    }

    /// "Your numbers" with the way into All data, plus why a side is blank when it is.
    private var numbersHeader: some View {
        VStack(alignment: .leading, spacing: Lab.S.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your numbers").font(Lab.title(20)).foregroundStyle(Lab.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAllData = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all stats").font(Lab.body(13, .bold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(Lab.violet)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityHint("Opens every synced metric")
            }
            HStack(spacing: Lab.S.s) {
                Label("Watch", systemImage: "circle.fill").foregroundStyle(Lab.watch)
                Label("WHOOP", systemImage: "circle.fill").foregroundStyle(Lab.whoop)
                Text("· tap a tile for details").foregroundStyle(Lab.faint)
                Spacer(minLength: 0)
            }
            .font(Lab.label(9))
            .labelStyle(DotLabelStyle())
            if store.reason(.watch) != nil || store.reason(.whoop) != nil {
                HStack(spacing: Lab.S.s) {
                    ForEach(Source.allCases) { s in
                        if let r = store.reason(s) { ReasonChip(source: s, text: r) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, Lab.S.s)
    }

    // MARK: Head to head

    /// The five numbers both trackers report, Watch on the left, WHOOP on the right. Each side shows its most
    /// relevant recent value (last night / newest reading / today / yesterday) with a caption saying which;
    /// "––" only when there's nothing from the last day and a half, with a one-line hint.
    private var headToHead: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SourceChip(source: .watch)
                    Spacer()
                    SectionTag("Head to head")
                    Spacer()
                    SourceChip(source: .whoop)
                }
                h2hRow("Resting HR", "bpm", .rhr,
                       store.reading(.watch, \.rhr, recent: "rhr"), store.reading(.whoop, \.rhr, manual: .rhr),
                       watchHint: String(localized: "Arrives after a few hours of wear"), whoopHint: String(localized: "Not in yet"))
                Divider().overlay(Lab.line)
                h2hRow("HRV", "ms", .hrv,
                       store.reading(.watch, \.hrv, recent: "hrv"), store.reading(.whoop, \.hrv, manual: .hrv),
                       note: "SDNN vs RMSSD",
                       watchHint: String(localized: "Wear your Watch to bed for overnight HRV"), whoopHint: String(localized: "Not in yet"))
                Divider().overlay(Lab.line)
                h2hRow("Respiratory", "br/min", .resp,
                       store.reading(.watch, \.resp, recent: "resp"), store.reading(.whoop, \.resp, manual: .resp), decimals: 1,
                       watchHint: String(localized: "Needs Watch sleep tracking"), whoopHint: String(localized: "Not in yet"))
                Divider().overlay(Lab.line)
                h2hRow("Calories", "kcal", .calories,
                       store.reading(.watch, \.totalKcal), store.reading(.whoop, \.totalKcal, manual: .kcal),
                       watchHint: String(localized: "Not in yet"), whoopHint: String(localized: "Not shared by WHOOP · tap to add"),
                       edit: .kcal())
                Divider().overlay(Lab.line)
                h2hRow("Steps", "steps", .steps,
                       store.reading(.watch, \.steps), store.reading(.whoop, \.steps, manual: .steps),
                       watchHint: String(localized: "Not in yet"), whoopHint: String(localized: "Tap to add WHOOP steps"),
                       edit: .steps())
                Text("Tap a row for its chart · tap WHOOP steps or calories to type them in")
                    .font(Lab.label(8)).foregroundStyle(Lab.faint)
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            }
        }
    }

    private func h2hRow(_ title: String, _ unit: String, _ m: MetricKey, _ w: LabStore.Reading?, _ h: LabStore.Reading?,
                        decimals: Int = 0, note: String? = nil, watchHint: String, whoopHint: String,
                        edit: WhoopQuickEdit? = nil) -> some View {
        let f: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(decimals))) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L(title).uppercased()).font(Lab.label(10)).tracking(1.6).foregroundStyle(Lab.dim)
                Spacer()
                if let note { Text(note).font(Lab.label(8)).foregroundStyle(Lab.faint) }
            }
            HStack(alignment: .top, spacing: Lab.S.s) {
                h2hSide(w, .watch, unit, f, hint: watchHint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let w, let h {
                    let d = w.value - h.value
                    Text((d >= 0 ? "+" : "−") + f(abs(d)))
                        .font(Lab.mono(11, .bold)).foregroundStyle(Lab.dim)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.12)))
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                }
                if let edit {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.quickWhoop = WhoopQuickEdit(field: edit.field, day: Date().dayStart)
                    } label: {
                        h2hSide(h, .whoop, unit, f, hint: whoopHint, editable: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityHint("Type in today's WHOOP \(L(title).lowercased())")
                } else {
                    h2hSide(h, .whoop, unit, f, hint: whoopHint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.detail = m
        }
        .accessibilityAction(named: Text("Open chart")) { store.detail = m }
    }

    private func h2hSide(_ r: LabStore.Reading?, _ s: Source, _ unit: String, _ f: (Double) -> String, hint: String, editable: Bool = false) -> some View {
        let lead = s == .watch
        return VStack(alignment: lead ? .leading : .trailing, spacing: 2) {
            if let r {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if editable && !lead { Image(systemName: "pencil").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.faint) }
                    Text(f(r.value)).font(Lab.number(26, .black)).foregroundStyle(Lab.color(s))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(unit).font(Lab.label(8)).foregroundStyle(Lab.color(s).opacity(0.7))
                }
                Text(r.caption).font(Lab.label(7)).tracking(0.8).foregroundStyle(r.manual ? Lab.whoop.opacity(0.8) : Lab.faint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 4) {
                    if editable { Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Lab.whoop) }
                    Text("––").font(Lab.number(26, .black)).foregroundStyle(Lab.faint)
                }
                Text(hint).font(Lab.body(10)).foregroundStyle(editable ? Lab.whoop.opacity(0.85) : Lab.faint)
                    .multilineTextAlignment(lead ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.name): \(r.map { f($0.value) + " " + unit + ", " + $0.caption.lowercased() } ?? hint)")
    }

    /// Every number people check, Watch over WHOOP, in one scannable grid. A value from an
    /// earlier day (today's isn't in yet) is shown dimmer with a "yday"-style tag instead of a dash.
    private var quickTiles: some View {
        let wn = store.lastNight(.watch), hn = store.lastNight(.whoop)
        let cols = typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s), count: cols), spacing: Lab.S.s) {
            tile("Sleep", "h", wn.map { ($0.asleepMin / 60, $0.night >= Date().dayStart.adding(days: -1)) }, hn.map { ($0.asleepMin / 60, $0.night >= Date().dayStart.adding(days: -1)) }, .sleep, decimals: 1)
            tile("Blood O₂", "%", store.latest(.watch, \.spo2), store.latest(.whoop, \.spo2), .spo2)
            tile("Skin temp", Units.fahrenheit ? "°F vs base" : "°C vs base", store.latest(.watch, \.tempDev).map { (Units.tempDelta($0.0).0 ?? $0.0, $0.1) }, store.latest(.whoop, \.tempDev).map { (Units.tempDelta($0.0).0 ?? $0.0, $0.1) }, .temp, decimals: 1, signed: true)
            tile("Strain", "/ 21", nil, store.latest(.whoop, \.strain), nil, decimals: 1, only: .whoop)
        }
    }

    /// `a` / `b` are (value, isToday). `only` = the other tracker doesn't measure this at all.
    /// `m` nil = WHOOP strain, which has no `MetricKey` and opens its All-data detail directly.
    private func tile(_ title: String, _ unit: String, _ a: (Double, Bool)?, _ b: (Double, Bool)?, _ m: MetricKey?,
                      decimals: Int = 0, signed: Bool = false, note: String? = nil, only: Source? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let m { store.detail = m } else { statSheet = AllStats.def("strain") }
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
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lab.panel.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(title): Apple Watch \(a.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit), WHOOP \(b.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit)")
        .accessibilityHint("Opens \(title.lowercased()) details")
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
            return "Readiness is Pulse Lab's score from your Watch: HRV and resting HR vs your own baseline, plus sleep. Tap it for the breakdown."
        }
        let d = Int((a - b).rounded())
        if abs(d) <= 8 { return "Both trackers agree on how ready you are today." }
        return d > 0 ? "Your Watch thinks you're \(d) points fresher than WHOOP does." : "WHOOP rates you \(-d) points more recovered than your Watch."
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
    /// Tap the readiness arc: how readiness was worked out.
    var onReadiness: () -> Void = {}
    /// Tap the recovery arc: the recovery chart.
    var onRecovery: () -> Void = {}
    /// The VS link: the Compare tab (Pro).
    let action: () -> Void
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        LabPanel(tint: Lab.violet) {
            VStack(spacing: 12) {
                HStack {
                    SectionTag("Recovery vs Readiness")
                    Spacer()
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if !unlock.isPro { Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)) }
                            Text("VS").font(Lab.label(9)).tracking(1.5)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(Lab.watch)
                        .padding(.vertical, 6).padding(.leading, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Compare tab")
                    .accessibilityHint(unlock.isPro ? "Opens the VS tab" : "Opens the Pro unlock")
                }
                HStack(spacing: 0) {
                    Button(action: onReadiness) {
                        FacingArc(value: readiness, label: "Readiness", source: .watch, color: Lab.watch, opensRight: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Apple Watch readiness \(fmt(readiness))")
                    .accessibilityHint("Shows how readiness was worked out")
                    .accessibilityAddTraits(.isButton)
                    VStack(spacing: 2) {
                        Text("VS").font(Lab.display(22)).foregroundStyle(Lab.duel)
                        Text(gapText).font(Lab.label(8)).tracking(1.2).foregroundStyle(Lab.faint)
                    }
                    .frame(width: 72)
                    .accessibilityHidden(true)
                    Button(action: onRecovery) {
                        FacingArc(value: recovery, label: "Recovery", source: .whoop, color: recovery.map(Lab.band) ?? Lab.whoop, opensRight: false)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("WHOOP recovery \(fmt(recovery))")
                    .accessibilityHint("Opens the recovery chart")
                    .accessibilityAddTraits(.isButton)
                }
                Text(read)
                    .font(Lab.body(13, .semibold)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap a score for the breakdown").font(Lab.label(8)).tracking(1).foregroundStyle(Lab.faint)
                    .accessibilityHidden(true)
            }
        }
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

/// A small coloured dot before the title (legend labels).
struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}
