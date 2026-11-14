import Charts
import SwiftUI

/// Every metric Pulse Lab syncs, in one place: today's (or the newest) value, a 7-day sparkline and where
/// it came from. Metrics with no data stay listed (dimmed) so it's obvious what isn't arriving.
@MainActor
struct AllDataScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("allDataHideEmpty") private var hideEmpty = false
    @State private var defs: [StatDef] = []
    @State private var series: [String: StatSeries] = [:]
    @State private var selected: StatDef?
    @State private var workoutLimit = 15

    /// Changes whenever the store's data does, so the catalogue is rebuilt once per sync, not per frame.
    private var dataStamp: String {
        "\(store.lastPull?.timeIntervalSince1970 ?? 0)-\(store.watchDays.count)-\(store.whoopDays.count)-\(store.sleeps.count)-\(store.workouts.count)-\(Units.imperial)-\(Units.fahrenheit)"
    }

    var body: some View {
        let withData = defs.filter { !(series[$0.id]?.isEmpty ?? true) }.count
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: "Everything that syncs", title: "All data")
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .accessibilityLabel("Close")
                    }
                    if store.loading { SyncProgressBar() }
                    summary(withData: withData)
                    ForEach(StatSection.allCases) { section in
                        sectionPanel(section)
                    }
                    workoutsPanel
                }
                .padding(.horizontal, Lab.S.m)
                .padding(.top, Lab.S.m)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh(.user) }
        }
        .preferredColorScheme(.dark)
        .task(id: dataStamp) { rebuild() }
        .sheet(item: $selected) { def in
            StatDetailSheet(def: def, series: series[def.id] ?? StatSeries(), badge: badge(def, .watch), whoopBadge: badge(def, .whoop))
                .presentationDetents([.large])
                .presentationBackground(Lab.bg)
        }
    }

    private func rebuild() {
        let d = AllStats.defs()
        var s: [String: StatSeries] = [:]
        for def in d { s[def.id] = def.read(store) }
        defs = d
        series = s
    }

    // MARK: Header

    private func summary(withData: Int) -> some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(withData)").font(Lab.number(30, .black)).foregroundStyle(Lab.text)
                    Text("of \(defs.count) metrics have data").font(Lab.body(13)).foregroundStyle(Lab.dim)
                    Spacer()
                }
                HStack(spacing: 6) {
                    badgeView("WHOOP"); badgeView("WATCH"); badgeView("IPHONE"); badgeView("HEALTH")
                }
                Toggle(isOn: $hideEmpty.animation(.snappy)) {
                    Text("Hide metrics with no data").font(Lab.body(13, .semibold)).foregroundStyle(Lab.text)
                }
                .tint(Lab.violet)
                Text("Tap any row for its 7-day, 30-day, 90-day and 1-year chart. Dimmed rows aren't arriving yet: check Sources or the Health permissions.")
                    .font(Lab.body(11)).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private func sectionPanel(_ section: StatSection) -> some View {
        let all = defs.filter { $0.section == section }
        let filled = all.filter { !(series[$0.id]?.isEmpty ?? true) }
        let shown = hideEmpty ? filled : all
        if !shown.isEmpty {
            LabPanel(tint: section.tint) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: section.icon).foregroundStyle(section.tint)
                        Text(section.title).font(Lab.display(18, .heavy)).foregroundStyle(Lab.text)
                        Spacer()
                        Text("\(filled.count)/\(all.count)").font(Lab.mono(11)).foregroundStyle(Lab.faint)
                    }
                    .padding(.bottom, Lab.S.s)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, def in
                        if i > 0 { Divider().overlay(Lab.line) }
                        row(def)
                    }
                }
            }
        }
    }

    private func row(_ def: StatDef) -> some View {
        let s = series[def.id] ?? StatSeries()
        let primary = primarySource(def, s)
        return Button {
            Lab.tick()
            selected = def
        } label: {
            StatRowView(def: def, series: s, primary: primary,
                        badge: primary.map { badge(def, $0) },
                        otherBadge: primary.map { badge(def, $0 == .watch ? .whoop : .watch) })
        }
        .buttonStyle(PressScale())
        .disabled(s.isEmpty)
    }

    /// The side whose newest value is most recent (ties go to the metric's preferred side).
    private func primarySource(_ def: StatDef, _ s: StatSeries) -> Source? {
        switch (s.watch.last, s.whoop.last) {
        case (nil, nil): return nil
        case (_, nil): return .watch
        case (nil, _): return .whoop
        case let (w?, h?):
            if w.day == h.day { return def.preferWhoop ? .whoop : .watch }
            return w.day > h.day ? .watch : .whoop
        }
    }

    private func badge(_ def: StatDef, _ s: Source) -> String {
        if s == .whoop {
            // The newest WHOOP number was typed in (Log WHOOP), not synced.
            if let f = ManualField.forStat(def.id), let d = series[def.id]?.whoop.last?.day, store.isManual(d, f) { return "WHOOP · MANUAL" }
            return "WHOOP"
        }
        if let id = def.healthID, let o = store.appleOrigins[id] { return o }
        return def.appleBadge
    }

    private func badgeView(_ t: String) -> some View { SourceBadge(text: t) }

    // MARK: Workouts

    private var workoutsPanel: some View {
        let all = store.workouts   // newest first
        return LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                HStack {
                    Image(systemName: "figure.run").foregroundStyle(Lab.whoop)
                    Text("Workouts").font(Lab.display(18, .heavy)).foregroundStyle(Lab.text)
                    Spacer()
                    Text("\(all.count)").font(Lab.mono(11)).foregroundStyle(Lab.faint)
                }
                if all.isEmpty {
                    Text("No data yet").font(Lab.body(13)).foregroundStyle(Lab.faint).padding(.vertical, 6)
                } else {
                    ForEach(Array(all.prefix(workoutLimit).enumerated()), id: \.element.id) { i, w in
                        if i > 0 { Divider().overlay(Lab.line) }
                        WorkoutRowView(w: w)
                    }
                    if all.count > workoutLimit {
                        Button {
                            Lab.tick()
                            withAnimation(.snappy) { workoutLimit += 30 }
                        } label: {
                            Text("Show more (\(all.count - workoutLimit) older)").font(Lab.mono(12, .heavy)).foregroundStyle(Lab.violet)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// "WHOOP" / "WATCH" / "IPHONE" / app-name badge, coloured like the rest of the app.
struct SourceBadge: View {
    let text: String
    private var color: Color {
        if text.hasPrefix("WHOOP") { return Lab.whoop }
        if text.contains("WATCH") { return Lab.watch }
        if text.contains("IPHONE") { return Lab.violet }
        return Lab.dim
    }
    var body: some View {
        Text(text).font(Lab.label(8)).tracking(1).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
    }
}

/// One metric row: title, badge + date, 7-day sparkline, newest value.
struct StatRowView: View {
    let def: StatDef
    let series: StatSeries
    let primary: Source?
    let badge: String?
    let otherBadge: String?

    var body: some View {
        if let primary, let last = series.points(primary).last {
            filled(primary, last)
        } else {
            empty
        }
    }

    private func filled(_ src: Source, _ last: StatPoint) -> some View {
        let other: Source = src == .watch ? .whoop : .watch
        let otherLast = series.points(other).last
        let spark = series.points(src).filter { $0.day >= Date().dayStart.adding(days: -6) }
        return HStack(spacing: Lab.S.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text(def.title).font(Lab.body(14, .semibold)).foregroundStyle(Lab.text).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    if let badge { SourceBadge(text: badge) }
                    Text(dayLabel(last.day)).font(Lab.label(8)).foregroundStyle(last.day.isToday ? Lab.good : Lab.faint)
                }
            }
            Spacer(minLength: 4)
            Sparkline(points: spark, color: Lab.color(src))
                .frame(width: 64, height: 26)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(fmt(last.value)).font(Lab.number(19, .black)).foregroundStyle(Lab.color(src))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(def.unit).font(Lab.label(8)).foregroundStyle(Lab.faint).lineLimit(1)
                }
                if let o = otherLast {
                    HStack(spacing: 3) {
                        Circle().fill(Lab.color(other)).frame(width: 4, height: 4)
                        Text(fmt(o.value)).font(Lab.mono(10)).foregroundStyle(Lab.color(other).opacity(0.85))
                        if let otherBadge { Text(otherBadge).font(Lab.label(7)).foregroundStyle(Lab.faint).lineLimit(1) }
                    }
                }
            }
            .frame(minWidth: 70, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(Lab.faint)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(def.title): \(fmt(last.value)) \(def.unit), \(dayLabel(last.day).lowercased()), from \(badge ?? "")\(otherLast.map { ". Other tracker: \(fmt($0.value))" } ?? "")")
        .accessibilityHint("Opens the chart")
    }

    private var empty: some View {
        HStack {
            Text(def.title).font(Lab.body(14, .medium)).foregroundStyle(Lab.faint).lineLimit(1)
            Spacer()
            Text("No data yet").font(Lab.label(9)).tracking(1).foregroundStyle(Lab.faint)
        }
        .padding(.vertical, 9)
        .opacity(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(def.title): no data yet")
    }

    private func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(def.decimals))) }
}

