import SwiftUI
import Charts

struct TodayScreen: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        let notes = Insights.build(store)
        let streak = Insights.streak(store)
        LabScroll(kicker: Date().formatted(.dateTime.weekday(.wide).month().day()), title: "Today") {
            if streak >= 2 { StreakChip(days: streak) }
            gauges
            LabNotesCard(insights: notes)
            hero
            sleepDuel
            sparkCard
            ShareVSButton()
            if !store.whoopConnected { whoopNudge }
        }
    }

    // Two gauges: WHOOP recovery vs Pulse Lab's Watch readiness.
    private var gauges: some View {
        LabPanel(tint: Lab.violet) {
            VStack(spacing: 14) {
                HStack {
                    SectionTag("Ready check")
                    Spacer()
                    Text("VS").font(Lab.display(13)).foregroundStyle(Lab.faint)
                }
                HStack {
                    VStack(spacing: 8) {
                        GaugeRing(value: store.readinessToday, label: "Readiness", color: Lab.watch, size: 128)
                        SourceChip(source: .watch)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 8) {
                        GaugeRing(value: store.recoveryToday, label: "Recovery", color: store.recoveryToday.map(Lab.band) ?? Lab.whoop, size: 128)
                        SourceChip(source: .whoop)
                    }
                    .frame(maxWidth: .infinity)
                }
                Text(gaugeNote).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
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
                Text("Tap a row for the full chart").font(Lab.label(9)).foregroundStyle(Lab.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .breathingGlow([Lab.watch, Lab.violet, Lab.whoop])
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
        .buttonStyle(.plain)
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
                SectionTag("Resting HR · 14 days")
                Chart {
                    ForEach(Source.allCases) { s in
                        ForEach(store.days(s).recent(14).filter { $0.rhr != nil }) { d in
                            LineMark(x: .value("Day", d.day, unit: .day), y: .value("bpm", d.rhr ?? 0))
                                .foregroundStyle(by: .value("Source", s.name))
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                    }
                }
                .chartForegroundStyleScale([Source.watch.name: Lab.watch, Source.whoop.name: Lab.whoop])
                .chartLegend(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis { LabAxis.y }
                .frame(height: 120)
                .shadow(color: Lab.watch.opacity(0.25), radius: 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rhrSummary)
            }
        }
        .onTapGesture { store.detail = .rhr }
        .accessibilityAddTraits(.isButton)
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
