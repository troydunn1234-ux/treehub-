import SwiftUI

/// What one app's Pro unlock contains. Each app builds one of these.
struct PaywallSpec {
    struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }
    var appName: String
    var headline: String          // "Everything, once."
    var tagline: String           // one sentence under the headline
    var tint: Color
    var tint2: Color
    var features: [Feature]
    var freeNote: String          // what stays free, so nobody feels tricked
    var privacyURL: URL? = nil
}

/// A one-screen paywall. No timers, no fake urgency. Apps that list "SubscriptionProductIDs"
/// get monthly / yearly plans (with Apple's free trial) plus lifetime; the rest sell one lifetime unlock.
/// People who already own Pro see a thank-you card instead of anything to buy.
struct PaywallView: View {
    let spec: PaywallSpec
    /// What the person was trying to do when the sheet came up, e.g. "Cloud Hands".
    var context: String? = nil
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Bought (2) and unlocked right now (1, also during the free trial): one success haptic when either goes up.
    private var proLevel: Int { (unlock.owned ? 2 : 0) + (unlock.isPro ? 1 : 0) }
    private var labelColor: Color { FamilyContrast.label(on: spec.tint, spec.tint2, in: .dark) }

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(spacing: FamilySpacing.xl) {
                    header
                    featureList
                    if unlock.usesSubscriptions {
                        PlansBlock(spec: spec)
                        if !unlock.owned { freeNote }
                    } else if unlock.owned {
                        ProOwnedCard(tint: spec.tint, title: "You're Pro for life",
                                     message: "Everything in \(spec.appName) is unlocked. Thank you for supporting an indie app.")
                        PaywallLinks(spec: spec)
                    } else {
                        buyBlock
                        freeNote
                        PaywallLinks(spec: spec)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, FamilySpacing.l)
                .padding(.bottom, FamilySpacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            // The glyph stays inside its circle at the largest text sizes; long-press shows it large instead.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityShowsLargeContentViewer()
            .accessibilityLabel("Close")
            .padding(10)
        }
        .onChange(of: unlock.isPro) { _, pro in if pro && !unlock.inTrial { dismiss() } }
        .onChange(of: unlock.trialEnds) { _, end in if end != nil && unlock.inTrial { dismiss() } }
        // Bought during the free trial (Pro was already on, so isPro didn't change), or a restore found a purchase.
        .onChange(of: unlock.owned) { _, owned in if owned { dismiss() } }
        .sensoryFeedback(.success, trigger: proLevel) { old, new in new > old }
        .task { await unlock.load() }
        .onAppear {
            unlock.message = nil   // an old "No previous purchase found" shouldn't greet the next visit
            if reduceMotion { appeared = true } else { withAnimation(.spring(duration: 0.9, bounce: 0.25)) { appeared = true } }
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            RadialGradient(colors: [spec.tint.opacity(0.5), .clear], center: .init(x: 0.2, y: 0.05), startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            RadialGradient(colors: [spec.tint2.opacity(0.3), .clear], center: .init(x: 0.95, y: 0.35), startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FamilySpacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption.weight(.bold))
                Text("\(spec.appName) Pro").font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.4)
            }
            .foregroundStyle(spec.tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(spec.tint.opacity(0.16)))
            .accessibilityElement(children: .combine)

            Text(spec.headline)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(context.map { "\($0) is part of Pro. " + spec.tagline } ?? spec.tagline)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FamilySpacing.xxl)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(spec.features.enumerated()), id: \.element.id) { i, f in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: f.icon)
                        .font(.body.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // decorative: stays inside its 38 pt tile
                        .foregroundStyle(labelColor)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: FamilySpacing.innerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title).font(.headline).foregroundStyle(.white)
                        Text(f.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, FamilySpacing.m)
                .accessibilityElement(children: .combine)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.06 * Double(i) + 0.1), value: appeared)
                if i < spec.features.count - 1 { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(.horizontal, FamilySpacing.l).padding(.vertical, FamilySpacing.xs)
        .background(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var freeNote: some View {
        Text(spec.freeNote)
            .font(.footnote).foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: One-time unlock

    private var buyTitle: String {
        unlock.priceText.isEmpty ? "Unlock everything" : "Unlock everything · \(unlock.priceText)"
    }

    /// A purchase or the free trial is in flight (a restore spins its own link instead).
    private var buying: Bool { unlock.busy && !unlock.restoring }

    private var buyBlock: some View {
        VStack(spacing: FamilySpacing.m) {
            if unlock.inTrial {
                Label("Free trial · \(unlock.trialDaysLeft) day\(unlock.trialDaysLeft == 1 ? "" : "s") left", systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(spec.tint)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(spec.tint.opacity(0.14)))
            }
            Button { Task { await unlock.buy() } } label: {
                // One line ("Unlock everything · $4.99 ... once") while it fits; stacked at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: FamilySpacing.s) {
                        if buying { ProgressView().tint(labelColor) }
                        Text(buyTitle)
                        Spacer(minLength: FamilySpacing.s)
                        Text("once").font(.subheadline.weight(.semibold)).opacity(0.7)
                    }
                    VStack(spacing: 2) {
                        if buying { ProgressView().tint(labelColor) }
                        Text(buyTitle)
                        Text("once").font(.subheadline.weight(.semibold)).opacity(0.7)
                    }
                }
            }
            .buttonStyle(FamilyGradientButtonStyle(tint: spec.tint, tint2: spec.tint2))
            .disabled(unlock.busy)
            .accessibilityLabel(unlock.priceText.isEmpty ? "Unlock everything, one-time purchase"
                                : "Unlock everything for \(unlock.priceText), one-time purchase")
            .sensoryFeedback(.impact(weight: .medium), trigger: unlock.busy) { _, busy in busy && !unlock.restoring }
            if unlock.trialAvailable {
                Button { Task { await unlock.startTrial() } } label: {
                    Label("Try everything free for \(Unlock.trialDays) days", systemImage: "gift.fill")
                }
                .buttonStyle(FamilySecondaryButtonStyle(tint: spec.tint))
                .disabled(unlock.busy)
                Text("The trial is free and never charges you. After \(Unlock.trialDays) days the free features stay, and you can unlock everything whenever you like.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("One payment. No subscription. Yours on every device signed in to your Apple ID.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let m = unlock.message {
                Text(m).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shared paywall pieces

/// Restore purchase, Terms of Use (Apple's standard EULA) and Privacy Policy, under every paywall. One row when it
/// fits, a column at large text sizes; every link is a full 44 pt tap target.
struct PaywallLinks: View {
    let spec: PaywallSpec
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FamilySpacing.l) { items }
            VStack(spacing: 0) { items }
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var items: some View {
        // "Restore purchase" (not "Restore Purchases"): the apps' Spanish catalogs already translate this one.
        Button { Task { await unlock.restore() } } label: { item(unlock.restoring ? "Restoring…" : "Restore purchase") }
            .buttonStyle(.plain)
            .disabled(unlock.busy)
        Link(destination: FamilyAboutLinks.standardTerms) { item("Terms of Use") }
        if let u = spec.privacyURL { Link(destination: u) { item("Privacy Policy") } }
    }

    private func item(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// The thank-you card for people who already own Pro (lifetime, or bought back when the app was paid upfront).
struct ProOwnedCard: View {
    var tint: Color
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: FamilySpacing.s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: shown)
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.75))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .onAppear { if !reduceMotion { shown = true } }
    }
}

/// Convenience: `.paywall(isPresented:, spec:)` on any view.
extension View {
    func paywall(isPresented: Binding<Bool>, spec: PaywallSpec, context: String? = nil) -> some View {
        sheet(isPresented: isPresented) { PaywallView(spec: spec, context: context) }
    }
}

/// Root-level presenter: any `Unlock.shared.gate(...)` call opens the paywall here.
extension View {
    func paywallHost(spec: PaywallSpec) -> some View {
        modifier(PaywallHost(spec: spec))
    }
}

private struct PaywallHost: ViewModifier {
    let spec: PaywallSpec
    @ObservedObject private var unlock = Unlock.shared
    /// Set once the paywall sheet has actually appeared (used by the "-demo -paywall" launch below).
    @State private var demoShown = false
    func body(content: Content) -> some View {
        content
            .sheet(item: $unlock.requested) { r in
                PaywallView(spec: spec, context: r.context).onAppear { demoShown = true }
            }
            .task { await openDemoPaywall() }
    }

    /// "-demo -paywall" (App Store review screenshot): open the paywall at launch. Asked for from here, after the
    /// host is on screen, and asked again if it hasn't appeared: a request made while a slow cold start still
    /// shows the launch screen is dropped by UIKit and never retried. Normal launches return right away.
    @MainActor private func openDemoPaywall() async {
        guard Unlock.demoPaywall else { return }
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if demoShown || Task.isCancelled { return }
            unlock.requested = nil
            try? await Task.sleep(nanoseconds: 250_000_000)
            if demoShown { return }
            unlock.requested = PaywallRequest(context: nil)
        }
    }
}

/// Small lock badge for locked rows.
struct ProLockBadge: View {
    var tint: Color
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .accessibilityLabel("Pro")
            .foregroundStyle(.black.opacity(0.8))
            .padding(5)
            .background(Circle().fill(tint))
    }
}
