import Charts
import SwiftUI

/// Every metric Pulse Lab syncs, in one place: the newest value with its day and source, a 7-day sparkline and
/// the other tracker's number. Metrics with no data stay listed (dimmed) so it's obvious what isn't arriving;
/// tapping one explains what it is and where it should come from.
@MainActor
struct AllDataScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("allDataHideEmpty") private var hideEmpty = false
    @State private var defs: [StatDef] = []
    @State private var series: [String: StatSeries] = [:]
    @State private var selected: StatDef?
    @State private var workoutLimit = 15
    @State private var quickEdit: WhoopQuickEdit?

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
                        CloseButton { dismiss() }
                    }
                    if store.loading { SyncProgressBar() }
                    if defs.isEmpty {
                        SkeletonStack()
                    } else {
                        if withData == 0 && !store.loading { nothingYet }
                        summary(withData: withData)
                        ForEach(StatSection.allCases) { section in
                            sectionPanel(section)
                        }
                        workoutsPanel
                    }
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
            Group {
                if def.id == "readiness" { ReadinessSheet() } else { StatDetailSheet(def: def) }
            }
            .environment(store)
            .presentationDetents([.large])
            .presentationBackground(Lab.bg)
        }
        .sheet(item: $quickEdit) { r in
            WhoopQuickEditSheet(request: r).environment(store).presentationBackground(Lab.bg)
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

    /// Nothing at all has synced: say why and offer the one thing that helps.
    private var nothingYet: some View {
        Group {
            if !store.healthAsked {
                LabEmptyState(icon: "heart.text.square.fill", title: "Connect Apple Health",
                              message: "Pulse Lab reads your Apple Watch data from Health (and anything WHOOP saves there). Nothing leaves your iPhone.",
                              button: "Connect Apple Health", tint: Lab.watch) {
                    Task { await store.connectHealth() }
                }
            } else {
                LabEmptyState(icon: "tray", title: "Nothing has arrived yet",
                              message: "Wear your Watch for a day, or check Settings → Health → Data Access → Pulse Lab. WHOOP numbers arrive once WHOOP is connected in Pulse Lab's Settings.",
                              button: "Sync now", tint: Lab.accent) {
                    Task { await store.refresh(.user) }
                }
            }
        }
    }

    private func summary(withData: Int) -> some View {
        let share = defs.isEmpty ? 0 : Double(withData) / Double(defs.count)
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(withData.formatted()).font(Lab.number(32)).foregroundStyle(Lab.text)
                        .contentTransition(.numericText(value: Double(withData)))
                    Text("of \(defs.count) metrics have data").font(.subheadline).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Lab.inset)
                        Capsule().fill(Lab.accent).frame(width: max(6, geo.size.width * share))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { sourcesLabel; badgesA; badgesB }
                    VStack(alignment: .leading, spacing: 6) { sourcesLabel; HStack(spacing: 6) { badgesA; badgesB } }
                    VStack(alignment: .leading, spacing: 6) { sourcesLabel; HStack(spacing: 6) { badgesA }; HStack(spacing: 6) { badgesB } }
                }
                Divider().overlay(Lab.line)
                Toggle(isOn: $hideEmpty.animation(.snappy)) {
                    Text("Hide metrics with no data").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                }
                .tint(Lab.accent)
                .sensoryFeedback(.selection, trigger: hideEmpty)
                Text("Tap any metric for what it means, your normal range, its chart and tips. Dimmed ones aren't arriving yet: tap one to see where it should come from.")
                    .font(.footnote).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourcesLabel: some View {
        Text("Sources").font(.footnote.weight(.medium)).foregroundStyle(Lab.dim)
    }

    @ViewBuilder private var badgesA: some View {
        SourceBadge(text: "WHOOP")
        SourceBadge(text: "WATCH")
    }

    @ViewBuilder private var badgesB: some View {
        SourceBadge(text: "IPHONE")
        SourceBadge(text: "HEALTH")
    }

    // MARK: Sections

    @ViewBuilder private func sectionPanel(_ section: StatSection) -> some View {
        let all = defs.filter { $0.section == section }
        let filled = all.filter { !(series[$0.id]?.isEmpty ?? true) }
        let shown = hideEmpty ? filled : all
        if !shown.isEmpty {
            LabPanel {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeader(section.title, symbol: section.icon, tint: section.tint) {
                        Text("\(filled.count) of \(all.count)")
                            .font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(Lab.faint)
                            .accessibilityLabel(String(localized: "\(filled.count) of \(all.count) with data"))
                    }
                    .padding(.bottom, Lab.S.xs)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, def in
                        if i > 0 { Divider().overlay(Lab.line) }
                        row(def)
                    }
                }
            }
        }
    }

    /// Steps and calories get a pencil for typing in WHOOP's number (WHOOP doesn't share them).
    private func row(_ def: StatDef) -> some View {
        let field: ManualField? = def.id == "steps" ? .steps : def.id == "totalKcal" ? .kcal : nil
        return HStack(spacing: Lab.S.xs) {
            rowButton(def)
            if let field {
                Button {
                    Lab.tick()
                    quickEdit = WhoopQuickEdit(field: field, day: Date().dayStart)
                } label: {
                    Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(Lab.whoop)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(field == .steps ? String(localized: "Type in WHOOP steps") : String(localized: "Type in WHOOP calories"))
            }
        }
    }

    private func rowButton(_ def: StatDef) -> some View {
        let s = series[def.id] ?? StatSeries()
        let primary = def.primary(s)
        return Button {
            Lab.tick()
            selected = def
        } label: {
            StatRowView(def: def, series: s, primary: primary, badge: primary.map { badge(def, $0) })
        }
        .buttonStyle(PressScale())
    }

    private func badge(_ def: StatDef, _ s: Source) -> String {
        store.badge(def, s, series: series[def.id] ?? StatSeries())
    }

    // MARK: Workouts

    private var workoutsPanel: some View {
        let all = store.workouts   // newest first
        return LabPanel {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                CardHeader("Workouts", symbol: "figure.run", tint: Lab.whoop) {
                    if !all.isEmpty {
                        Text(all.count.formatted()).font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(Lab.faint)
                    }
                }
                if all.isEmpty {
                    EmptyNote(text: "Workouts from your Watch's Workout app and WHOOP activities show up here.",
                              symbol: "figure.run", title: "No workouts yet")
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
                            Text("Show older workouts (\(all.count - workoutLimit))")
                        }
                        .buttonStyle(LabSecondaryButton())
                        .padding(.top, Lab.S.xs)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// Where a number came from: "WHOOP", "Watch", "iPhone", "Health" or an app's name, coloured like the rest of
/// the app. Stored badges are uppercase ("WATCH", "WHOOP · MANUAL"); they're shown in sentence case.
struct SourceBadge: View {
    let text: String
    private var color: Color {
        if text.hasPrefix("WHOOP") { return Lab.whoop }
        if text.contains("WATCH") { return Lab.watch }
        if text.contains("IPHONE") { return Lab.violet }
        return Lab.dim
    }

    static func display(_ raw: String) -> String {
        switch raw {
        case "WATCH": return "Watch"
        case "IPHONE": return "iPhone"
        case "HEALTH": return String(localized: "Health")
        case "WHOOP": return "WHOOP"
        case "WHOOP · MANUAL": return String(localized: "WHOOP · typed in")
        default: return raw.hasPrefix("WHOOP") ? raw : raw.capitalized
        }
    }

    var body: some View {
        Text(Self.display(text)).font(.caption2.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .fixedSize()
    }
}

/// One metric row: name, source + day, 7-day sparkline, newest value with its unit, and the other tracker.
struct StatRowView: View {
    let def: StatDef
    let series: StatSeries
    let primary: Source?
    let badge: String?
    @Environment(\.dynamicTypeSize) private var typeSize

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
        let name = VStack(alignment: .leading, spacing: 4) {
            Text(L(def.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let badge { SourceBadge(text: badge) }
                Text(dayLabel(last.day)).font(.caption).foregroundStyle(last.day.isToday ? Lab.good : Lab.faint)
            }
        }
        let value = VStack(alignment: .trailing, spacing: 2) {
            NumberUnit(value: fmt(last.value), unit: def.unit, color: Lab.color(src), size: 20)
            if let o = otherLast {
                Text(verbatim: "\(other.label) \(fmt(o.value))")
                    .font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Lab.color(other))
                    .lineLimit(1)
            }
        }
        let chevron = Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Lab.S.s) {
                    name
                    HStack { value; Spacer(minLength: 0); chevron }
                }
            } else {
                HStack(spacing: Lab.S.sm) {
                    name
                    Spacer(minLength: Lab.S.xs)
                    Sparkline(points: spark, color: Lab.color(src))
                        .frame(width: 56, height: 24)
                    value.frame(minWidth: 64, alignment: .trailing)
                    chevron
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(src, last, other, otherLast))
        .accessibilityHint("Opens details")
    }

    private func spoken(_ src: Source, _ last: StatPoint, _ other: Source, _ o: StatPoint?) -> String {
        var s = "\(L(def.title)): \(fmt(last.value)) \(def.unit), \(dayLabel(last.day)), \(SourceBadge.display(badge ?? src.label))"
        if let o { s += ". \(other.name) \(fmt(o.value)) \(def.unit)" }
        return s
    }

    private var empty: some View {
        HStack(spacing: Lab.S.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(def.title)).font(.subheadline.weight(.medium)).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No data yet").font(.caption).foregroundStyle(Lab.faint)
            }
            Spacer(minLength: Lab.S.xs)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .opacity(0.75)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(L(def.title)): no data yet"))
        .accessibilityHint("Shows what it is and where it comes from")
    }

    private func fmt(_ v: Double) -> String { Lab.fmt(v, def.decimals) }
}

/// "Today", "Yesterday" or a short date.
func dayLabel(_ d: Date) -> String {
    if d.isToday { return String(localized: "Today") }
    if Calendar.current.isDateInYesterday(d) { return String(localized: "Yesterday") }
    return d.formatted(.dateTime.month(.abbreviated).day())
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
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Cell: Identifiable {
        let caption: String
        let value: String
        let unit: String
        var id: String { caption }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Lab.S.s) {
            HStack(spacing: Lab.S.sm) {
                SymbolTile(symbol: w.symbol, tint: Lab.color(w.source), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.name).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) + " · " + fmtHM(w.minutes))
                        .font(.caption.monospacedDigit()).foregroundStyle(Lab.dim)
                }
                Spacer(minLength: Lab.S.xs)
                SourceChip(source: w.source)
            }
            let cells = stats
            if !cells.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s, alignment: .leading),
                                         count: typeSize.isAccessibilitySize ? 2 : 4),
                          alignment: .leading, spacing: Lab.S.s) {
                    ForEach(cells) { c in StatCell(caption: c.caption, value: c.value, unit: c.unit, size: 15) }
                }
            }
            if let z = w.zonesMin, z.reduce(0, +) > 0 { ZoneBar(minutes: z) }
        }
        .padding(.vertical, Lab.S.s)
        .accessibilityElement(children: .combine)
    }

    private var stats: [Cell] {
        var out: [Cell] = []
        if let v = w.avgHR { out.append(Cell(caption: String(localized: "Avg HR"), value: Lab.fmt(v), unit: "bpm")) }
        if let v = w.maxHR { out.append(Cell(caption: String(localized: "Max HR"), value: Lab.fmt(v), unit: "bpm")) }
        if let v = w.strain { out.append(Cell(caption: String(localized: "Strain"), value: Lab.fmt(v, 1), unit: "")) }
        if let v = w.kcal { out.append(Cell(caption: String(localized: "Energy"), value: Lab.fmt(v), unit: "kcal")) }
        if let km = w.distanceKm, km > 0 {
            let d = Units.distance(km)
            out.append(Cell(caption: String(localized: "Distance"), value: Lab.fmt(d.0 ?? km, 2), unit: d.1))
        }
        if let a = w.altitudeGainM, a > 0 {
            out.append(Cell(caption: String(localized: "Climb"), value: Lab.fmt(Units.imperial ? a * 3.28084 : a), unit: Units.imperial ? "ft" : "m"))
        }
        return out
    }
}

/// Heart-rate zones 0…5 as one stacked bar with minutes underneath.
struct ZoneBar: View {
    let minutes: [Double]
    private static let colors: [Color] = [Color.white.opacity(0.25), Lab.watch.opacity(0.6), Lab.good, Lab.warn, Lab.whoop, Lab.bad]

    var body: some View {
        let total = max(minutes.reduce(0, +), 0.001)
        let spoken = minutes.indices.filter { minutes[$0] >= 0.5 }
            .map { i in String(localized: "zone \(i) \(Int(minutes[i].rounded())) minutes") }
            .joined(separator: ", ")
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
        .accessibilityLabel(String(localized: "Heart rate zones: \(spoken)"))
    }
}
