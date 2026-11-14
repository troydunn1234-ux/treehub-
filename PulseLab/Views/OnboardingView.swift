import SwiftUI

/// Three welcome screens: what Pulse Lab compares, connect Health (asked only when you tap), then WHOOP
/// and your Stack, with the morning notification as an opt-in that asks for permission only if switched on.
struct OnboardingView: View {
    var done: () -> Void
    @Environment(LabStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var healthDone = false
    @State private var briefing = MorningBriefing.enabled
    @State private var notifyDenied = false

    private let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                compares.tag(0)
                connectHealth.tag(1)
                whoopAndStack.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            dots.padding(.bottom, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Page \(page + 1) of \(pages)"))
            if page == 0 {
                Button { go(1) } label: { primary(String(localized: "Next")) }
                    .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private func go(_ p: Int) {
        if reduceMotion { page = p } else { withAnimation(.snappy) { page = p } }
    }

    /// 1 · What it compares.
    private var compares: some View {
        ScrollView {
            VStack(spacing: 20) {
                pulseArt.padding(.top, 36)
                Text(String(localized: "Two trackers.\nOne lab.")).font(Lab.display(38)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 14) {
                    feature("chart.xyaxis.line", String(localized: "Head to head"),
                            String(localized: "Resting HR, HRV, sleep stages, breathing, blood oxygen, temperature, calories and workouts from your Watch and WHOOP, side by side."))
                    feature("scope", String(localized: "Who agrees"),
                            String(localized: "Agreement scores and a readiness score from your Watch to sit next to WHOOP recovery."))
                    feature("sun.max.fill", String(localized: "Morning briefing"),
                            String(localized: "Recovery, sleep vs your week and HRV vs your baseline in one card."))
                    feature("chart.dots.scatter", String(localized: "Insights"),
                            String(localized: "How your next morning looks after supplements, sauna, workouts and late meals."))
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Lab.watch)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Lab.display(16, .heavy)).foregroundStyle(Lab.text)
                Text(text).font(Lab.body(14)).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Two glowing pulse lines (cyan Watch, amber WHOOP) that scroll.
    private var pulseArt: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Lab.reduceMotion)) { tl in
        let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3)
        Canvas { context, size in
            for (i, color) in [Lab.watch, Lab.whoop].enumerated() {
                var ctx = context
                var path = Path()
                let mid = size.height / 2 + CGFloat(i) * 10 - 5
                for x in stride(from: 0, through: size.width, by: 2) {
                    let t = (x / size.width + phase + CGFloat(i) * 0.08).truncatingRemainder(dividingBy: 1)
                    var y = mid + sin(x / 18 + CGFloat(i)) * 3
                    if t > 0.42 && t < 0.5 { y = mid - sin((t - 0.42) / 0.08 * .pi) * (size.height * 0.42) * (i == 0 ? 1 : 0.8) }
                    if t > 0.5 && t < 0.55 { y = mid + sin((t - 0.5) / 0.05 * .pi) * size.height * 0.18 }
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.addFilter(.shadow(color: color, radius: 6))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        }
        .frame(height: 120)
        .padding(.horizontal, 24)
        .accessibilityHidden(true)
    }

    /// 2 · Connect Health: the system sheet only appears after tapping Connect.
    private var connectHealth: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(Lab.watch)
                .shadow(color: Lab.watch.opacity(0.7), radius: 16)
                .accessibilityHidden(true)
            Text(String(localized: "Connect Health")).font(Lab.display(32)).foregroundStyle(Lab.text)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "Pulse Lab reads your Watch's heart, sleep and activity data, and what WHOOP saves to Health. It only writes the supplements you check off. Tap Turn On All on the next screen so nothing is missing."))
                .font(Lab.body(15)).foregroundStyle(Lab.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 12)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                Task {
                    await store.connectHealth()
                    healthDone = true
                    go(2)
                }
            } label: { primary(healthDone ? String(localized: "Connected") : String(localized: "Connect Health")) }
            Button(String(localized: "Not now")) { go(2) }
                .font(Lab.body(15, .semibold)).foregroundStyle(Lab.dim)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    /// 3 · WHOOP and the Stack, plus the morning notification (permission asked only if switched on).
    private var whoopAndStack: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bolt.heart.fill").font(.system(size: 52)).foregroundStyle(Lab.whoop)
                    .shadow(color: Lab.whoop.opacity(0.7), radius: 16).padding(.top, 32)
                    .accessibilityHidden(true)
                Text(String(localized: "WHOOP & your Stack")).font(Lab.display(30)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "Connect WHOOP for recovery, strain and sleep, or type the numbers in each morning in about 20 seconds. Check off supplements in the Stack tab so Insights can compare."))
                    .font(Lab.body(15)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                LabPanel(tint: Lab.whoop) { WhoopConnectView(accent: Lab.whoop) }
                LabPanel(tint: Lab.good) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(String(localized: "Morning briefing notification"), isOn: $briefing).tint(Lab.good)
                            .font(Lab.body(15, .semibold)).foregroundStyle(Lab.text)
                            .onChange(of: briefing) { _, on in
                                Task {
                                    if on {
                                        let ok = await MorningBriefing.enable(loggedToday: store.hasWhoopRecoveryToday)
                                        if !ok { briefing = false; notifyDenied = true }
                                    } else {
                                        MorningBriefing.enabled = false
                                    }
                                }
                            }
                        Text(notifyDenied
                             ? String(localized: "Notifications are off for Pulse Lab. You can turn them on later in the Settings app.")
                             : String(localized: "8 am by default. It asks you to log WHOOP when today's numbers are missing. Change it any time in Settings."))
                            .font(Lab.body(12, .regular)).foregroundStyle(notifyDenied ? Lab.warn : Lab.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { done() } label: { primary(String(localized: "Enter the lab")) }
                Button(String(localized: "Skip WHOOP for now")) { done() }
                    .font(Lab.body(15, .semibold)).foregroundStyle(Lab.dim)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule().fill(i == page ? AnyShapeStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.15)))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: page)
    }

    private func primary(_ t: String) -> some View {
        Text(t).font(Lab.display(17, .heavy)).foregroundStyle(Lab.bg)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Capsule().fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: Lab.watch.opacity(0.4), radius: 14)
    }
}
