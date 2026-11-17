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
    case welcome, features, permissions
}

private struct OnboardingFeature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
}

// MARK: - Onboarding

/// First-run walkthrough (3 pages): welcome, features, then what the app will ask for and when.
/// Nothing is asked up front: location and Apple Health come up in context, the first time a feature
/// needs them (Rootbound: logging a hug pins the tree and fills in heart data; Roamr: recording, importing workouts).
/// "Skip" / "Let's go" both mark onboarding done and call `onDone`.
@MainActor
struct OnboardingView: View {
    var onDone: () -> Void

    @Environment(RouteTracker.self) private var tracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var appeared: Bool = false
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
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Text(AppInfo.name.uppercased())
                .font(Theme.rounded(12, .heavy))
                .tracking(2.5)
                .foregroundStyle(Theme.textDim)
                .accessibilityHidden(true)
            Spacer()
            if step != .permissions {
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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityIdentifier("onboarding-skip")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
    }

    private var pager: some View {
        TabView(selection: $step) {
            welcomePage.tag(OnboardingStep.welcome)
            featuresPage.tag(OnboardingStep.features)
            permissionsPage.tag(OnboardingStep.permissions)
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
                    Text(step == .permissions ? "Let's go" : "Continue")
                    Image(systemName: step == .permissions ? "checkmark" : "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(step == .permissions ? "onboarding-done" : "onboarding-continue")
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
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.72), value: step)
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

    /// What the app will ask for, and when. No prompts here: each permission is asked in context.
    private var permissionsPage: some View {
        OnboardingPageLayout(active: isActive(.permissions), headline: Copy.permissionsHeadline, message: Copy.permissionsMessage) {
            permissionsHero
        } extra: {
            VStack(alignment: .leading, spacing: 18) {
                permissionRow(symbol: "location.fill", tint: Theme.sky, title: "Location",
                              detail: Copy.locationWhen, isOn: tracker.canTrack)
                permissionRow(symbol: "heart.fill", tint: Color.pink, title: "Apple Health",
                              detail: Copy.healthWhen, isOn: false)
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
            OnboardingFeature(id: "garmin", symbol: "applewatch", title: "Watch workouts",
                              detail: "Pulled in automatically through Apple Health.", tint: Theme.gold),
        ]
        #else
        return [
            OnboardingFeature(id: "hug", symbol: "tree.fill", title: "Hug & log trees",
                              detail: "Snap the tree, pin it on the map, note how you feel.", tint: Theme.leaf),
            OnboardingFeature(id: "breathe", symbol: "applewatch", title: "Hug with your Apple Watch",
                              detail: "Live heart rate during the hug, plus your breath sessions.", tint: Theme.sky),
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(f.detail)
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Permissions (information only)

    private var permissionsHero: some View {
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
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.forestDeep)
            heroBadge("location.fill", tint: Theme.sky).offset(x: -50, y: -42)
            heroBadge("heart.fill", tint: Color.pink).offset(x: 50, y: 40)
        }
        .accessibilityHidden(true)
    }

    private func heroBadge(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Theme.forestDeep, lineWidth: 3))
    }

    /// One permission: what it is, when the app asks, and "On" once it's already allowed.
    private func permissionRow(symbol: String, tint: Color, title: String, detail: String, isOn: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.rounded(17, .bold))
                        .foregroundStyle(.white)
                    if isOn {
                        Label("On", systemImage: "checkmark.circle.fill")
                            .font(Theme.rounded(13, .bold))
                            .foregroundStyle(Theme.glow)
                    }
                }
                Text(detail)
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
        if reduceMotion { step = next } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next } }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        FirstRun.hasOnboarded = true
        onDone()
    }
}

// MARK: - Copy

private enum Copy {
    #if TRACK_APP
    static let welcomeHeadline: String = "Go anywhere.\nKeep every mile."
    static let welcomeMessage: String = "Roamr records your walks, runs, hikes, rides and drives, with clean stats and records to chase."
    static let featuresHeadline: String = "Built for every\nkind of move."
    static let featuresMessage: String = "One tap to start. The rest is automatic."
    static let permissionsHeadline: String = "Only when\nyou need it."
    static let permissionsMessage: String = "Nothing is asked now. Each permission comes up the first time a feature needs it, and you can change your mind anytime in Settings."
    static let locationWhen: String = "When you start recording, to draw your route as you go."
    static let healthWhen: String = "When you bring in workouts and heart rate from your watch."
    #else
    static let welcomeHeadline: String = "Grow a grove,\none hug at a time."
    static let welcomeMessage: String = "Rootbound turns time with trees into a game: log hugs, breathe slow, and watch your forest grow."
    static let featuresHeadline: String = "A little game\nfor big trees."
    static let featuresMessage: String = "Everything you need to make time outside count."
    static let permissionsHeadline: String = "Only when\nyou need it."
    static let permissionsMessage: String = "Nothing is asked now. Each permission comes up the first time a feature needs it, and you can change your mind anytime in Settings."
    static let locationWhen: String = "When you log your first hug, to pin the tree on your map so you can find your way back."
    static let healthWhen: String = "When you log your first hug, to fill in heart rate and breath sessions from your Apple Watch."
    #endif
}

// MARK: - Page layout

/// Hero, headline, message and extra content. Centered with breathing room when it fits the screen;
/// scrolls instead of overlapping the top and bottom bars at large text sizes or on small phones.
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
        ViewThatFits(in: .vertical) {
            column(fillsHeight: true)
            ScrollView(showsIndicators: false) {
                column(fillsHeight: false)
            }
        }
    }

    private func column(fillsHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 8)
            heroBlock
            Spacer(minLength: 20)
            textBlock
            extraBlock
            Spacer(minLength: 12)
        }
        .padding(.horizontal, Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .leading)
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
                .accessibilityAddTraits(.isHeader)
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
