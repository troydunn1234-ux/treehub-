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
                    .buttonStyle(LabPrimaryButton())
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
                pulseArt.padding(.top, 28)
                Text(String(localized: "Watch vs WHOOP.\nHead to head."))
                    .font(Lab.display(36)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "Wear both? Pulse Lab puts their readings side by side and shows where they agree and where they split."))
                    .font(Lab.body(15)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                samplePreview
                VStack(alignment: .leading, spacing: 14) {
                    feature("checkmark.circle.fill", String(localized: "Agree or split"),
                            String(localized: "Resting HR, HRV, sleep and strain from both trackers, each marked, with one agreement score for the day."))
                    feature("scope", String(localized: "Who to trust"),
                            String(localized: "Day-by-day agreement over weeks: which one reads higher, by how much, and why they differ."))
                    feature("gauge.with.dots.needle.67percent", String(localized: "Readiness next to recovery"),
                            String(localized: "A readiness score built from your Watch, next to WHOOP recovery, with every part explained."))
                    feature("sun.max.fill", String(localized: "And the rest of your day"),
                            String(localized: "Sleep stages, heart, moves, a morning briefing and your supplement stack."))
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    /// A labelled sample of the Today card, so the very first screen shows what the comparison looks like.
    private var samplePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Example")).font(.caption.weight(.bold)).foregroundStyle(Lab.faint)
                Spacer()
                Text(String(localized: "3 of 4 agree")).font(.caption.weight(.bold)).foregroundStyle(Lab.good)
            }
            sampleRow(String(localized: "Resting HR"), "52", "54", agree: true)
            sampleRow(String(localized: "HRV"), String(localized: "Up 9%"), String(localized: "Down 4%"), agree: false)
            sampleRow(String(localized: "Sleep"), "7h 12m", "6h 58m", agree: true)
        }
        .padding(Lab.S.sm)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.panel))
        .overlay(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).strokeBorder(Lab.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Example: resting heart rate and sleep agree, HRV splits. 3 of 4 agree."))
    }

    private func sampleRow(_ title: String, _ watch: String, _ whoop: String, agree: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(watch).font(Lab.number(15)).foregroundStyle(Lab.watch)
            Text("vs").font(.caption2).foregroundStyle(Lab.faint)
            Text(whoop).font(Lab.number(15)).foregroundStyle(Lab.whoop)
            Image(systemName: agree ? "checkmark.circle.fill" : "arrow.left.arrow.right.circle.fill")
                .foregroundStyle(agree ? Lab.good : Lab.warn)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(Lab.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Lab.accent.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Lab.text)
                Text(text).font(.subheadline).foregroundStyle(Lab.dim).fixedSize(horizontal: false, vertical: true)
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
                var path = Path()
                let mid = size.height / 2 + CGFloat(i) * 10 - 5
                for x in stride(from: 0, through: size.width, by: 2) {
                    let t = (x / size.width + phase + CGFloat(i) * 0.08).truncatingRemainder(dividingBy: 1)
                    var y = mid + sin(x / 18 + CGFloat(i)) * 3
                    if t > 0.42 && t < 0.5 { y = mid - sin((t - 0.42) / 0.08 * .pi) * (size.height * 0.42) * (i == 0 ? 1 : 0.8) }
                    if t > 0.5 && t < 0.55 { y = mid + sin((t - 0.5) / 0.05 * .pi) * size.height * 0.18 }
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
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
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(Lab.accent)
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
            .buttonStyle(LabPrimaryButton())
            .sensoryFeedback(.success, trigger: healthDone)
            Button(String(localized: "Not now")) { go(2) }
                .font(Lab.body(15, .semibold)).foregroundStyle(Lab.dim)
                .frame(minHeight: 44)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    /// 3 · WHOOP and the Stack, plus the morning notification (permission asked only if switched on).
    private var whoopAndStack: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bolt.heart.fill").font(.system(size: 52)).foregroundStyle(Lab.whoop)
                    .padding(.top, 32)
                    .accessibilityHidden(true)
                Text(String(localized: "WHOOP & your Stack")).font(Lab.display(30)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "Connect WHOOP for recovery, strain and sleep, or type the numbers in each morning in about 20 seconds. Check off supplements in the Stack tab so Insights can compare."))
                    .font(Lab.body(15)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                LabPanel(tint: Lab.whoop) { WhoopConnectView(accent: Lab.whoop) }
                LabPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(String(localized: "Morning briefing notification"), isOn: $briefing).tint(Lab.accent)
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
                    .buttonStyle(LabPrimaryButton())
                Button(String(localized: "Skip WHOOP for now")) { done() }
                    .font(Lab.body(15, .semibold)).foregroundStyle(Lab.dim)
                    .frame(minHeight: 44)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule().fill(i == page ? Lab.accent : Color.white.opacity(0.18))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: page)
    }

    private func primary(_ t: String) -> some View {
        Text(t)
    }
}
