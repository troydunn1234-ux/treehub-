import SwiftUI
import CoreLocation

/// Roamr's first-run intro: three screens (record, Go Together, location privacy).
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

    private var recordPage: some View {
        IntroPage(symbol: "location.north.circle.fill", tint: Theme.glow,
                  title: "Record every trip",
                  text: "Walks, runs, hikes, rides and drives. Tap Start, put your phone away, and Roamr maps the route, speed, time and distance.") {
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

    private var togetherPage: some View {
        IntroPage(symbol: "person.2.fill", tint: Theme.sky,
                  title: "Go Together",
                  text: "Start a group trip and send friends a link. Everyone sees each other on one live map, with speeds and who's ahead or behind.") {
            Text("Only people with your trip code can see you, and only until the trip ends.")
                .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
    }

    private var privacyPage: some View {
        IntroPage(symbol: "lock.shield.fill", tint: Theme.gold,
                  title: "Your location stays yours",
                  text: "Roamr uses GPS only while you record. Auto-detect listens with low-power motion signals and takes a few seconds of GPS only when you seem to be driving. Trips are saved on your iPhone and your private iCloud. Nothing is sold or used for ads.") {
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
