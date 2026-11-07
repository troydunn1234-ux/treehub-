import SwiftUI

/// Shows the launch animation, then onboarding on first run, then the app.
struct LaunchGate<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(RouteTracker.self) private var tracker

    private static var forceIntro: Bool { ProcessInfo.processInfo.arguments.contains("-showIntro") }

    @State private var showSplash = !FirstRun.isDemo || LaunchGate.forceIntro
    @State private var needsOnboarding = (!FirstRun.hasOnboarded && !FirstRun.isDemo) || LaunchGate.forceIntro

    var body: some View {
        ZStack {
            if !needsOnboarding {
                content
                    .transition(.opacity)
            } else if !showSplash {
                OnboardingView(onDone: {
                    withAnimation(.easeInOut(duration: 0.5)) { needsOnboarding = false }
                })
                .environment(tracker)
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
            if showSplash {
                LaunchSplash(onFinished: {
                    withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
