import SwiftUI
import Charts

/// A metric opened from Today, the tabs or a notification: the same detail screen as All data.
struct MetricDetailSheet: View {
    let metric: MetricKey
    @Environment(LabStore.self) private var store

    var body: some View {
        if let def = AllStats.def(metric.statID) {
            StatDetailSheet(def: def)
        } else {
            ZStack {
                LabBackground()
                EmptyNote(text: "No \(metric.title.lowercased()) yet.")
            }
            .preferredColorScheme(.dark)
        }
    }
}

/// Every metric's detail, one pattern everywhere: big current value with date and source, what it is,
/// your normal range shaded on a 7D/30D/90D/1Y chart (90D/1Y stay Pro via RangePicker), min/avg/max and the
/// trend vs last week, tracker agreement when both measure it, why it matters, how to improve, where the
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
                            LabPanel(tint: def.section.tint) {
                                VStack(alignment: .leading, spacing: Lab.S.s) {
                                    Text("No data yet").font(Lab.title(20)).foregroundStyle(Lab.text)
                                    Text(info.what).font(Lab.body(14)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        chartPanel(series, primary, band)
                        statsPanel(series)
                        if let name = StatGuide.compareName(def.id), let a = agreement(name) { agreementCard(a) }
                        textCard("Why it matters", info.why, icon: "lightbulb.fill")
                        improveCard
                        sourcesCard(series)
                        relatedCard(proxy)
                        Text("Pulse Lab is for general wellness and fitness, not medical advice.")
                            .font(Lab.body(11)).foregroundStyle(Lab.faint)
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
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Lab.S.s) {
            if let back = trail.last {
                Button {
                    Lab.tick()
                    withAnimation(.snappy) { def = back; trail.removeLast(); solo = nil }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.07)))
                }
                .accessibilityLabel("Back to \(back.title)")
            }
            ScreenTitle(kicker: def.section.title, title: def.title)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.07)))
            }
            .accessibilityLabel("Close")
        }
    }

    // MARK: Hero: value, date, source, what it is

    private func hero(_ series: StatSeries, _ src: Source, _ last: StatPoint, _ band: ClosedRange<Double>?) -> some View {
        let other: Source = src == .watch ? .whoop : .watch
        let otherLast = series.points(other).last
        let badge = store.badge(def, src, series: series)
        return LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    SourceBadge(text: badge)
                    Text(dayLabel(last.day)).font(Lab.label(9)).tracking(1).foregroundStyle(last.day.isToday ? Lab.good : Lab.dim)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmt(last.value)).font(Lab.number(52, .black)).foregroundStyle(Lab.color(src))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(def.unit).font(Lab.body(15, .semibold)).foregroundStyle(Lab.dim)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fmt(last.value)) \(def.unit), \(dayLabel(last.day).lowercased()), from \(badge)")
                if let band { normalLine(last.value, band) }
                if let o = otherLast {
                    HStack(spacing: 6) {
                        Circle().fill(Lab.color(other)).frame(width: 6, height: 6)
                        Text("\(other.name): \(fmt(o.value)) \(def.unit)").font(Lab.body(13, .semibold)).foregroundStyle(Lab.text)
                        Text(dayLabel(o.day)).font(Lab.label(8)).foregroundStyle(Lab.faint)
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider().overlay(Lab.line)
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHAT THIS IS").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                    Text(info.what).font(Lab.body(14)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
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
            Text(text).font(Lab.body(13, .semibold)).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
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
        return LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: 12) {
                RangePicker(days: $days)
                if !series.watch.isEmpty && !series.whoop.isEmpty { DuelLegend(solo: $solo) }
                if w.isEmpty && h.isEmpty {
                    EmptyNote(text: "No \(def.title.lowercased()) in the last \(days) days.")
                } else {
                    DuelChart(watch: w.map { DuelPoint(day: $0.day, value: $0.value, source: .watch) },
                              whoop: h.map { DuelPoint(day: $0.day, value: $0.value, source: .whoop) },
                              unit: def.unit, decimals: def.decimals, height: 220, showAverages: false,
                              showPoints: days <= 30, solo: solo, band: band)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(summary(w, h))
                }
                if let band, let primary {
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.18)).frame(width: 14, height: 9).padding(.top, 3)
                        Text("Shaded: your normal range, \(fmt(band.lowerBound))–\(fmt(band.upperBound)) \(def.unit) (\(primary.name), 30-day average ± 1 SD)")
                            .font(Lab.body(11)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Min / avg / max / trend

    private func statsPanel(_ series: StatSeries) -> some View {
        let sources = Source.allCases.filter { !series.points($0).isEmpty }
        return LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: 12) {
                Text(days == 365 ? "LAST YEAR" : "LAST \(days) DAYS").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                if sources.isEmpty {
                    Text("No data yet").font(Lab.body(13)).foregroundStyle(Lab.faint)
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
        let cells: [(String, String)] = [("MIN", fmt(v.min())), ("AVG", fmt(Stats.mean(v))), ("MAX", fmt(v.max())), ("DAYS", "\(v.count)")]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SourceChip(source: s)
                Spacer()
                trendView(all)
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cells.indices, id: \.self) { i in statCell(cells[i].0, cells[i].1, horizontal: true) }
                }
            } else {
                HStack(spacing: Lab.S.s) {
                    ForEach(cells.indices, id: \.self) { i in statCell(cells[i].0, cells[i].1, horizontal: false) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.name): minimum \(fmt(v.min())), average \(fmt(Stats.mean(v))), maximum \(fmt(v.max())), \(v.count) days. \(trendText(all) ?? "")")
    }

    @ViewBuilder private func statCell(_ label: String, _ value: String, horizontal: Bool) -> some View {
        if horizontal {
            HStack {
                Text(label).font(Lab.label(9)).foregroundStyle(Lab.faint)
                Spacer()
                Text(value).font(Lab.number(18)).foregroundStyle(label == "DAYS" ? Lab.dim : Lab.text)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(Lab.number(18)).foregroundStyle(label == "DAYS" ? Lab.dim : Lab.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(Lab.label(8)).foregroundStyle(Lab.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            HStack(spacing: 4) {
                Image(systemName: flat ? "arrow.right" : (d > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 11, weight: .heavy))
                Text(flat ? "steady" : (d > 0 ? "+" : "−") + fmt(abs(d)))
                    .font(Lab.mono(11, .heavy))
                Text("VS LAST WK").font(Lab.label(7)).foregroundStyle(Lab.faint)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.1)))
        }
    }

    // MARK: Agreement

    private func agreement(_ name: String) -> Agreement? {
        Compare.agreements(watch: store.watchDays, whoop: store.whoopDays, sleeps: store.sleeps, days: days)
            .first { $0.metric == name && $0.n > 0 }
    }

    private func agreementCard(_ a: Agreement) -> some View {
        LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Text("WATCH VS WHOOP").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                HStack(spacing: Lab.S.m) {
                    ArcGauge(value: a.score, label: "Agree", color: a.score >= 70 ? Lab.good : a.score >= 45 ? Lab.warn : Lab.bad, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.verdict).font(Lab.body(15, .bold)).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
                        Text("\(a.n) days measured by both").font(Lab.mono(11)).foregroundStyle(Lab.dim)
                    }
                }
                Text(a.plain).font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if !a.why.isEmpty {
                    Text(a.why).font(Lab.body(12)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Text cards

    private func textCard(_ title: String, _ body: String, icon: String) -> some View {
        LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L(title).uppercased(), systemImage: icon).font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                Text(body).font(Lab.body(14)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var improveCard: some View {
        LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Label("HOW TO IMPROVE", systemImage: "arrow.up.forward.circle.fill").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                ForEach(info.improve, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(def.section.tint).frame(width: 5, height: 5).padding(.top, 7)
                        Text(tip).font(Lab.body(14)).foregroundStyle(Lab.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sourcesCard(_ series: StatSeries) -> some View {
        let manual = store.manualDays(def, series: series)
        let first = [series.watch.first?.day, series.whoop.first?.day].compactMap { $0 }.min()
        return LabPanel(tint: def.section.tint) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                Label("WHERE IT COMES FROM", systemImage: "antenna.radiowaves.left.and.right").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
                if !series.watch.isEmpty {
                    sourceRow(store.badge(def, .watch, series: series), String(localized: "\(series.watch.count) days from Apple Health"))
                }
                if !series.whoop.isEmpty {
                    sourceRow("WHOOP", manual > 0 ? String(localized: "\(series.whoop.count) days, \(manual) typed in by hand")
                                                  : String(localized: "\(series.whoop.count) days synced from WHOOP"))
                }
                if series.isEmpty {
                    Text("Nothing has arrived yet. Check Sources in Settings and the Health permissions.").font(Lab.body(13)).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L(def.note)).font(Lab.body(12)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                if let first {
                    Text("History from \(first.formatted(.dateTime.month(.abbreviated).day().year()))").font(Lab.mono(10)).foregroundStyle(Lab.faint)
                }
            }
        }
    }

    private func sourceRow(_ badge: String, _ text: String) -> some View {
        HStack(spacing: Lab.S.s) {
            SourceBadge(text: badge)
            Text(text).font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func relatedCard(_ proxy: ScrollViewProxy) -> some View {
        let links = info.related.filter { $0 != def.id }.compactMap { AllStats.def($0) }
        if !links.isEmpty {
            LabPanel(tint: def.section.tint) {
                VStack(alignment: .leading, spacing: Lab.S.s) {
                    Label("RELATED", systemImage: "point.3.connected.trianglepath.dotted").font(Lab.label(9)).tracking(1.4).foregroundStyle(Lab.faint)
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
            HStack(spacing: Lab.S.s) {
                Image(systemName: link.section.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(link.section.tint)
                    .frame(width: 28)
                Text(L(link.title)).font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                Spacer()
                if let v = latest(link) {
                    Text(v).font(Lab.mono(12)).foregroundStyle(Lab.dim).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.faint)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Opens \(link.title)")
    }

    private func latest(_ d: StatDef) -> String? {
        let s = d.read(store)
        guard let p = d.primary(s), let v = s.points(p).last?.value else { return nil }
        return v.formatted(.number.precision(.fractionLength(d.decimals))) + " " + d.unit
    }

    // MARK: Formatting

    private func fmt(_ v: Double?) -> String { v.map { $0.formatted(.number.precision(.fractionLength(def.decimals))) } ?? "––" }

    private func summary(_ w: [StatPoint], _ h: [StatPoint]) -> String {
        [(Source.watch, w), (Source.whoop, h)].map { s, p in
            guard let m = Stats.mean(p.map(\.value)) else { return "\(s.name): no data" }
            return "\(s.name) averages \(fmt(m)) \(def.unit) over \(p.count) days"
        }
        .joined(separator: ". ")
    }
}
