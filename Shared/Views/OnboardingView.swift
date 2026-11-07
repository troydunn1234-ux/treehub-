import SwiftUI
import UIKit

// MARK: - First-run flags

enum FirstRun {
    private static let key: String = "hasOnboarded"

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// True for demo / simulator test runs launched with `-demo`.
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
}

// MARK: - Model

private enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome, features, location, health
}

private enum HealthLinkState: Equatable {
    case idle, requesting, connected, unavailable
}

private struct OnboardingFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
}

// MARK: - Onboarding

/// First-run walkthrough: welcome, features, location, Apple Health.
/// Nothing is required; "Skip" / "Let's go" both mark onboarding done and call `onDone`.
@MainActor
struct OnboardingView: View {
    var onDone: () -> Void

    @Environment(RouteTracker.self) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var step: OnboardingStep = .welcome
    @State private var appeared: Bool = false
    @State private var health: HealthLinkState = .idle
    @State private var emblemDraw: CGFloat = 0
    @State private var emblemLeaves: CGFloat = 0
    @State private var emblemPulse: Bool = false
    @State private var finished: Bool = false

    var body: some View {
        ZStack {
            ForestBackground()
            VStack(spacing: 0) {
                topBar
                pager
                bottomBar
            }
        }
        .onAppear { start() }
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: tracker.canTrack) { (old: Bool, new: Bool) -> Bool in
            !old && new
        }
        .sensoryFeedback(.success, trigger: health) { (_: HealthLinkState, new: HealthLinkState) -> Bool in
            new == .connected
        }
        .accessibilityIdentifier("onboarding")
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Text(AppInfo.name.uppercased())
                .font(Theme.rounded(12, .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.textDim)
            Spacer()
            if step != .health {
                Button {
                    finish()
                } label: {
                    Text("Skip")
                        .font(Theme.rounded(15, .semibold))
                        .foregroundStyle(Theme.textDim)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityIdentifier("onboarding-skip")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var pager: some View {
        TabView(selection: $step) {
            welcomePage.tag(OnboardingStep.welcome)
            featuresPage.tag(OnboardingStep.features)
            locationPage.tag(OnboardingStep.location)
            healthPage.tag(OnboardingStep.health)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var bottomBar: some View {
        VStack(spacing: 22) {
            pageDots
            Button {
                advance()
            } label: {
                HStack(spacing: 8) {
                    Text(step == .health ? "Let's go" : "Continue")
                    Image(systemName: step == .health ? "checkmark" : "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(step == .health ? "onboarding-done" : "onboarding-continue")
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { (s: OnboardingStep) in
                Capsule()
                    .fill(s == step ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.22)))
                    .frame(width: s == step ? 28 : 8, height: 8)
                    .shadow(color: s == step ? Theme.glow.opacity(0.5) : Color.clear, radius: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPageLayout(active: isActive(.welcome), headline: Copy.welcomeHeadline, message: Copy.welcomeMessage) {
            BrandEmblem(appear: appeared, progress: emblemDraw, leafT: emblemLeaves, pulse: emblemPulse)
                .frame(width: 210, height: 210)
        } extra: {
            EmptyView()
        }
    }

    private var featuresPage: some View {
        OnboardingPageLayout(active: isActive(.features), headline: Copy.featuresHeadline,
                             message: Copy.featuresMessage, staggerExtra: true) {
            featuresHero
        } extra: {
            featureList
        }
    }

    private var locationPage: some View {
        OnboardingPageLayout(active: isActive(.location), headline: Copy.locationHeadline, message: Copy.locationMessage) {
            locationHero
        } extra: {
            locationAction
        }
    }

    private var healthPage: some View {
        OnboardingPageLayout(active: isActive(.health), headline: Copy.healthHeadline, message: Copy.healthMessage) {
            healthHero
        } extra: {
            VStack(alignment: .leading, spacing: 16) {
                healthFlow
                healthAction
            }
        }
    }

    // MARK: Features

    private var features: [OnboardingFeature] {
        #if TRACK_APP
        return [
            OnboardingFeature(id: "track", symbol: "figure.run", title: "Track any move",
                              detail: "Walk, run, hike, ride or drive, mapped live by GPS.", tint: Theme.leaf),
            OnboardingFeature(id: "stats", symbol: "chart.bar.xaxis", title: "Stats & records",
                              detail: "History, totals and personal records to chase.", tint: Theme.sky),
            OnboardingFeature(id: "garmin", symbol: "applewatch", title: "Garmin workouts",
                              detail: "Pulled in automatically through Apple Health.", tint: Theme.gold),
        ]
        #else
        return [
            OnboardingFeature(id: "hug", symbol: "tree.fill", title: "Hug & log trees",
                              detail: "Snap the tree and a selfie, then pin it on the map.", tint: Theme.leaf),
            OnboardingFeature(id: "breathe", symbol: "wind", title: "Breathe with your Garmin",
                              detail: "Heart rate and breathing from Apple Health.", tint: Theme.sky),
            OnboardingFeature(id: "grow", symbol: "leaf.fill", title: "Grow your grove",
                              detail: "Earn XP, badges and collectible leaves.", tint: Theme.gold),
        ]
        #endif
    }

    private var featuresHero: some View {
        HStack(spacing: -14) {
            ForEach(features) { (f: OnboardingFeature) in
                Image(systemName: f.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 68, height: 68)
                    .background(f.tint, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.forestDeep, lineWidth: 3))
                    .shadow(color: f.tint.opacity(0.45), radius: 12)
            }
        }
        .accessibilityHidden(true)
    }

    private var featureList: some View {
        let items: [OnboardingFeature] = features
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                featureRow(pair.element)
                    .modifier(Reveal(active: isActive(.features), delay: 0.22 + Double(pair.offset) * 0.08, reduceMotion: reduceMotion))
            }
        }
    }

    private func featureRow(_ f: OnboardingFeature) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: f.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(f.tint)
                .frame(width: 50, height: 50)
                .background(f.tint.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(f.tint.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title)
                    .font(Theme.rounded(17, .bold))
                    .foregroundStyle(.white)
                Text(f.detail)
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Location

    private var locationHero: some View {
        ZStack {
            Circle()
                .fill(Theme.leaf.opacity(0.10))
                .frame(width: 180, height: 180)
                .scaleEffect(emblemPulse && !reduceMotion ? 1.06 : 0.96)
            Circle()
                .strokeBorder(Theme.leaf.opacity(0.28), lineWidth: 1)
                .frame(width: 136, height: 136)
            Circle()
                .fill(Theme.leafGradient)
                .frame(width: 92, height: 92)
                .shadow(color: Theme.glow.opacity(0.5), radius: 18)
            Image(systemName: tracker.canTrack ? "checkmark" : "location.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.forestDeep)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: tracker.canTrack)
        .accessibilityHidden(true)
    }

    private var locationAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tracker.canTrack {
                grantedBadge("Location is on")
            } else if tracker.denied {
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                }
                .buttonStyle(OnboardingGlassButtonStyle())
                .accessibilityIdentifier("onboarding-location-settings")
                Text("Location is off for \(AppInfo.name). You can turn it on anytime in Settings.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    tracker.requestPermission()
                } label: {
                    Label("Allow location", systemImage: "location.fill")
                }
                .buttonStyle(OnboardingGlassButtonStyle())
                .accessibilityIdentifier("onboarding-allow-location")
                Text("Not now? Tap Continue. You can allow it later.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: tracker.canTrack)
    }

    // MARK: Health

    private var healthHero: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.10))
                .frame(width: 180, height: 180)
            Circle()
                .strokeBorder(Color.pink.opacity(0.28), lineWidth: 1)
                .frame(width: 136, height: 136)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.45, blue: 0.55), Color(red: 0.92, green: 0.20, blue: 0.36)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92)
                .shadow(color: Color.pink.opacity(0.45), radius: 18)
            Image(systemName: "heart.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: !reduceMotion && isActive(.health))
            Image(systemName: "applewatch")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.forestDeep)
                .frame(width: 42, height: 42)
                .background(Theme.leafGradient, in: Circle())
                .overlay(Circle().strokeBorder(Theme.forestDeep, lineWidth: 3))
                .offset(x: 44, y: 38)
        }
        .accessibilityHidden(true)
    }

    private var healthFlow: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 6) {
                flowNode("Garmin Connect", symbol: "applewatch", tint: Theme.sky)
                flowArrow
                flowNode("Apple Health", symbol: "heart.fill", tint: Color.pink)
                flowArrow
                flowNode(AppInfo.name, symbol: Copy.appSymbol, tint: Theme.glow)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Garmin Connect → Apple Health → \(AppInfo.name)")
    }

    private func flowNode(_ title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.3), lineWidth: 1))
            Text(title)
                .font(Theme.rounded(12, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.textDim)
            .frame(height: 46)
    }

