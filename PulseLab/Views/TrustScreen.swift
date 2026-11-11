import SwiftUI

/// "Who to trust": for each metric, which tracker is the better source and why, with the user's
/// own agreement numbers (last 30 days) underneath. Pro, behind the same blurred teaser as VS.
/// Presented as a sheet from the VS screen and from Settings.
struct TrustScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        ZStack {
            LabBackground()
            if unlock.isPro {
                TrustContent(onClose: { dismiss() })
            } else {
                ProTeaser(symbol: "checkmark.shield.fill", title: "Who to trust is Pro",
                          message: "Metric by metric: which tracker to believe, why they differ, and how often yours agree.",
                          context: "Who to trust") {
                    TrustContent(onClose: nil)
                }
                .overlay(alignment: .topTrailing) {
                    closeButton.padding(.top, 10).padding(.trailing, Lab.S.m)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Lab.dim)
                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.06)))
        }
        .accessibilityLabel("Close")
    }
}

/// One line of guidance per metric.
struct TrustPick: Identifiable {
    let title: String
    let symbol: String
    /// Name used by `Compare.agreements`, when there is one, so the card can show your own numbers.
    let compareName: String?
    /// nil = both are fine.
    let trust: Source?
    let headline: String
    let reason: String
    var id: String { title }

    static let all: [TrustPick] = [
        TrustPick(title: "Sleep stages", symbol: "moon.zzz.fill", compareName: "Sleep", trust: .whoop,
                  headline: "WHOOP for sleep stages",
                  reason: "WHOOP's strap sits tighter and scores every night automatically, with no Sleep Focus or schedule to forget. Deep and REM splits are more consistent night to night. The Watch is fine for total time asleep."),
        TrustPick(title: "Resting HR", symbol: "heart.fill", compareName: "Resting HR", trust: .whoop,
                  headline: "WHOOP for resting HR",
                  reason: "WHOOP reads it during your deepest sleep, the same window every night, so day-to-day changes mean something. Apple's number mixes calm daytime moments and runs a few beats higher."),
        TrustPick(title: "HRV", symbol: "waveform.path.ecg", compareName: "HRV", trust: .whoop,
                  headline: "WHOOP for a daily HRV number",
                  reason: "RMSSD from slow-wave sleep is the standard recovery measure and is taken the same way every night. Apple's SDNN comes from scattered daytime samples, so use the Watch for the long trend, not today's reading."),
        TrustPick(title: "Recovery vs readiness", symbol: "bolt.heart.fill", compareName: nil, trust: .whoop,
                  headline: "WHOOP for the recovery score",
                  reason: "WHOOP's recovery is built from overnight HRV, resting HR, breathing and sleep. Pulse Lab's Watch readiness is our own recipe from the same ingredients, so treat it as a second opinion, not a tie-breaker."),
        TrustPick(title: "Steps", symbol: "figure.walk", compareName: nil, trust: .watch,
                  headline: "Watch for steps",
                  reason: "WHOOP doesn't count steps at all. The Watch (and iPhone) do, de-duplicated by Health."),
        TrustPick(title: "Workouts", symbol: "figure.run", compareName: nil, trust: .watch,
                  headline: "Watch for workouts",
                  reason: "GPS routes, pace, power, splits and a heart-rate trace you can inspect. WHOOP's auto-detected activities are great for strain, but they're HR-only and sometimes miss short sessions."),
        TrustPick(title: "Calories", symbol: "flame.fill", compareName: "Calories", trust: .watch,
                  headline: "Watch for calories",
                  reason: "Apple combines motion and heart rate, split into active and resting. WHOOP estimates one total from heart rate alone, so it undercounts walking and lifting."),
        TrustPick(title: "Blood oxygen", symbol: "lungs.fill", compareName: "Blood oxygen", trust: .watch,
                  headline: "Watch for SpO₂ spot checks",
                  reason: "The Watch can take a reading on demand and shows each sample. WHOOP only averages the night, which is fine for a trend but can't answer \"what is it right now?\"."),
        TrustPick(title: "ECG", symbol: "waveform.path.ecg.rectangle", compareName: nil, trust: .watch,
                  headline: "Watch, and only the Watch",
                  reason: "A single-lead ECG you can export as a PDF for a doctor. WHOOP has no equivalent."),
        TrustPick(title: "Respiratory rate", symbol: "wind", compareName: "Respiratory rate", trust: nil,
                  headline: "Both are fine",
                  reason: "Both measure overnight from the wrist. They land within a breath per minute of each other for most people."),
        TrustPick(title: "Temperature", symbol: "thermometer.medium", compareName: "Temp deviation", trust: nil,
                  headline: "Both, as a trend",
                  reason: "Each shows change from your own baseline, not a thermometer reading. A rise on either one is worth noticing; the size of the number isn't comparable between them."),
    ]
}

