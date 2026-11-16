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
struct PaywallView: View {
    let spec: PaywallSpec
    /// What the person was trying to do when the sheet came up, e.g. "Cloud Hands".
    var context: String? = nil
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(spacing: FamilySpacing.xl) {
                    header
                    featureList
                    if unlock.usesSubscriptions {
                        PlansBlock(spec: spec)
                        Text(spec.freeNote)
                            .font(.footnote).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        buyBlock
                        footer
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
            .accessibilityLabel("Close")
            .padding(10)
        }
        .onChange(of: unlock.isPro) { _, pro in if pro && !unlock.inTrial { dismiss() } }
        .onChange(of: unlock.trialEnds) { _, end in if end != nil && unlock.inTrial { dismiss() } }
        .sensoryFeedback(.success, trigger: unlock.isPro) { old, new in !old && new }
        .task { await unlock.load() }
        .onAppear {
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
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: FamilySpacing.innerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title).font(.headline).foregroundStyle(.white)
                        Text(f.detail).font(.subheadline).foregroundStyle(.white.opacity(0.65))
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
                HStack(spacing: 10) {
                    if unlock.busy { ProgressView().tint(.black) }
                    Text(unlock.priceText.isEmpty ? "Unlock everything" : "Unlock everything · \(unlock.priceText)")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text("once").font(.subheadline.weight(.semibold)).opacity(0.7)
                }
                .foregroundStyle(.black.opacity(0.88))
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: FamilySpacing.buttonHeight)
                .background(Capsule().fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .leading, endPoint: .trailing)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(unlock.busy)
            .sensoryFeedback(.impact(weight: .medium), trigger: unlock.busy) { _, busy in busy }
            if unlock.trialAvailable {
                Button { Task { await unlock.startTrial() } } label: {
                    Label("Try everything free for \(Unlock.trialDays) days", systemImage: "gift.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, FamilySpacing.l)
                        .frame(maxWidth: .infinity, minHeight: FamilySpacing.buttonHeight)
                        .background(Capsule().strokeBorder(spec.tint.opacity(0.7), lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
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

    private var footer: some View {
        VStack(spacing: FamilySpacing.m) {
            Text(spec.freeNote)
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: FamilySpacing.l) {
                Button("Restore purchase") { Task { await unlock.restore() } }
                Link("Terms", destination: FamilyAboutLinks.standardTerms)
                if let u = spec.privacyURL { Link("Privacy", destination: u) }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .frame(minHeight: 44)
        }
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
