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
    @State private var appeared = false

    var body: some View {
        ZStack {
            background
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    featureList
                    if unlock.usesSubscriptions {
                        PlansBlock(spec: spec)
                        Text(spec.freeNote)
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    } else {
                        buyBlock
                        footer
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(9)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .padding(16)
        }
        .onChange(of: unlock.isPro) { _, pro in if pro && !unlock.inTrial { dismiss() } }
        .onChange(of: unlock.trialEnds) { _, end in if end != nil && unlock.inTrial { dismiss() } }
        .task { await unlock.load() }
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.25)) { appeared = true } }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            RadialGradient(colors: [spec.tint.opacity(0.55), .clear], center: .init(x: 0.2, y: 0.05), startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            RadialGradient(colors: [spec.tint2.opacity(0.35), .clear], center: .init(x: 0.95, y: 0.35), startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                Text("\(spec.appName.uppercased()) PRO").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.8)
            }
            .foregroundStyle(spec.tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(spec.tint.opacity(0.14)))

            Text(spec.headline)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(context.map { "\($0) is part of Pro. " + spec.tagline } ?? spec.tagline)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(Array(spec.features.enumerated()), id: \.element.id) { i, f in
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: f.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.black.opacity(0.8))
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text(f.detail).font(.system(size: 13.5, design: .rounded)).foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
                .animation(.spring(duration: 0.8, bounce: 0.2).delay(0.06 * Double(i) + 0.1), value: appeared)
                if i < spec.features.count - 1 { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
    }

    private var buyBlock: some View {
        VStack(spacing: 12) {
            if unlock.inTrial {
                Label("Free trial · \(unlock.trialDaysLeft) day\(unlock.trialDaysLeft == 1 ? "" : "s") left", systemImage: "hourglass")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(spec.tint)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(spec.tint.opacity(0.14)))
            }
            Button { Task { await unlock.buy() } } label: {
                HStack(spacing: 10) {
                    if unlock.busy { ProgressView().tint(.black) }
                    Text(unlock.priceText.isEmpty ? "Unlock everything" : "Unlock everything · \(unlock.priceText)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Text("once").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.7)
                }
                .foregroundStyle(.black.opacity(0.88))
                .padding(.horizontal, 20).padding(.vertical, 17)
                .background(Capsule().fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: spec.tint.opacity(0.45), radius: 18, y: 8)
            }
            .disabled(unlock.busy)
            if unlock.trialAvailable {
                Button { Task { await unlock.startTrial() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                        Text("Try everything free for \(Unlock.trialDays) days")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().stroke(spec.tint.opacity(0.7), lineWidth: 1.5))
                }
                .disabled(unlock.busy)
                Text("The trial is free and never charges you. After \(Unlock.trialDays) days the free features stay, and you can unlock everything whenever you like.")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            Text("One payment. No subscription. Yours on every device signed in to your Apple ID.")
                .font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            if let m = unlock.message {
                Text(m).font(.system(size: 13, design: .rounded)).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text(spec.freeNote)
                .font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Button("Restore purchase") { Task { await unlock.restore() } }
                if let u = spec.privacyURL { Link("Privacy", destination: u) }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
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
    func body(content: Content) -> some View {
        content.sheet(item: $unlock.requested) { r in PaywallView(spec: spec, context: r.context) }
    }
}

/// Small lock badge for locked rows.
struct ProLockBadge: View {
    var tint: Color
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.8))
            .padding(5)
            .background(Circle().fill(tint))
    }
}
