import SwiftUI

/// Three swipes on first launch: what the app does, what it needs, what's free vs Pro.
struct OnboardingSpec {
    struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let text: String
    }
    var appName: String
    var tint: Color
    var tint2: Color
    var pages: [Page]
    var freeLine: String
    var proLine: String
    /// Bump when the onboarding changes enough to show again.
    var version: Int = 1
}

extension View {
    /// Shows the onboarding once per `spec.version`.
    func onboarding(_ spec: OnboardingSpec) -> some View { modifier(OnboardingHost(spec: spec)) }
}

private struct OnboardingHost: ViewModifier {
    let spec: OnboardingSpec
    @State private var show = false
    private var key: String { "onboarding.seen.v\(spec.version)" }
    func body(content: Content) -> some View {
        content
            .onAppear { if !UserDefaults.standard.bool(forKey: key) { show = true } }
            .fullScreenCover(isPresented: $show) {
                OnboardingView(spec: spec) {
                    UserDefaults.standard.set(true, forKey: key)
                    show = false
                }
            }
    }
}

struct OnboardingView: View {
    let spec: OnboardingSpec
    let done: () -> Void
    @State private var page = 0
    @ObservedObject private var unlock = Unlock.shared

    private var last: Int { spec.pages.count }   // the "free vs Pro" page sits after the spec pages

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            RadialGradient(colors: [spec.tint.opacity(0.5), .clear], center: .init(x: 0.15, y: 0.1), startRadius: 10, endRadius: 420).ignoresSafeArea()
            RadialGradient(colors: [spec.tint2.opacity(0.3), .clear], center: .init(x: 0.9, y: 0.5), startRadius: 10, endRadius: 360).ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(spec.pages.enumerated()), id: \.element.id) { i, p in
                        pageView(icon: p.icon, title: p.title, text: p.text).tag(i)
                    }
                    proPage.tag(last)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) {
                    ForEach(0...last, id: \.self) { i in
                        Capsule().fill(i == page ? spec.tint : .white.opacity(0.18))
                            .frame(width: i == page ? 22 : 7, height: 7)
                            .animation(.snappy, value: page)
                    }
                }
                .padding(.bottom, 18)
                Button {
                    if page < last { withAnimation(.snappy) { page += 1 } } else { done() }
                } label: {
                    Text(page < last ? "Next" : "Let's go")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.88))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Capsule().fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .leading, endPoint: .trailing)))
                        .shadow(color: spec.tint.opacity(0.4), radius: 16, y: 8)
                }
                .padding(.horizontal, 24)
                Button("Skip") { done() }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 12).padding(.bottom, 24)
                    .opacity(page < last ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pageView(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 8)
            Text(title).font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(text).font(.system(size: 17, design: .rounded)).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    private var proPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 8)
            Text("Free to use.\nOne unlock for everything.").font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            row("checkmark.circle.fill", spec.freeLine)
            row("sparkles", unlock.isPro ? "You already have \(spec.appName) Pro — thank you." : spec.proLine + (unlock.priceText.isEmpty ? "" : " \(unlock.priceText), once. No subscription."))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .task { await unlock.load() }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(spec.tint).font(.system(size: 18, weight: .semibold)).padding(.top, 1)
            Text(text).font(.system(size: 16, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
