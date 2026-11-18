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
            ReadyDuelCard(readiness: store.readinessToday, recovery: store.recoveryToday,
                          sleepHours: lastNightHours, fromYesterday: store.readinessUsesYesterday,
                          onReadiness: { openDetail(.readiness) },
                          onRecovery: { openDetail(.recovery) },
                          action: {
                              UIImpactFeedbackGenerator(style: .light).impactOccurred()
                              if Unlock.shared.gate("The VS lab") { store.go(.compare, metric: .hrv) }
                          })
            // Calm minutes, tree hugs and walks today from Still Pointz, Rootbound and Roamr (hidden without them).
            CalmMovementCard()
            BriefingCard()
            LogWhoopCard()
            numbersHeader
            headToHead
            quickTiles
            if streak >= 2 { StreakChip(days: streak) }
            sleepDuel
            RivalryHero(rounds: Rivalry.rounds(store),
                        watchBPM: store.reading(.watch, \.rhr, recent: "rhr")?.value,
                        whoopBPM: store.reading(.whoop, \.rhr, manual: .rhr)?.value,
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
                Text("Your numbers").font(.title3.weight(.bold)).foregroundStyle(Lab.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAllData = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all stats").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Lab.accent)
                    .frame(minHeight: 44)
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
            .font(.footnote.weight(.medium))
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
    /// "—" only when there's nothing from the last day and a half, with a one-line hint.
    private var headToHead: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTag("Head to head")
                    Spacer()
                    SourceChip(source: .watch)
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
                    .font(.caption).foregroundStyle(Lab.faint)
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
                Text(L(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.dim)
                Spacer()
                if let note { Text(note).font(.caption2).foregroundStyle(Lab.faint) }
            }
            HStack(alignment: .top, spacing: Lab.S.s) {
                h2hSide(w, .watch, unit, f, hint: watchHint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let w, let h {
                    DeltaPill(value: w.value - h.value, decimals: decimals)
                        .padding(.top, 8)
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
                    if editable && !lead { Image(systemName: "pencil").font(.caption2.weight(.bold)).foregroundStyle(Lab.faint) }
                    Text(f(r.value)).font(Lab.number(26)).foregroundStyle(Lab.color(s))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: r.value))
                    Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint)
                }
                Text(r.caption).font(.caption2).foregroundStyle(r.manual ? Lab.whoop : Lab.faint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 4) {
                    if editable { Image(systemName: "plus.circle.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Lab.whoop) }
                    Text("—").font(Lab.number(26)).foregroundStyle(Lab.faint)
                }
                Text(hint).font(.caption2).foregroundStyle(editable ? Lab.whoop : Lab.faint)
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
                    Text(L(title)).font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if let a, let b, a.1 || b.1 { gapChip(a.0 - b.0, decimals: decimals) }
                }
                if only == .whoop { notMeasured(.watch) } else { tileValue(a, .watch, decimals, signed: signed) }
                if only == .watch { notMeasured(.whoop) } else { tileValue(b, .whoop, decimals, signed: signed) }
                Text(note ?? unit).font(.caption2).foregroundStyle(Lab.faint).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(Lab.S.sm)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
            .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.line))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("\(title): Apple Watch \(a.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit), WHOOP \(b.map { $0.0.formatted(.number.precision(.fractionLength(decimals))) } ?? "no data") \(unit)")
        .accessibilityHint("Opens \(title.lowercased()) details")
    }

    /// Watch − WHOOP, coloured by who reads higher. Small on purpose.
    private func gapChip(_ d: Double, decimals: Int) -> some View {
        DeltaPill(value: d, decimals: decimals)
    }

    private func notMeasured(_ s: Source) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(s).opacity(0.35)).frame(width: 5, height: 5)
            Text(s == .watch ? "Not on Watch" : "Not on WHOOP").font(.caption2).foregroundStyle(Lab.faint)
        }
        .frame(height: 24)
    }

    private func tileValue(_ v: (Double, Bool)?, _ s: Source, _ decimals: Int, signed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(s)).frame(width: 6, height: 6)
            let f = v.map { Lab.fmt($0.0, decimals, signed: signed) }
            Text(f ?? "—")
                .font(Lab.number(20)).foregroundStyle(v == nil ? Lab.faint : Lab.color(s).opacity(v?.1 == false ? 0.6 : 1))
                .lineLimit(1).minimumScaleFactor(0.6)
            if v == nil { Text("No reading").font(.caption2).foregroundStyle(Lab.faint) }
            if let v, !v.1 { Text("Earlier").font(.caption2).foregroundStyle(Lab.faint) }
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
                        Text("Details").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.accent).frame(minHeight: 44)
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
            SourceChip(source: s)
            Text(fmtHM(n?.asleepMin)).font(Lab.number(26)).foregroundStyle(n == nil ? Lab.faint : Lab.color(s))
            Text(n == nil ? "No night recorded" : "Asleep").font(.caption).foregroundStyle(Lab.faint)
            HStack(spacing: 8) {
                stat("DEEP", n?.deepMin)
                stat("REM", n?.remMin)
            }
        }
        .frame(maxWidth: .infinity, alignment: s == .watch ? .leading : .trailing)
    }

    private func stat(_ l: String, _ m: Double?) -> some View {
        VStack(spacing: 0) {
            Text(fmtHM(m)).font(Lab.mono(13)).foregroundStyle(Lab.text)
            Text(l).font(Lab.label(9)).foregroundStyle(Lab.faint)
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
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Open resting heart rate details")
                }
                DuelChart(watch: spark(.watch), whoop: spark(.whoop), unit: "bpm", height: 150, showAverages: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rhrSummary)
                DuelLegend()
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
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect WHOOP for the full duel").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    Text("Recovery, strain and sleep stages straight from WHOOP. Settings → WHOOP.").font(.footnote).foregroundStyle(Lab.dim)
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
        LabPanel {
            VStack(spacing: Lab.S.m) {
                HStack {
                    SectionTag("Recovery vs readiness")
                    Spacer()
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if !unlock.isPro { Image(systemName: "lock.fill").font(.caption2.weight(.bold)) }
                            Text("Compare").font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Lab.accent)
                        .frame(minHeight: 44)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Compare tab")
                    .accessibilityHint(unlock.isPro ? "Opens the VS tab" : "Opens the Pro unlock")
                }
                HStack(alignment: .top, spacing: 0) {
                    Button(action: onReadiness) {
                        scoreColumn(readiness, "Readiness", .watch)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Apple Watch readiness \(fmt(readiness))")
                    .accessibilityHint("Shows how readiness was worked out")
                    .accessibilityAddTraits(.isButton)
                    VStack(spacing: 4) {
                        Text(gapText).font(Lab.mono(13, .semibold)).foregroundStyle(Lab.text)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Lab.inset))
                        Text("gap").font(.caption2).foregroundStyle(Lab.faint)
                    }
                    .frame(width: 64)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                    Button(action: onRecovery) {
                        scoreColumn(recovery, "Recovery", .whoop)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("WHOOP recovery \(fmt(recovery))")
                    .accessibilityHint("Opens the recovery chart")
                    .accessibilityAddTraits(.isButton)
                }
                Text(read)
                    .font(.subheadline).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tap a score for the breakdown").font(.caption).foregroundStyle(Lab.faint)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Ring coloured by zone (green / yellow / red), tracker chip underneath.
    private func scoreColumn(_ v: Double?, _ label: String, _ s: Source) -> some View {
        VStack(spacing: Lab.S.s) {
            GaugeRing(value: v, label: label, color: v.map(Lab.band) ?? Lab.faint, size: 116)
            SourceChip(source: s)
            Text(zone(v)).font(.caption.weight(.medium)).foregroundStyle(v.map(Lab.band) ?? Lab.faint)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func zone(_ v: Double?) -> String {
        guard let v else { return String(localized: "No score yet") }
        return v >= 67 ? String(localized: "Ready") : v >= 34 ? String(localized: "Moderate") : String(localized: "Rest")
    }

    private func fmt(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) percent" } ?? "no score" }

    private var gapText: String {
        guard let a = readiness, let b = recovery else { return "—" }
        let d = Int((a - b).rounded())
        return d == 0 ? String(localized: "Even") : Lab.fmt(Double(d), signed: true)
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

/// A small coloured dot before the title (legend labels).
struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}
