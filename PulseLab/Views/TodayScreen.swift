import SwiftUI
import Charts

struct TodayScreen: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        let notes = Insights.build(store)
        let streak = Insights.streak(store)
        LabScroll(kicker: Date().formatted(.dateTime.weekday(.wide).month().day()), title: "Today") {
            RivalryHero(rounds: Rivalry.rounds(store),
                        watchBPM: store.today(.watch)?.rhr, whoopBPM: store.today(.whoop)?.rhr,
                        readiness: store.readinessToday, recovery: store.recoveryToday,
                        note: gaugeNote)
            if streak >= 2 { StreakChip(days: streak) }
            LabNotesCard(insights: notes)
            hero
            sleepDuel
            sparkCard
            ShareVSButton()
            if !store.whoopConnected { whoopNudge }
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
