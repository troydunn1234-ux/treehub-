import SwiftUI
import Charts

/// Today: "Stress & recovery across apps". The last 7 days of grounded time (Still Pointz calm practice plus
/// Rootbound tree hugs not already linked to one of those sessions) and time on foot (Roamr walks, runs and hikes),
/// next to Pulse Lab's own numbers: over the last 30 days, the Watch's next-morning HRV after days with 10+ grounded
/// minutes vs the other days, once each side has 3 days. Read-only on the shared feed (Shared/Wellness/
/// WellnessFamily.swift); taps open Still Pointz' Journey or Roamr's history. Hidden when none of the three apps
/// is installed or they shared nothing this week.
@MainActor
struct RecoveryAcrossAppsCard: View {
    @Environment(LabStore.self) private var store
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    private static let calmBlue = Color(red: 0.56, green: 0.64, blue: 1.0)
    private static let footOrange = Color(red: 1.0, green: 0.58, blue: 0.28)

    var body: some View {
        let anyPeer = feed.has(WellnessConnect.stillPoint) || feed.has(WellnessConnect.rootbound) || feed.has(WellnessConnect.roamr)
        let week = weekLoads
        let hasData = week.contains { $0.groundedMin > 0 || $0.onFootMin > 0 }
        if anyPeer && hasData {
            LabPanel {
                VStack(alignment: .leading, spacing: Lab.S.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTag("Stress & recovery across apps")
                        Text("Grounded time and time on foot, last 7 days")
                            .font(.footnote).foregroundStyle(Lab.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    chart(week)
                    totals(week)
                    insight
                    links
                }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    // MARK: Data

    private var weekLoads: [WellnessConnect.DayLoad] {
        if WellnessConnect.isDemo { return WellnessConnect.sampleDayLoads() }
        return WellnessConnect.dayLoads(7, endingOn: Date(), stillPoint: feed.stillPoint, rootbound: feed.rootbound, roamr: feed.roamr)
    }

    private var effect: WellnessConnect.CalmEffect? {
        if WellnessConnect.isDemo {
            return .init(afterCalm: 58, afterOther: 51, calmDays: 9, otherDays: 12, threshold: 10)
        }
        let loads = WellnessConnect.dayLoads(30, endingOn: Date(), stillPoint: feed.stillPoint, rootbound: feed.rootbound, roamr: feed.roamr)
        // One HRV scale only: the Watch's (SDNN), else WHOOP's (RMSSD) when there's no Watch data at all.
        let days = store.watchDays.contains(where: { $0.hrv != nil }) ? store.watchDays : store.whoopDays
        var hrv: [Date: Double] = [:]
        for d in days { if let v = d.hrv { hrv[Calendar.current.startOfDay(for: d.day)] = v } }
        return WellnessConnect.calmEffect(loads, hrv: hrv)
    }

    // MARK: Pieces

    private func chart(_ week: [WellnessConnect.DayLoad]) -> some View {
        Chart {
            ForEach(week) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.groundedMin))
                    .foregroundStyle(by: .value("Kind", String(localized: "Grounded")))
                    .position(by: .value("Kind", String(localized: "Grounded")))
                    .cornerRadius(3)
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.onFootMin))
                    .foregroundStyle(by: .value("Kind", String(localized: "On foot")))
                    .position(by: .value("Kind", String(localized: "On foot")))
                    .cornerRadius(3)
            }
        }
        .chartForegroundStyleScale(domain: [String(localized: "Grounded"), String(localized: "On foot")], range: [Self.calmBlue, Self.footOrange])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Lab.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Lab.line)
                AxisValueLabel().foregroundStyle(Lab.faint)
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Grounded minutes and minutes on foot for the last 7 days"))
        .accessibilityValue(week.map { d in
            d.day.formatted(.dateTime.weekday(.wide)) + ": " + WellnessConnect.minutes(d.groundedMin) + " grounded, "
                + WellnessConnect.minutes(d.onFootMin) + " on foot"
        }.joined(separator: "; "))
    }

    private func totals(_ week: [WellnessConnect.DayLoad]) -> some View {
        let calm = week.reduce(0) { $0 + $1.calmMin }
        let hugs = week.reduce(0) { $0 + $1.hugMin }
        let foot = week.reduce(0) { $0 + $1.onFootMin }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Lab.S.s) { totalChips(calm: calm, hugs: hugs, foot: foot) }
            VStack(alignment: .leading, spacing: Lab.S.s) { totalChips(calm: calm, hugs: hugs, foot: foot) }
        }
    }

    @ViewBuilder
    private func totalChips(calm: Double, hugs: Double, foot: Double) -> some View {
        chip(String(localized: "Calm practice"), WellnessConnect.minutes(calm), Self.calmBlue)
        if hugs > 0 { chip(String(localized: "Tree hugs"), WellnessConnect.minutes(hugs), Color(red: 0.45, green: 0.80, blue: 0.45)) }
        chip(String(localized: "On foot"), WellnessConnect.minutes(foot), Self.footOrange)
    }

    private func chip(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Lab.mono(15, .bold)).foregroundStyle(Lab.text)
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(tint)
        }
        .padding(.horizontal, Lab.S.sm).padding(.vertical, Lab.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var insight: some View {
        HStack(alignment: .top, spacing: Lab.S.s) {
            Image(systemName: "arrow.triangle.branch")
                .font(.footnote.weight(.bold)).foregroundStyle(Lab.accent)
                .accessibilityHidden(true)
            Group {
                if let e = effect {
                    let diff = e.afterCalm - e.afterOther
                    Text(String(localized: "After days with \(Int(e.threshold))+ grounded minutes, your next-morning HRV averaged \(Int(e.afterCalm.rounded())) ms, vs \(Int(e.afterOther.rounded())) ms after other days (\(e.calmDays) vs \(e.otherDays) days)."))
                        + Text(diff >= 1 ? String(localized: " Calm time seems to help you recover.")
                               : String(localized: " No clear lift yet."))
                } else {
                    Text("Log a few calm days in Still Pointz or Rootbound and Pulse Lab will compare your next-morning HRV after them.")
                }
            }
            .font(.footnote).foregroundStyle(Lab.dim)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Lab.S.s) { linkButtons }
            VStack(alignment: .leading, spacing: Lab.S.s) { linkButtons }
        }
    }

    @ViewBuilder
    private var linkButtons: some View {
        if feed.has(WellnessConnect.stillPoint) {
            linkButton(String(localized: "Breathe in Still Pointz"), "wind", Self.calmBlue) {
                WellnessConnect.open(WellnessConnect.stillPointJourney, in: WellnessConnect.stillPoint)
            }
        }
        if feed.has(WellnessConnect.roamr) {
            linkButton(String(localized: "Walks in Roamr"), "figure.walk", Self.footOrange) {
                WellnessConnect.open(WellnessConnect.roamrHistory, in: WellnessConnect.roamr)
            }
        }
    }

    private func linkButton(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            taps += 1
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, Lab.S.sm)
                .frame(minHeight: 44)
                .background(Capsule().fill(tint.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
