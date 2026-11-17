import SwiftUI
import Charts

/// A metric opened from Today, the tabs or a notification: the same detail screen as All data.
struct MetricDetailSheet: View {
    let metric: MetricKey
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let def = AllStats.def(metric.statID) {
            StatDetailSheet(def: def)
        } else {
            ZStack(alignment: .topTrailing) {
                LabBackground()
                EmptyNote(text: String(localized: "Nothing has arrived for \(L(metric.title).lowercased()) yet."),
                          symbol: "tray", title: "No data yet")
                    .padding(Lab.S.l)
                    .frame(maxHeight: .infinity)
                CloseButton { dismiss() }.padding(Lab.S.s)
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Every metric's detail, one pattern everywhere: big current value with its day and source, what it is,
/// your normal range shaded on a 7D/30D/90D/1Y chart (90D/1Y stay Pro via RangePicker), low/average/high and
/// the trend vs last week, tracker agreement when both measure it, why it matters, how to improve, where the
/// numbers come from, and related metrics.
struct StatDetailSheet: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var def: StatDef
    /// Metrics visited through "Related", for the back button.
    @State private var trail: [StatDef] = []
    @State private var days = 30
    @State private var solo: Source?
    @State private var showReadiness = false
    @State private var quickEdit: WhoopQuickEdit?

    init(def: StatDef) { _def = State(initialValue: def) }

    private var info: StatInfo { StatGuide.info(def) }

    var body: some View {
        let series = def.read(store)
        let primary = def.primary(series)
        let band = primary.flatMap { normalBand(series.points($0)) }
        ZStack {
            LabBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Lab.S.m) {
                        header.id("top")
                        if let primary, let last = series.points(primary).last {
                            hero(series, primary, last, band)
                        } else {
                            emptyHero
                        }
                        if let edit = whoopEdit { whoopEditButton(edit, series) }
                        chartPanel(series, primary, band)
                        statsPanel(series)
                        if let name = StatGuide.compareName(def.id), let a = agreement(name) { agreementCard(a) }
                        textCard("Why it matters", info.why, icon: "lightbulb.fill")
                        improveCard
                        sourcesCard(series)
                        relatedCard(proxy)
                        Text("Pulse Lab is for general wellness and fitness, not medical advice.")
                            .font(.footnote).foregroundStyle(Lab.faint)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Lab.S.m)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showReadiness) {
            ReadinessSheet().environment(store).presentationBackground(Lab.bg)
        }
        .sheet(item: $quickEdit) { r in
            WhoopQuickEditSheet(request: r).environment(store).presentationBackground(Lab.bg)
        }
    }

    /// Steps and calories can be typed in for WHOOP (it doesn't share them).
    private var whoopEdit: WhoopQuickEdit? {
        switch def.id {
        case "steps": .steps()
        case "totalKcal": .kcal()
        default: nil
        }
    }

    private func whoopEditButton(_ edit: WhoopQuickEdit, _ series: StatSeries) -> some View {
        let today = series.whoop.last { $0.day.isToday }
        let title = edit.field == .steps
            ? (today == nil ? String(localized: "Add today's WHOOP steps") : String(localized: "Edit today's WHOOP steps"))
            : (today == nil ? String(localized: "Add today's WHOOP calories") : String(localized: "Edit today's WHOOP calories"))
        return Button {
            Lab.tick()
            quickEdit = WhoopQuickEdit(field: edit.field, day: Date().dayStart)
        } label: {
            HStack(spacing: Lab.S.sm) {
                SymbolTile(symbol: today == nil ? "plus" : "pencil", tint: Lab.whoop, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(today.map { String(localized: "Today: \(Int($0.value.rounded()).formatted())") }
                         ?? String(localized: "Type it from the WHOOP app in a few seconds"))
                        .font(.footnote).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Lab.S.xs)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
            }
            .padding(Lab.S.sm)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.whoop.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.whoop.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Lab.S.xs) {
            if let back = trail.last {
                Button {
                    Lab.tick()
                    withAnimation(.snappy) { def = back; trail.removeLast(); solo = nil }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(Lab.dim)
                        .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.10)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back to \(L(back.title))"))
            }
            ScreenTitle(kicker: def.section.title, title: def.title)
            CloseButton { dismiss() }
        }
    }

    // MARK: Hero: value, day, source, what it is

    private func hero(_ series: StatSeries, _ src: Source, _ last: StatPoint, _ band: ClosedRange<Double>?) -> some View {
        let other: Source = src == .watch ? .whoop : .watch
        let otherLast = series.points(other).last
        let badge = store.badge(def, src, series: series)
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                HStack(spacing: 6) {
                    SourceBadge(text: badge)
                    Text(dayLabel(last.day)).font(.footnote.weight(.semibold)).foregroundStyle(last.day.isToday ? Lab.good : Lab.dim)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmt(last.value)).font(Lab.number(52)).foregroundStyle(Lab.color(src))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: last.value))
                    Text(def.unit).font(.title3.weight(.semibold)).foregroundStyle(Lab.dim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fmt(last.value)) \(def.unit), \(dayLabel(last.day)), \(SourceBadge.display(badge))")
                if let band { normalLine(last.value, band) }
                if let o = otherLast {
                    HStack(spacing: 6) {
                        SourceChip(source: other)
                        Text(verbatim: "\(fmt(o.value)) \(def.unit)").font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Lab.text)
                        Text(dayLabel(o.day)).font(.caption).foregroundStyle(Lab.faint)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(other.name): \(fmt(o.value)) \(def.unit), \(dayLabel(o.day))")
                }
                Divider().overlay(Lab.line)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What it is").font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
                        .accessibilityAddTraits(.isHeader)
                    Text(info.what).font(.subheadline).foregroundStyle(Lab.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Nothing has arrived for this metric: what it is, and the one thing to try.
    private var emptyHero: some View {
        LabPanel {
            VStack(spacing: Lab.S.sm) {
                SymbolTile(symbol: def.section.icon, tint: def.section.tint, size: 52)
                Text("No data yet").font(.title3.weight(.bold)).foregroundStyle(Lab.text)
                Text(info.what).font(.subheadline).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("It shows up here once your tracker records it and it reaches Apple Health or WHOOP. If it never does, check Sources in Settings.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Lab.tick()
                    Task { await store.refresh(.user) }
                } label: {
                    Text(store.loading ? String(localized: "Syncing…") : String(localized: "Sync now"))
                }
                .buttonStyle(LabPrimaryButton())
                .disabled(store.loading)
                .frame(maxWidth: 320)
                .padding(.top, Lab.S.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Lab.S.s)
        }
    }

    /// "In your normal range" / "Above your normal range (52–61 ms)".
    private func normalLine(_ v: Double, _ band: ClosedRange<Double>) -> some View {
        let range = "\(fmt(band.lowerBound))–\(fmt(band.upperBound)) \(def.unit)"
        let inside = band.contains(v)
        let above = v > band.upperBound
        let good: Bool? = inside ? true : info.better.map { ($0 == .higher) == above }
        let color: Color = inside ? Lab.good : (good == nil ? Lab.violet : (good == true ? Lab.good : Lab.warn))
        let text: String = inside ? String(localized: "In your normal range (\(range))")
            : above ? String(localized: "Above your normal range (\(range))")
            : String(localized: "Below your normal range (\(range))")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: inside ? "checkmark.circle.fill" : (above ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Your normal: 30-day mean ± 1 SD of the main tracker (needs 5+ days).
    private func normalBand(_ pts: [StatPoint]) -> ClosedRange<Double>? {
        let cut = Date().dayStart.adding(days: -29)
        let v = pts.filter { $0.day >= cut }.map(\.value)
        guard v.count >= 5, let m = Stats.mean(v), let sd = Stats.sd(v) else { return nil }
        let half = max(sd, abs(m) * 0.005, 0.5 * pow(10, -Double(def.decimals)))
        return (m - half)...(m + half)
    }

    // MARK: Chart

    private func inRange(_ pts: [StatPoint]) -> [StatPoint] {
        let cut = Date().dayStart.adding(days: -(days - 1))
        return pts.filter { $0.day >= cut }
    }

    private func chartPanel(_ series: StatSeries, _ primary: Source?, _ band: ClosedRange<Double>?) -> some View {
        let w = inRange(series.watch), h = inRange(series.whoop)
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        SectionTag("Trend")
                        Spacer(minLength: Lab.S.s)
                        RangePicker(days: $days)
                    }
                    VStack(alignment: .leading, spacing: Lab.S.s) {
                        SectionTag("Trend")
                        RangePicker(days: $days)
                    }
                }
                if !series.watch.isEmpty && !series.whoop.isEmpty { DuelLegend(solo: $solo) }
                if w.isEmpty && h.isEmpty {
                    if series.isEmpty {
                        EmptyNote(text: "The chart fills in as readings arrive.", symbol: "chart.xyaxis.line", title: "No readings yet")
                    } else {
                        EmptyNote(text: String(localized: "Nothing in the last \(days) days. Try a longer range."),
                                  symbol: "chart.xyaxis.line", title: "No readings in this range")
                    }
                } else {
                    DuelChart(watch: w.map { DuelPoint(day: $0.day, value: $0.value, source: .watch) },
                              whoop: h.map { DuelPoint(day: $0.day, value: $0.value, source: .whoop) },
                              unit: def.unit, decimals: def.decimals, height: 220, showAverages: false,
                              showPoints: days <= 30, solo: solo, band: band)
                        .chartSummary(summary(w, h))
                }
                if let band, let primary {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.18)).frame(width: 14, height: 9)
                            .accessibilityHidden(true)
                        Text("Shaded band: your normal range, \(fmt(band.lowerBound))–\(fmt(band.upperBound)) \(def.unit) (\(primary.label), 30-day average ± 1 SD).")
                            .font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Low / average / high / trend

    private func statsPanel(_ series: StatSeries) -> some View {
        let sources = Source.allCases.filter { !series.points($0).isEmpty }
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTag(days == 365 ? String(localized: "Last year") : String(localized: "Last \(days) days"))
                    Spacer(minLength: Lab.S.s)
                    if !def.unit.isEmpty {
                        Text(def.unit).font(.footnote.weight(.medium)).foregroundStyle(Lab.faint)
                            .accessibilityHidden(true)
                    }
                }
                if sources.isEmpty {
                    EmptyNote(text: "Lowest, average and highest show up once readings arrive.", symbol: "number", title: "No data yet")
                }
                ForEach(sources) { s in
                    sourceStats(series.points(s), s)
                    if s != sources.last { Divider().overlay(Lab.line) }
                }
            }
        }
    }

    private func sourceStats(_ all: [StatPoint], _ s: Source) -> some View {
        let v = inRange(all).map(\.value)
        let cells: [(String, String?)] = [(String(localized: "Lowest"), v.min().map { fmt($0) }),
                                          (String(localized: "Average"), Stats.mean(v).map { fmt($0) }),
                                          (String(localized: "Highest"), v.max().map { fmt($0) }),
                                          (String(localized: "Days"), "\(v.count)")]
        return VStack(alignment: .leading, spacing: Lab.S.s) {
            HStack(spacing: Lab.S.s) {
                SourceChip(source: s)
                Spacer(minLength: Lab.S.xs)
                trendView(all)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s, alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 2 : 4),
                      alignment: .leading, spacing: Lab.S.sm) {
                ForEach(cells.indices, id: \.self) { i in
                    StatCell(caption: cells[i].0, value: cells[i].1, color: i == 3 ? Lab.dim : Lab.text, size: 18)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(s.name): lowest \(fmt(v.min())), average \(fmt(Stats.mean(v))), highest \(fmt(v.max())) \(def.unit), \(v.count) days.") + " " + (trendText(all) ?? ""))
    }

    /// This week's average vs the week before.
    private func weekChange(_ pts: [StatPoint]) -> (now: Double, before: Double)? {
        let today = Date().dayStart
        let a = pts.filter { $0.day >= today.adding(days: -6) }.map(\.value)
        let b = pts.filter { $0.day >= today.adding(days: -13) && $0.day < today.adding(days: -6) }.map(\.value)
        guard let x = Stats.mean(a), let y = Stats.mean(b) else { return nil }
        return (x, y)
    }

    private func isFlat(_ d: Double, _ base: Double) -> Bool {
        abs(d) < max(abs(base) * 0.02, 0.5 * pow(10, -Double(def.decimals)))
    }

    private func trendText(_ pts: [StatPoint]) -> String? {
        guard let c = weekChange(pts) else { return nil }
        let d = c.now - c.before
        if isFlat(d, c.before) { return String(localized: "About the same as last week.") }
        return d > 0 ? String(localized: "Up \(fmt(abs(d))) \(def.unit) vs last week.") : String(localized: "Down \(fmt(abs(d))) \(def.unit) vs last week.")
    }

    @ViewBuilder private func trendView(_ pts: [StatPoint]) -> some View {
        if let c = weekChange(pts) {
            let d = c.now - c.before
            let flat = isFlat(d, c.before)
            let good: Bool? = flat ? nil : info.better.map { ($0 == .higher) == (d > 0) }
            let color: Color = good == nil ? Lab.dim : (good == true ? Lab.good : Lab.warn)
            let amount = (d > 0 ? "+" : "−") + fmt(abs(d))
            TagChip(flat ? String(localized: "Steady vs last week") : String(localized: "\(amount) vs last week"),
                    tint: color,
                    symbol: flat ? "arrow.right" : (d > 0 ? "arrow.up.right" : "arrow.down.right"))
        }
    }

    // MARK: Agreement

    private func agreement(_ name: String) -> Agreement? {
        Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
            .first { $0.metric == name && $0.n > 0 }
    }

    private func agreementCard(_ a: Agreement) -> some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                CardHeader("Watch vs WHOOP", symbol: "bolt.horizontal.fill", tint: Lab.accent)
                HStack(spacing: Lab.S.m) {
                    ArcGauge(value: a.score, label: "Agree", color: a.score >= 70 ? Lab.good : a.score >= 45 ? Lab.warn : Lab.bad, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.verdict).font(.headline).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
                        Text("\(a.n) days measured by both").font(.footnote).foregroundStyle(Lab.dim)
                    }
                }
                Text(a.plain).font(.subheadline).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if !a.why.isEmpty { InfoBox(text: a.why) }
            }
        }
    }

    // MARK: Text cards

    private func textCard(_ title: String, _ body: String, icon: String) -> some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader(title, symbol: icon, tint: def.section.tint)
                Text(body).font(.subheadline).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var improveCard: some View {
        LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader("How to improve", symbol: "arrow.up.forward", tint: def.section.tint)
                ForEach(info.improve, id: \.self) { tip in
                    LabBullet(tip, tint: def.section.tint, color: Lab.text)
                }
            }
        }
    }

    private func sourcesCard(_ series: StatSeries) -> some View {
        let manual = store.manualDays(def, series: series)
        let first = [series.watch.first?.day, series.whoop.first?.day].compactMap { $0 }.min()
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader("Where it comes from", symbol: "antenna.radiowaves.left.and.right", tint: def.section.tint)
                if !series.watch.isEmpty {
                    sourceRow(store.badge(def, .watch, series: series), String(localized: "\(series.watch.count) days from Apple Health"))
                }
                if !series.whoop.isEmpty {
                    sourceRow("WHOOP", manual > 0 ? String(localized: "\(series.whoop.count) days, \(manual) typed in by hand")
                                                  : String(localized: "\(series.whoop.count) days synced from WHOOP"))
                }
                if series.isEmpty {
                    Text("Nothing has arrived yet. Check Sources in Settings and the Health permissions.")
                        .font(.subheadline).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L(def.note)).font(.footnote).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                if let first {
                    Text("History from \(first.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.footnote).foregroundStyle(Lab.faint)
                }
            }
        }
    }

    private func sourceRow(_ badge: String, _ text: String) -> some View {
        HStack(spacing: Lab.S.s) {
            SourceBadge(text: badge)
            Text(text).font(.subheadline).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func relatedCard(_ proxy: ScrollViewProxy) -> some View {
        let links = info.related.filter { $0 != def.id }.compactMap { AllStats.def($0) }
        if !links.isEmpty {
            LabPanel {
                VStack(alignment: .leading, spacing: Lab.S.xs) {
                    CardHeader("Related", symbol: "point.3.connected.trianglepath.dotted", tint: def.section.tint)
                    ForEach(Array(links.enumerated()), id: \.element.id) { i, link in
                        if i > 0 { Divider().overlay(Lab.line) }
                        relatedRow(link, proxy)
                    }
                }
            }
        }
    }

    private func relatedRow(_ link: StatDef, _ proxy: ScrollViewProxy) -> some View {
        Button {
            Lab.tick()
            if link.id == "readiness" { showReadiness = true; return }
            withAnimation(.snappy) {
                trail.append(def)
                def = link
                solo = nil
                proxy.scrollTo("top", anchor: .top)
            }
        } label: {
            HStack(spacing: Lab.S.sm) {
                SymbolTile(symbol: link.section.icon, tint: link.section.tint, size: 30)
                Text(L(link.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Lab.S.xs)
                if let v = latest(link) {
                    Text(v).font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(Lab.dim).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
            }
            .padding(.vertical, Lab.S.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityHint(String(localized: "Opens \(L(link.title))"))
    }

    private func latest(_ d: StatDef) -> String? {
        let s = d.read(store)
        guard let p = d.primary(s), let v = s.points(p).last?.value else { return nil }
        return v.formatted(.number.precision(.fractionLength(d.decimals))) + " " + d.unit
    }

    // MARK: Formatting

    private func fmt(_ v: Double?) -> String { v.map { $0.formatted(.number.precision(.fractionLength(def.decimals))) } ?? "—" }

    private func summary(_ w: [StatPoint], _ h: [StatPoint]) -> String {
        let parts = [(Source.watch, w), (Source.whoop, h)].map { s, p in
            guard let m = Stats.mean(p.map(\.value)) else { return String(localized: "\(s.name): no data") }
            return String(localized: "\(s.name) averages \(fmt(m)) \(def.unit) over \(p.count) days")
        }
        let range = days == 365 ? String(localized: "last year") : String(localized: "last \(days) days")
        let title = L(def.title)
        let detail = parts.joined(separator: ". ")
        return "\(title), \(range). \(detail)."
    }
}