func dayLabel(_ d: Date) -> String {
    if d.isToday { return "TODAY" }
    if Calendar.current.isDateInYesterday(d) { return "YESTERDAY" }
    return d.formatted(.dateTime.month(.abbreviated).day()).uppercased()
}

/// Tiny 7-day line, no axes.
struct Sparkline: View {
    let points: [StatPoint]
    let color: Color
    var body: some View {
        if points.count >= 2 {
            let v = points.map(\.value)
            let lo = v.min() ?? 0, hi = v.max() ?? 1
            let pad = max((hi - lo) * 0.15, max(abs(hi) * 0.01, 0.01))
            Chart {
                ForEach(points, id: \.day) { p in
                    LineMark(x: .value("Day", p.day), y: .value("V", p.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.day), y: .value("V", last.value)).foregroundStyle(color).symbolSize(14)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .accessibilityHidden(true)
        } else if let p = points.first {
            HStack { Spacer(); Circle().fill(color).frame(width: 5, height: 5) }
                .accessibilityHidden(true)
                .id(p.day)
        } else {
            Capsule().fill(Color.white.opacity(0.06)).frame(height: 2)
                .accessibilityHidden(true)
        }
    }
}

/// One workout with everything we know about it.
struct WorkoutRowView: View {
    let w: WorkoutRec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Lab.S.s) {
                Image(systemName: w.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Lab.color(w.source))
                    .frame(width: 30, height: 30).background(Circle().fill(Lab.color(w.source).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.name).font(Lab.body(14, .semibold)).foregroundStyle(Lab.text).lineLimit(1)
                    Text(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) + " · " + fmtHM(w.minutes))
                        .font(Lab.mono(10)).foregroundStyle(Lab.faint)
                }
                Spacer()
                SourceBadge(text: w.source == .whoop ? "WHOOP" : "WATCH")
            }
            HStack(spacing: 10) {
                if let v = w.avgHR { stat("AVG HR", "\(Int(v.rounded()))") }
                if let v = w.maxHR { stat("MAX HR", "\(Int(v.rounded()))") }
                if let v = w.strain { stat("STRAIN", v.formatted(.number.precision(.fractionLength(1)))) }
                if let v = w.kcal { stat("KCAL", "\(Int(v.rounded()))") }
                if let km = w.distanceKm, km > 0 {
                    let d = Units.distance(km)
                    stat(d.1.uppercased(), (d.0 ?? km).formatted(.number.precision(.fractionLength(2))))
                }
                if let a = w.altitudeGainM, a > 0 { stat(Units.imperial ? "FT UP" : "M UP", "\(Int((Units.imperial ? a * 3.28084 : a).rounded()))") }
            }
            if let z = w.zonesMin, z.reduce(0, +) > 0 { ZoneBar(minutes: z) }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Lab.mono(12, .heavy)).foregroundStyle(Lab.text)
            Text(l).font(Lab.label(7)).foregroundStyle(Lab.faint)
        }
    }
}

