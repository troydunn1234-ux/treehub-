import SwiftUI
import CoreLocation

/// Roamr's first-run intro: three screens (every mile mapped, trips and fuel, auto-detect and privacy).
/// Permissions are asked in context: location on the Record screen when you tap Allow, drive
/// auto-detect (Always location, motion, notifications) on the privacy screen only if you opt in.
/// Contacts/notifications for the hard-stop alert are asked in Settings when you turn it on.
enum RoamrIntro {
    static let pendingKey = "roamr.intro.pending"

    /// Call once at launch, before LaunchGate reads FirstRun: Roamr shows this intro instead of
    /// the shared onboarding.
    static func prepare() {
        if !FirstRun.hasOnboarded {
            UserDefaults.standard.set(true, forKey: pendingKey)
            // The intro asks for auto-detect itself, so the automatic first-launch prompt is skipped.
            UserDefaults.standard.set(true, forKey: DriveDetector.permsAskedKey)
            FirstRun.hasOnboarded = true
        }
    }

    static var shouldShow: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-roamrIntro") { return true }
        return UserDefaults.standard.bool(forKey: pendingKey) && !FirstRun.isDemo
    }

    static func markDone() { UserDefaults.standard.set(false, forKey: pendingKey) }
}

/// Shows the intro over the app until it's done.
struct RoamrIntroGate<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var show = RoamrIntro.shouldShow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
            if show {
                RoamrIntroView {
                    RoamrIntro.markDone()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { show = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

struct RoamrIntroView: View {
    var onDone: () -> Void

    @Environment(RouteTracker.self) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var autoDetectAsked = false

    private let pages = 3

    var body: some View {
        ZStack {
            ForestBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("ROAMR").font(Theme.rounded(12, .heavy)).tracking(2).foregroundStyle(Theme.textDim)
                        .accessibilityHidden(true)
                    Spacer()
                    Button("Skip") { onDone() }
                        .font(Theme.rounded(15, .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    recordPage.tag(0)
                    togetherPage.tag(1)
                    privacyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut, value: page)

                dots.padding(.bottom, 16)

                Button {
                    if page < pages - 1 {
                        withAnimation(reduceMotion ? nil : .easeInOut) { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < pages - 1 ? LocalizedStringKey("Next") : LocalizedStringKey("Let's go"))
                        .font(Theme.rounded(17, .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.leafGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages, id: \.self) { i in
                Capsule().fill(i == page ? Theme.glow : Color.white.opacity(0.25))
                    .frame(width: i == page ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(page + 1) of \(pages)"))
    }

    // MARK: Pages

    /// 1 · The signature: every mile mapped (drives noticed on their own, everything else one tap).
    private var recordPage: some View {
        IntroPage(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", tint: Theme.glow,
                  title: "Every mile, mapped",
                  text: "Drives, rides, hikes, runs and walks, each saved with its route, speed, time and distance. Roamr notices when a drive starts, records it with one tap and finishes it when you park.") {
            VStack(spacing: 14) {
                kindStrip
                if tracker.canTrack {
                    Label("Location is on", systemImage: "checkmark.circle.fill")
                        .font(Theme.rounded(15, .bold)).foregroundStyle(Theme.glow)
                } else if tracker.denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { pill("Open Settings to allow location") }
                    .buttonStyle(.plain)
                } else {
                    Button { tracker.requestPermission() } label: { pill("Allow location while recording") }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Shows the iPhone location permission prompt"))
                }
            }
        }
    }

    /// Drive · Walk · Ride · Hike · Run, as small glowing chips.
    private var kindStrip: some View {
        let kinds: [(String, LocalizedStringKey)] = [("car.fill", "Drive"), ("figure.walk", "Walk"), ("bicycle", "Ride"),
                                                     ("figure.hiking", "Hike"), ("figure.run", "Run")]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(kinds.indices, id: \.self) { i in kindChip(kinds[i].0, kinds[i].1) } }
            VStack(spacing: 8) {
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { i in kindChip(kinds[i].0, kinds[i].1) } }
                HStack(spacing: 8) { ForEach(3..<5, id: \.self) { i in kindChip(kinds[i].0, kinds[i].1) } }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func kindChip(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.rounded(12, .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.glow.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(Theme.glow.opacity(0.35), lineWidth: 1))
    }

    /// 2 · What you get from those miles: the night-map history and the fuel log per vehicle.
    private var togetherPage: some View {
        IntroPage(symbol: "fuelpump.fill", tint: Theme.gold,
                  title: "Your trips, your fuel",
                  text: "Every trip lands in a night-map history, grouped by week with its route. Log a fill-up and Roamr works out MPG for each vehicle from the drives it mapped.") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("moon.stars.fill", "Night-map trip history with weekly totals")
                bullet("gauge.with.dots.needle.67percent", "MPG and monthly fuel spend per vehicle")
                bullet("person.2.fill", "Go Together: friends live on one map")
            }
            .padding(.horizontal, 4)
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.rounded(14, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// 3 · Auto-detect (opt-in) and how location is kept private.
    private var privacyPage: some View {
        IntroPage(symbol: "lock.shield.fill", tint: Theme.sky,
                  title: "Catch every drive, privately",
                  text: "Auto-detect listens with low-power motion signals and takes a few seconds of GPS only when you seem to be driving. GPS runs only while you record. Trips stay on your iPhone and in your private iCloud. Nothing is sold or used for ads.") {
            VStack(spacing: 10) {
                if autoDetectAsked {
                    Label("Auto-detect is set up", systemImage: "checkmark.circle.fill")
                        .font(Theme.rounded(15, .bold)).foregroundStyle(Theme.glow)
                } else {
                    Button {
                        autoDetectAsked = true
                        Task { await DriveDetector.shared.enable() }
                    } label: { pill("Notice my drives automatically") }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Asks for Always location, motion and notifications"))
                    Text("Optional. You can change it any time in Settings.")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func pill(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.rounded(15, .heavy))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.glow.opacity(0.6), lineWidth: 1.2))
            .contentShape(Capsule())
    }
}

private struct IntroPage<Extra: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var extra: Extra
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: shown)
                    .frame(width: 130, height: 130)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                    .padding(.top, 30)
                    .onAppear { if !reduceMotion { shown.toggle() } }
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                extra
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
