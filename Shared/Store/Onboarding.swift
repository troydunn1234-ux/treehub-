import SwiftUI

/// Up to three swipes on first launch: what the app does and what it needs; the last page also says what's free vs Pro.
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
    /// What Pro adds. May end with "for": the price from the App Store is added after it ("… for $4.99, once.").
    var proLine: String
    /// Bump when the onboarding changes enough to show again.
    var version: Int = 1
}

extension View {
    /// Shows the onboarding once per `spec.version`.
    func onboarding(_ spec: OnboardingSpec) -> some View { modifier(ProOnboardingHost(spec: spec)) }
}

private struct ProOnboardingHost: ViewModifier {
    let spec: OnboardingSpec
    @State private var show = false
    private var key: String { "onboarding.seen.v\(spec.version)" }
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Screenshots ("-demo" or "-noOnboarding") skip it unless "-onboarding" asks for it.
                let args = ProcessInfo.processInfo.arguments
                let skip = args.contains("-demo") || args.contains("-noOnboarding")
                if args.contains("-onboarding") || (!skip && !UserDefaults.standard.bool(forKey: key)) { show = true }
            }
            .fullScreenCover(isPresented: $show) {
                ProOnboardingView(spec: spec) {
                    UserDefaults.standard.set(true, forKey: key)
                    show = false
                }
            }
    }
}

struct ProOnboardingView: View {
    let spec: OnboardingSpec
    let done: () -> Void
    @State private var page = 0
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Index of the last page. The "free vs Pro" lines sit under the last spec page (so three spec pages
    /// stay three pages); with no spec pages they get a page of their own.
    private var last: Int { max(spec.pages.count - 1, 0) }

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            RadialGradient(colors: [spec.tint.opacity(0.45), .clear], center: .init(x: 0.15, y: 0.1), startRadius: 10, endRadius: 420).ignoresSafeArea()
            RadialGradient(colors: [spec.tint2.opacity(0.28), .clear], center: .init(x: 0.9, y: 0.5), startRadius: 10, endRadius: 360).ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    if spec.pages.isEmpty {
                        pageView(icon: "sparkles", title: "Free to use.", text: nil, showsPlans: true).tag(0)
                    }
                    ForEach(Array(spec.pages.enumerated()), id: \.element.id) { i, p in
                        pageView(icon: p.icon, title: p.title, text: p.text, showsPlans: i == last).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) {
                    ForEach(0...last, id: \.self) { i in
                        Capsule().fill(i == page ? spec.tint : .white.opacity(0.18))
                            .frame(width: i == page ? 22 : 7, height: 7)
                            .animation(reduceMotion ? nil : .snappy, value: page)
                    }
                }
                .padding(.bottom, FamilySpacing.l)
                .accessibilityElement()
                .accessibilityLabel("Page \(page + 1) of \(last + 1)")
                Button {
                    if page < last {
                        if reduceMotion { page += 1 } else { withAnimation(.snappy) { page += 1 } }
                    } else { done() }
                } label: {
                    // "Next" / "Let's go" / "Skip": the apps' Spanish catalogs already translate these three.
                    Text(page < last ? "Next" : "Let's go")
                }
                .buttonStyle(FamilyGradientButtonStyle(tint: spec.tint, tint2: spec.tint2))
                .padding(.horizontal, FamilySpacing.xl)
                Button { done() } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 88, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, FamilySpacing.xs).padding(.bottom, FamilySpacing.m)
                .opacity(page < last ? 1 : 0)
                .disabled(page >= last)
                .accessibilityHidden(page >= last)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
        .task { await unlock.load() }
    }

    /// Centered when it fits; scrolls at large Dynamic Type sizes instead of clipping.
    private func pageView(icon: String, title: String, text: String?, showsPlans: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                pageContent(icon: icon, title: title, text: text, showsPlans: showsPlans)
                Spacer(minLength: 0)
            }
            ScrollView(showsIndicators: false) {
                pageContent(icon: icon, title: title, text: text, showsPlans: showsPlans)
            }
        }
    }

    private func pageContent(icon: String, title: String, text: String?, showsPlans: Bool) -> some View {
            VStack(alignment: .leading, spacing: FamilySpacing.l) {
                Image(systemName: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.bottom, FamilySpacing.s)
                    .accessibilityHidden(true)
                Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let text {
                    Text(text).font(.body).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsPlans {
                    VStack(alignment: .leading, spacing: FamilySpacing.m) {
                        row("checkmark.circle.fill", spec.freeLine)
                        row("sparkles", proText)
                    }
                    .padding(FamilySpacing.l)
                    .background(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).fill(.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
                    .padding(.top, FamilySpacing.s)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, FamilySpacing.xxl)
    }

    /// "Pro adds … for $4.99, once. No subscription." Prices (and the free trial, only while this person can still
    /// get it) come from the App Store; before it answers, the sentence ends without a price instead of on "for".
    private var proText: String {
        if unlock.owned { return "You already have \(spec.appName) Pro. Thank you!" }
        var line = spec.proLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prices = priceEnding {
            line += " " + prices
        } else {
            // No price yet: end the sentence instead of leaving it on "for" (or a translation's "por" / "para").
            if let dangling = [" for", " por", " para"].first(where: { line.hasSuffix($0) }) { line.removeLast(dangling.count) }
            if !line.hasSuffix(".") { line += "." }
        }
        if unlock.inTrial {
            let n = unlock.trialDaysLeft
            line += " Your free trial has \(n) day\(n == 1 ? "" : "s") left."
        }
        return line
    }

    /// "$2.99 a month or $19.99 a year (both start with a free week), or $39.99 once." for subscription apps,
    /// "$4.99, once. No subscription." for the one-time unlock; nil until the App Store has answered.
    private var priceEnding: String? {
        guard unlock.usesSubscriptions else {
            return unlock.priceText.isEmpty ? nil : "\(unlock.priceText), once. No subscription."
        }
        let plans = unlock.plans.sorted { Unlock.days($0) < Unlock.days($1) }   // monthly before yearly
        guard !plans.isEmpty else { return nil }
        let prices = plans.map { "\($0.displayPrice) \($0.familyPerWord)" }
        var text = prices.count == 1 ? prices[0] : prices.dropLast().joined(separator: ", ") + " or " + prices[prices.count - 1]
        // The free trial only when every plan has the same one and this Apple ID hasn't used it yet.
        let lengths = plans.map(\.familyFreeTrialLength)   // "1 week", "3 days", or nil
        if unlock.introEligible, let length = lengths[0], lengths.allSatisfy({ $0 == length }) {
            let words = length.split(separator: " ").map(String.init)   // ["1", "week"]
            let unit = words.dropFirst().joined(separator: " ")
            let free = words.first == "1" ? "a free \(unit)" : "\(words.first ?? "") free \(unit)"   // "a free week", "3 free days"
            switch plans.count {
            case 1: text += " (starts with \(free))"
            case 2: text += " (both start with \(free))"
            default: text += " (each starts with \(free))"
            }
        }
        if let lifetime = unlock.product { text += ", or \(lifetime.displayPrice) once" }
        return text + "."
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FamilySpacing.m) {
            Image(systemName: icon).foregroundStyle(spec.tint).font(.body.weight(.semibold)).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