/// The scrolling list of trust cards (shown blurred inside the teaser when not Pro).
struct TrustContent: View {
    @Environment(LabStore.self) private var store
    /// nil when rendered as the blurred teaser background (no close control).
    let onClose: (() -> Void)?

    var body: some View {
        let list = store.agreements30
        ScrollView {
            VStack(alignment: .leading, spacing: Lab.S.m) {
                HStack(alignment: .top) {
                    ScreenTitle(kicker: "Lab verdict", title: "Who to trust")
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .accessibilityLabel("Close")
                    }
                }
                summary
                ForEach(TrustPick.all) { pick in
                    TrustCard(pick: pick, agreement: pick.compareName.flatMap { n in list.first { $0.metric == n } })
                }
                Text("Guidance is general: it's what each tracker is built to measure best. Your own agreement numbers (last 30 days) show where your two units actually line up.")
                    .font(Lab.body(12)).foregroundStyle(Lab.faint)
            }
            .padding(.horizontal, Lab.S.m)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private var summary: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                SectionTag("The short version")
                line(.whoop, "Sleep stages, resting HR, HRV, recovery")
                line(.watch, "Steps, workouts, calories, SpO₂ spot checks, ECG")
                HStack(alignment: .top, spacing: Lab.S.s) {
                    Text("BOTH").font(Lab.label(9)).tracking(1.5).foregroundStyle(Lab.violet)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Lab.violet.opacity(0.12)))
                    Text("Respiratory rate, temperature trend").font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ s: Source, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Lab.S.s) {
            SourceChip(source: s)
            Text(text).font(Lab.body(14, .semibold)).foregroundStyle(Lab.text)
        }
    }
}

/// One metric: who to trust, why, and how your own two trackers have agreed.
struct TrustCard: View {
    let pick: TrustPick
    let agreement: Agreement?

    private var tint: Color { pick.trust.map(Lab.color) ?? Lab.violet }

    var body: some View {
        LabPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: pick.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                        .frame(width: 30, height: 30).background(Circle().fill(tint.opacity(0.14)))
                    Text(pick.title).font(Lab.title(17)).foregroundStyle(Lab.text)
                    Spacer()
                    badge
                }
                Text(pick.headline).font(Lab.body(15, .bold)).foregroundStyle(tint)
                Text(pick.reason).font(Lab.body(13)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                if let why = pick.compareName.flatMap({ Compare.why[$0] }), !why.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Lab.violet).font(.system(size: 13)).padding(.top, 2)
                        Text(why).font(.system(size: 12, design: .rounded)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Lab.violet.opacity(0.08)))
                }
                if pick.compareName != nil { yourNumbers }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Text(pick.trust.map { "TRUST \($0.short)" } ?? "BOTH FINE")
            .font(Lab.label(9)).tracking(1.4).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    @ViewBuilder private var yourNumbers: some View {
        Divider().overlay(Lab.line)
        HStack(spacing: Lab.S.m) {
            Text("YOURS · 30D").font(Lab.label(8)).tracking(1.4).foregroundStyle(Lab.faint)
            if let a = agreement, a.n >= 3 {
                if let p = a.agreePercent {
                    stat(a.trendOnly ? "SAME WAY" : "AGREE", "\(Int(p.rounded()))%", p >= 70 ? Lab.good : p >= 45 ? Lab.warn : Lab.bad)
                }
                if !a.trendOnly, let b = a.bias {
                    stat(b >= 0 ? "WATCH +" : "WHOOP +", gap(b, a.unit), b >= 0 ? Lab.watch : Lab.whoop)
                } else if let r = a.correlation {
                    stat("R", String(format: "%.2f", r), Lab.text)
                }
                stat("DAYS", "\(a.n)", Lab.text)
            } else {
                Text(agreement.map { $0.n == 0 ? "No days measured by both yet" : "Only \($0.n) day\($0.n == 1 ? "" : "s") so far · needs 3" } ?? "No data yet")
                    .font(Lab.body(12)).foregroundStyle(Lab.faint)
            }
            Spacer()
        }
    }

    private func gap(_ b: Double, _ unit: String) -> String {
        String(format: abs(b) < 10 ? "%.1f" : "%.0f", abs(b)) + " " + unit
    }

    private func stat(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(Lab.mono(13, .heavy)).foregroundStyle(c)
            Text(l).font(Lab.label(7)).tracking(1.2).foregroundStyle(Lab.faint)
        }
    }
}
