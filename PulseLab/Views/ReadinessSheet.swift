import SwiftUI
import Charts

/// Watch readiness, fully explained: the score on a gauge, every contributor with today's value, the
/// baseline, the difference and the points it added or took away, what's missing, a 30-day trend,
/// how it compares with WHOOP recovery, and the whole recipe in plain English.
struct ReadinessSheet: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var openStat: StatDef?

    private typealias Part = Compare.ReadinessDetail.Part

    var body: some View {
        let detail = store.readinessDetailToday
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: "Apple Watch", title: "Readiness")
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.07)))
                        }
                        .accessibilityLabel("Close")
                    }
                    if let d = detail {
                        hero(d)
                        breakdown(d)
                        if !d.missing.isEmpty { missingCard(d.missing) }
                    } else {
                        emptyCard
                    }
                    trendCard(today: detail?.score)
                    whoopCard(today: detail?.score)
                    howCard
                    Text("Readiness is a general wellness estimate, not medical advice.")
                        .font(Lab.body(11)).foregroundStyle(Lab.faint)
                        .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                }
                .padding(Lab.S.m)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $openStat) { def in
            StatDetailSheet(def: def).environment(store).presentationBackground(Lab.bg)
        }
    }

    // MARK: Hero

    private func band(_ v: Double) -> String {
        v >= 67 ? String(localized: "High") : v >= 34 ? String(localized: "Moderate") : String(localized: "Low")
    }

    private func bandAdvice(_ v: Double) -> String {
        v >= 67 ? String(localized: "Your Watch signals look better than usual. A good day to push if you planned to.")
            : v >= 34 ? String(localized: "Close to your usual. Train as planned, but no need to chase a record.")
            : String(localized: "Below your usual. An easier day and an early night may help.")
    }

    private func hero(_ d: Compare.ReadinessDetail) -> some View {
        let color = Lab.band(d.score)
        return LabPanel(tint: color) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Lab.S.m) {
                    ArcGauge(value: d.score, label: "Readiness", color: color, size: 140)
                    heroText(d, color)
                }
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    ArcGauge(value: d.score, label: "Readiness", color: color, size: 140).frame(maxWidth: .infinity)
                    heroText(d, color)
                }
            }
        }
    }

    private func heroText(_ d: Compare.ReadinessDetail, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(band(d.score)).font(Lab.title(24)).foregroundStyle(color)
            Text(bandAdvice(d.score)).font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            chip(String(localized: "BASELINE: LAST \(d.baselineDays) DAYS"), Lab.violet)
            if d.usedYesterday { chip(String(localized: "USED YESTERDAY'S READINGS"), Lab.warn) }
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(Lab.label(8)).tracking(1).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.13)))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Breakdown

    private func breakdown(_ d: Compare.ReadinessDetail) -> some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHAT MADE TODAY'S SCORE").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                HStack {
                    Text("Starting point").font(Lab.body(14, .semibold)).foregroundStyle(Lab.dim)
                    Spacer()
                    Text("\(Int(Compare.ReadinessDetail.start))").font(Lab.number(20)).foregroundStyle(Lab.text)
                }
                .accessibilityElement(children: .combine)
                ForEach(d.parts) { p in
                    Divider().overlay(Lab.line)
                    partRow(p)
                }
                Divider().overlay(Lab.line)
                HStack(alignment: .firstTextBaseline) {
                    Text("Readiness").font(Lab.body(15, .heavy)).foregroundStyle(Lab.text)
                    Spacer()
                    Text("= \(Int(d.score))").font(Lab.number(26, .black)).foregroundStyle(Lab.band(d.score))
                }
                .accessibilityElement(children: .combine)
                if d.raw != d.score {
                    Text("The points add up to \(Int(d.raw)); the score is held between 1 and 99.")
                        .font(Lab.body(12)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                }
                Text("Tap a row for its full history.").font(Lab.body(11)).foregroundStyle(Lab.faint)
            }
        }
    }

    private func partRow(_ p: Part) -> some View {
        Button {
            Lab.tick()
            openStat = AllStats.def(p.statID)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: Lab.S.s) {
                    Image(systemName: p.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Lab.watch)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(p.title).font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                            if p.fromYesterday { chip(String(localized: "YESTERDAY"), Lab.warn) }
                        }
                        Text(detailLine(p)).font(Lab.body(12)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text(pointsText(p)).font(Lab.number(20)).foregroundStyle(pointsColor(p))
                }
                PointsBar(points: p.points, maxUp: p.maxUp, maxDown: p.maxDown).frame(height: 6)
                    .padding(.leading, 32)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.title). \(detailLine(p)). \(pointsSpoken(p))")
        .accessibilityHint("Opens \(p.title.lowercased()) details")
    }

    private func fmt(_ v: Double, _ p: Part) -> String {
        if p.kind == .sleep { return fmtHM(v * 60) }
        return v.formatted(.number.precision(.fractionLength(p.decimals))) + " " + p.unit
    }

    private func signed(_ v: Double, _ p: Part) -> String {
        if p.kind == .sleep { return (v >= 0 ? "+" : "−") + fmtHM(abs(v) * 60) }
        return (v >= 0 ? "+" : "−") + abs(v).formatted(.number.precision(.fractionLength(p.decimals))) + " " + p.unit
    }

    /// "Today 48 ms · Baseline 55 ms · −7 ms".
    private func detailLine(_ p: Part) -> String {
        guard let v = p.value else {
            return p.kind == .sleep ? String(localized: "No Watch sleep last night") : String(localized: "No reading")
        }
        let now = p.fromYesterday ? String(localized: "Yesterday") : String(localized: "Today")
        if p.kind == .temp { return "\(now) \(signed(v, p)) vs your normal" }
        guard let b = p.baseline, let diff = p.diff else { return String(localized: "\(now) \(fmt(v, p)) · no baseline yet") }
        return "\(now) \(fmt(v, p)) · \(p.baselineLabel) \(fmt(b, p)) · \(signed(diff, p))"
    }

    private func pointsText(_ p: Part) -> String {
        guard p.scored else { return "—" }
        let r = p.points.rounded()
        return r == 0 ? "0" : (r > 0 ? "+" : "−") + "\(Int(abs(r)))"
    }

    private func pointsSpoken(_ p: Part) -> String {
        guard p.scored else { return String(localized: "Not scored") }
        let r = Int(p.points.rounded())
        return r >= 0 ? String(localized: "Adds \(r) points") : String(localized: "Takes off \(-r) points")
    }

    private func pointsColor(_ p: Part) -> Color {
        guard p.scored else { return Lab.faint }
        return abs(p.points) < 0.5 ? Lab.dim : (p.points > 0 ? Lab.good : Lab.bad)
    }

    private func missingCard(_ notes: [String]) -> some View {
        LabPanel(tint: Lab.warn) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Label("MISSING OR LIMITED DATA", systemImage: "exclamationmark.circle.fill").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.warn)
                ForEach(notes, id: \.self) { n in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Lab.warn).frame(width: 5, height: 5).padding(.top, 7)
                        Text(n).font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyCard: some View {
        LabPanel(tint: Lab.warn) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Text("No readiness yet").font(Lab.title(20)).foregroundStyle(Lab.text)
                Text("Readiness needs HRV or resting heart rate from your Watch in the last day. Wear your Watch to sleep for overnight HRV and sleep, and it fills in each morning.")
                    .font(Lab.body(14)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Trend

    private func trendPoints(today: Double?) -> (watch: [DuelPoint], whoop: [DuelPoint]) {
        var w = store.watchDays.recent(30).compactMap { d in d.recovery.map { DuelPoint(day: d.day, value: $0, source: .watch) } }
        if let t = today {
            w.removeAll { $0.day.isToday }
            w.append(DuelPoint(day: Date().dayStart, value: t, source: .watch))
        }
        let h = store.whoopDays.recent(30).compactMap { d in d.recovery.map { DuelPoint(day: d.day, value: $0, source: .whoop) } }
        return (w, h)
    }

    private func trendCard(today: Double?) -> some View {
        let (w, h) = trendPoints(today: today)
        let v = w.map(\.value)
        return LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LAST 30 DAYS").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                    Spacer()
                    if !h.isEmpty { DuelLegend(compact: true) }
                }
                if w.isEmpty && h.isEmpty {
                    EmptyNote(text: "No readiness in the last 30 days.")
                } else {
                    DuelChart(watch: w, whoop: h, unit: "score", height: 190, showAverages: false, showPoints: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(trendSummary(v))
                }
                if let m = Stats.mean(v), let lo = v.min(), let hi = v.max() {
                    HStack(spacing: Lab.S.m) {
                        miniStat("AVERAGE", "\(Int(m.rounded()))")
                        miniStat("LOWEST", "\(Int(lo.rounded()))")
                        miniStat("HIGHEST", "\(Int(hi.rounded()))")
                        miniStat("DAYS", "\(v.count)")
                    }
                }
                Text("Past days are scored the same way, from that day's readings (no carry-over from the day before).")
                    .font(Lab.body(11)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func trendSummary(_ v: [Double]) -> String {
        guard let m = Stats.mean(v) else { return String(localized: "No readiness in the last 30 days") }
        return String(localized: "Readiness over 30 days: average \(Int(m.rounded())), from \(Int((v.min() ?? 0).rounded())) to \(Int((v.max() ?? 0).rounded())).")
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Lab.number(18)).foregroundStyle(Lab.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Lab.label(8)).foregroundStyle(Lab.faint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: vs WHOOP

    private func whoopCard(today: Double?) -> some View {
        let (w, h) = trendPoints(today: today)
        let hByDay = Dictionary(h.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        let pairs = w.compactMap { p in hByDay[p.day].map { (p.value, $0) } }
        let gaps = pairs.map { $0.0 - $0.1 }
        let within = gaps.filter { abs($0) <= 10 }.count
        let r = Stats.pearson(pairs.map(\.0), pairs.map(\.1))
        let rec = store.recoveryToday
        return LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: 12) {
                Text("NEXT TO WHOOP RECOVERY").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                if today != nil || rec != nil {
                    HStack(spacing: 0) {
                        scoreColumn("Readiness", today, .watch)
                        VStack(spacing: 2) {
                            Text("VS").font(Lab.display(18)).foregroundStyle(Lab.duel)
                            if let a = today, let b = rec {
                                let d = Int((a - b).rounded())
                                Text(d == 0 ? "EVEN" : String(format: "%+d PTS", d)).font(Lab.label(8)).foregroundStyle(Lab.faint)
                            }
                        }
                        .frame(width: 70)
                        scoreColumn("Recovery", rec, .whoop)
                    }
                }
                if rec == nil && h.isEmpty {
                    Text("Connect WHOOP in Settings, or log recovery by hand, to compare the two scores.")
                        .font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                } else if pairs.count >= 3 {
                    let avgGap = Stats.mean(gaps) ?? 0
                    let lean = abs(avgGap) < 3 ? String(localized: "They average about the same.")
                        : avgGap > 0 ? String(localized: "Readiness runs about \(Int(abs(avgGap).rounded())) points higher on average.")
                        : String(localized: "WHOOP runs about \(Int(abs(avgGap).rounded())) points higher on average.")
                    let move = r.map { $0 > 0.6 ? String(localized: "They rise and fall together closely.") : $0 > 0.3 ? String(localized: "They mostly move together.") : String(localized: "They often move differently day to day.") } ?? ""
                    Text("Over \(pairs.count) days with both scores, they were within 10 points on \(within). \(lean) \(move)")
                        .font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW THEY DIFFER").font(Lab.label(8)).tracking(1.2).foregroundStyle(Lab.faint)
                    bullet(String(localized: "WHOOP reads HRV (RMSSD) and resting HR in your last deep sleep. The Watch logs HRV as SDNN, often from short readings, and resting HR from calm moments in the day."))
                    bullet(String(localized: "WHOOP scores sleep against its own estimate of what you needed; readiness uses a flat 7-hour target."))
                    bullet(String(localized: "WHOOP's formula is its own and isn't published. Readiness is the simple recipe shown on this screen."))
                    bullet(String(localized: "Both compare you with your recent self, so they agree on direction more often than on the exact number."))
                }
            }
        }
    }

    private func scoreColumn(_ label: String, _ v: Double?, _ s: Source) -> some View {
        let shown: String = v.map { String(Int($0.rounded())) } ?? "––"
        let spoken: String = v.map { String(Int($0.rounded())) } ?? String(localized: "no score")
        return VStack(spacing: 4) {
            Text(shown).font(Lab.number(36, .black)).foregroundStyle(v.map(Lab.band) ?? Lab.faint)
            Text(L(label).uppercased()).font(Lab.label(8)).tracking(1.2).foregroundStyle(Lab.dim)
            SourceChip(source: s)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.name) \(L(label)): \(spoken)")
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Lab.faint).frame(width: 4, height: 4).padding(.top, 7)
            Text(t).font(Lab.body(12)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: How it's calculated

    private var howCard: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Label("HOW IT'S CALCULATED", systemImage: "function").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                Text("Every score starts at 55. Each signal from your Watch then adds or takes away points depending on how today compares with your own recent normal.")
                    .font(Lab.body(14)).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
                ForEach(Part.Kind.allCases, id: \.self) { k in
                    let p = Part(kind: k, maxUp: 0, maxDown: 0)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: p.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Lab.watch).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(Lab.body(13, .semibold)).foregroundStyle(Lab.text)
                            Text(p.rule).font(Lab.body(12)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                bullet(String(localized: "Baseline: the average of the 14 days before, once at least 10 of them have readings; until then, the last 7 days."))
                bullet(String(localized: "If your Watch hasn't recorded HRV or resting HR since midnight, today's score uses yesterday's readings against the days before yesterday."))
                bullet(String(localized: "The final score is kept between 1 and 99. 67 and up is high, 34–66 moderate, below 34 low — the same bands WHOOP uses."))
            }
        }
    }
}

/// Points from one contributor as a bar growing left (lost) or right (gained) from a centre line.
private struct PointsBar: View {
    let points: Double
    let maxUp: Double
    let maxDown: Double

    var body: some View {
        GeometryReader { geo in
            let total = max(maxUp + maxDown, 1)
            let center = geo.size.width * maxDown / total
            let width = geo.size.width * min(abs(points), points >= 0 ? maxUp : maxDown) / total
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Rectangle().fill(points >= 0 ? Lab.good : Lab.bad)
                    .frame(width: width)
                    .offset(x: points >= 0 ? center : center - width)
                    .opacity(abs(points) < 0.5 ? 0 : 0.85)
                Rectangle().fill(Color.white.opacity(0.4)).frame(width: 1).offset(x: center)
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }
}