    @ViewBuilder
    private var healthAction: some View {
        switch health {
        case .connected:
            grantedBadge("Apple Health connected")
        case .unavailable:
            Text("Apple Health isn't available on this device. You can connect it later in Settings.")
                .font(Theme.rounded(13, .medium))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .requesting:
            Button {
                connectHealth()
            } label: {
                HStack(spacing: 8) {
                    if health == .requesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "heart.fill").foregroundStyle(Color.pink)
                    }
                    Text("Connect Apple Health")
                }
            }
            .buttonStyle(OnboardingGlassButtonStyle())
            .disabled(health == .requesting)
            .accessibilityIdentifier("onboarding-connect-health")
        }
    }

    // MARK: Shared bits

    private func grantedBadge(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.leafGradient)
            Text(text)
                .font(Theme.rounded(17, .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Theme.leaf.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.leaf.opacity(0.35), lineWidth: 1))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private func isActive(_ s: OnboardingStep) -> Bool {
        appeared && step == s
    }

    // MARK: Actions

    private func start() {
        guard !appeared else { return }
        appeared = true
        if reduceMotion {
            emblemDraw = 1
            return
        }
        withAnimation(.easeInOut(duration: 1.0).delay(0.15)) { emblemDraw = 1 }
        withAnimation(.easeOut(duration: 1.4).delay(0.2)) { emblemLeaves = 1 }
        withAnimation(BrandEmblem.pulseAnimation) { emblemPulse = true }
    }

    private func advance() {
        guard let next: OnboardingStep = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        FirstRun.hasOnboarded = true
        onDone()
    }

    private func connectHealth() {
        guard HealthService.shared.isAvailable else {
            withAnimation(.easeOut(duration: 0.2)) { health = .unavailable }
            return
        }
        health = .requesting
        Task { @MainActor in
            let ok: Bool = await HealthService.shared.requestAccess()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                health = ok ? .connected : .idle
            }
        }
    }

    private func openSettings() {
        if let url: URL = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

// MARK: - Copy

private enum Copy {
    #if TRACK_APP
    static let appSymbol: String = "location.north.line.fill"
    static let welcomeHeadline: String = "Go anywhere.\nKeep every mile."
    static let welcomeMessage: String = "Roamr records your walks, runs, hikes, rides and drives, with clean stats and records to chase."
    static let featuresHeadline: String = "Built for every\nkind of move."
    static let featuresMessage: String = "One tap to start. The rest is automatic."
    static let locationHeadline: String = "Tracks with your\nphone locked."
    static let locationMessage: String = "Roamr uses GPS to draw your route as you go, and keeps recording with your phone in your pocket."
    static let healthHeadline: String = "Bring your\nGarmin along."
    static let healthMessage: String = "Garmin and Whoop sync workouts and heart rate into Apple Health. Roamr reads them so your Garmin workouts land in your history."
    #else
    static let appSymbol: String = "tree.fill"
    static let welcomeHeadline: String = "Grow a grove,\none hug at a time."
    static let welcomeMessage: String = "Rootbound turns time with trees into a game: log hugs, breathe slow, and watch your forest grow."
    static let featuresHeadline: String = "A little game\nfor big trees."
    static let featuresMessage: String = "Everything you need to make time outside count."
    static let locationHeadline: String = "Pin every tree,\ntrace every stroll."
    static let locationMessage: String = "Rootbound uses GPS to pin the trees you hug and draw your strolls and hikes, even with your phone locked."
    static let healthHeadline: String = "Bring your\nGarmin along."
    static let healthMessage: String = "Garmin and Whoop sync heart rate, breathing and mindful minutes into Apple Health. Rootbound reads them to show your breathwork with every hug."
    #endif
}

// MARK: - Page layout

private struct OnboardingPageLayout<Hero: View, Extra: View>: View {
    let active: Bool
    let headline: String
    let message: String
    let staggerExtra: Bool
    let hero: Hero
    let extra: Extra

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(active: Bool, headline: String, message: String, staggerExtra: Bool = false,
         @ViewBuilder hero: () -> Hero, @ViewBuilder extra: () -> Extra) {
        self.active = active
        self.headline = headline
        self.message = message
        self.staggerExtra = staggerExtra
        self.hero = hero()
        self.extra = extra()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            heroBlock
            Spacer(minLength: 20)
            textBlock
            extraBlock
            Spacer(minLength: 12)
        }
        .padding(.horizontal, Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var heroBlock: some View {
        hero
            .frame(maxWidth: .infinity)
            .scaleEffect(active || reduceMotion ? 1 : 0.9)
            .modifier(Reveal(active: active, delay: 0, reduceMotion: reduceMotion))
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(Theme.title(34))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Reveal(active: active, delay: 0.08, reduceMotion: reduceMotion))
            Text(message)
                .font(Theme.rounded(17, .medium))
                .foregroundStyle(Theme.textDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Reveal(active: active, delay: 0.14, reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var extraBlock: some View {
        if staggerExtra {
            extra
                .padding(.top, 28)
        } else {
            extra
                .padding(.top, 28)
                .modifier(Reveal(active: active, delay: 0.22, reduceMotion: reduceMotion))
        }
    }
}

/// Fades + slides content in when its page becomes active.
private struct Reveal: ViewModifier {
    let active: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: active || reduceMotion ? 0 : 26)
            .animation(animation, value: active)
    }

    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        return .spring(response: 0.55, dampingFraction: 0.82).delay(active ? delay : 0)
    }
}

/// Glassy full-width secondary button for permission prompts.
private struct OnboardingGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(17, .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.09),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