/// Heart-rate zones 0…5 as one stacked bar with minutes underneath.
struct ZoneBar: View {
    let minutes: [Double]
    private static let colors: [Color] = [Color.white.opacity(0.25), Lab.watch.opacity(0.6), Lab.good, Lab.warn, Lab.whoop, Lab.bad]

    var body: some View {
        let total = max(minutes.reduce(0, +), 0.001)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(minutes.indices, id: \.self) { i in
                        if minutes[i] > 0 {
                            Rectangle().fill(Self.colors[min(i, Self.colors.count - 1)])
                                .frame(width: max(2, geo.size.width * minutes[i] / total))
                        }
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            HStack(spacing: 8) {
                ForEach(minutes.indices, id: \.self) { i in
                    if minutes[i] >= 0.5 {
                        HStack(spacing: 3) {
                            Circle().fill(Self.colors[min(i, Self.colors.count - 1)]).frame(width: 5, height: 5)
                            Text("Z\(i) \(Int(minutes[i].rounded()))m").font(Lab.mono(9, .medium)).foregroundStyle(Lab.dim)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zones: " + minutes.indices.filter { minutes[$0] >= 0.5 }.map { "zone \($0) \(Int(minutes[$0].rounded())) minutes" }.joined(separator: ", "))
    }
}

// MARK: - Detail

/// Any All-data metric over 7 days to a year (90D/1Y stay Pro, via RangePicker), both trackers, plus min/avg/max.
struct StatDetailSheet: View {
    let def: StatDef
    let series: StatSeries
    let badge: String
    var whoopBadge = "WHOOP"
    @Environment(\.dismiss) private var dismiss
    @State private var days = 30
    @State private var solo: Source?

    private func inRange(_ s: Source) -> [StatPoint] {
        let cut = Date().dayStart.adding(days: -(days - 1))
        return series.points(s).filter { $0.day >= cut }
    }

    var body: some View {
        let w = inRange(.watch), h = inRange(.whoop)
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: def.section.title, title: def.title)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.07)))
                        }
                        .accessibilityLabel("Close")
                    }
                    RangePicker(days: $days)
                    LabPanel(tint: def.section.tint) {
                        VStack(alignment: .leading, spacing: 10) {
                            DuelLegend(solo: $solo)
                            if w.isEmpty && h.isEmpty {
                                EmptyNote(text: "No \(def.title.lowercased()) in the last \(days) days.")
                            } else {
                                DuelChart(watch: w.map { DuelPoint(day: $0.day, value: $0.value, source: .watch) },
                                          whoop: h.map { DuelPoint(day: $0.day, value: $0.value, source: .whoop) },
                                          unit: def.unit, decimals: def.decimals, height: 240, showPoints: days <= 30, solo: solo)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(summary(w, h))
                            }
                        }
                    }
                    table(w, h)
                    LabPanel(tint: Lab.violet) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTag("What it is · where it comes from")
                            Text(def.note).font(Lab.body(14)).foregroundStyle(Lab.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                if !series.watch.isEmpty { SourceBadge(text: badge) }
                                if !series.whoop.isEmpty { SourceBadge(text: whoopBadge) }
                                Spacer()
                                if let first = [series.watch.first?.day, series.whoop.first?.day].compactMap({ $0 }).min() {
                                    Text("History from \(first.formatted(.dateTime.month(.abbreviated).day().year()))")
                                        .font(Lab.mono(10)).foregroundStyle(Lab.faint)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func table(_ w: [StatPoint], _ h: [StatPoint]) -> some View {
        LabPanel(tint: Lab.violet) {
            VStack(spacing: 10) {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(["LATEST", "MIN", "AVG", "MAX", "DAYS"], id: \.self) { t in
                        Text(t).font(Lab.label(8)).foregroundStyle(Lab.faint).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                ForEach(Source.allCases) { s in
                    let pts = s == .watch ? w : h
                    if !series.points(s).isEmpty {
                        let v = pts.map(\.value)
                        HStack {
                            SourceChip(source: s).frame(maxWidth: .infinity, alignment: .leading)
                            cell(series.points(s).last?.value, s)
                            cell(v.min(), s)
                            cell(Stats.mean(v), s)
                            cell(v.max(), s)
                            Text("\(v.count)").font(Lab.mono(12)).foregroundStyle(Lab.dim).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(s.name): latest \(fmt(series.points(s).last?.value)), minimum \(fmt(v.min())), average \(fmt(Stats.mean(v))), maximum \(fmt(v.max())), \(v.count) days")
                    }
                }
            }
        }
    }

    private func cell(_ v: Double?, _ s: Source) -> some View {
        Text(fmt(v)).font(Lab.mono(13, .heavy)).foregroundStyle(Lab.color(s))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .minimumScaleFactor(0.6).lineLimit(1)
    }

    private func fmt(_ v: Double?) -> String { v.map { $0.formatted(.number.precision(.fractionLength(def.decimals))) } ?? "––" }

    private func summary(_ w: [StatPoint], _ h: [StatPoint]) -> String {
        [(Source.watch, w), (Source.whoop, h)].map { s, p in
            guard let m = Stats.mean(p.map(\.value)) else { return "\(s.name): no data" }
            return "\(s.name) averages \(fmt(m)) \(def.unit) over \(p.count) days"
        }
        .joined(separator: ". ")
    }
}
