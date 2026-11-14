import SwiftUI
import StoreKit

/// Subscription paywall block: Yearly (with the free trial), Monthly, and Lifetime.
/// Shows Apple's required renewal terms right above the button, plus Terms, Privacy, Restore and Manage.
struct PlansBlock: View {
    let spec: PaywallSpec
    @ObservedObject private var unlock = Unlock.shared
    @State private var selected: String?
    @State private var manage = false

    private static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private var options: [Product] {
        var all = unlock.plans
        if let life = unlock.product { all.append(life) }
        return all
    }
    private var choice: Product? {
        options.first { $0.id == (selected ?? unlock.plans.first?.id) } ?? options.first
    }

    var body: some View {
        VStack(spacing: 12) {
            if unlock.subscribed {
                subscribedCard
            } else if options.isEmpty {
                ProgressView().tint(.white).padding(30)
                Text("Loading plans from the App Store…").font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(options, id: \.id) { p in planRow(p) }
                cta
                Text(terms(for: choice))
                    .font(.system(size: 11.5, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = unlock.message {
                Text(m).font(.system(size: 13, design: .rounded)).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            links
        }
        .manageSubscriptionsSheet(isPresented: $manage)
    }

    // MARK: Rows

    private func planRow(_ p: Product) -> some View {
        let isOn = choice?.id == p.id
        let isYear = (p.subscription?.subscriptionPeriod.unit == .year)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selected = p.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isOn ? spec.tint : .white.opacity(0.35))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title(p)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        if let free = freeTrialText(p) {
                            Text(free.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(spec.tint))
                        }
                    }
                    Text(subtitle(p)).font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.displayPrice).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(periodWord(p)).font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(isOn ? 0.12 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isOn ? spec.tint : .white.opacity(0.08), lineWidth: isOn ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if isYear, let save = savings() {
                    Text(save).font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(spec.tint2))
                        .offset(x: -12, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(p)), \(p.displayPrice) \(periodWord(p))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var cta: some View {
        Button {
            guard let p = choice else { return }
            Task {
                if p.type == .autoRenewable { await unlock.subscribe(p) } else { await unlock.buy() }
            }
        } label: {
            HStack(spacing: 10) {
                if unlock.busy { ProgressView().tint(.black) }
                Text(ctaTitle).font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().fill(LinearGradient(colors: [spec.tint, spec.tint2], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: spec.tint.opacity(0.45), radius: 18, y: 8)
        }
        .disabled(unlock.busy || choice == nil)
    }

    private var subscribedCard: some View {
        VStack(spacing: 8) {
            Label("You're Pro", systemImage: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(spec.tint)
            if let id = unlock.activePlanID, let p = unlock.plans.first(where: { $0.id == id }) {
                Text("\(title(p)) · \(p.displayPrice) \(periodWord(p))")
                    .font(.system(size: 14, design: .rounded)).foregroundStyle(.white.opacity(0.75))
            }
            if let d = unlock.renewsOrEnds {
                Text("Renews or ends \(d.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            }
            Button("Manage subscription") { manage = true }
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.06)))
    }

    private var links: some View {
        HStack(spacing: 16) {
            Button("Restore") { Task { await unlock.restore() } }
            if unlock.subscribed { Button("Manage") { manage = true } }
            Link("Terms", destination: Self.terms)
            if let u = spec.privacyURL { Link("Privacy", destination: u) }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 4)
    }

    // MARK: Text

    private func title(_ p: Product) -> String {
        guard let s = p.subscription?.subscriptionPeriod else { return "Lifetime" }
        switch s.unit {
        case .year: return "Yearly"
        case .month: return s.value == 1 ? "Monthly" : "\(s.value) months"
        case .week: return "Weekly"
        default: return p.displayName
        }
    }

    private func periodWord(_ p: Product) -> String {
        guard let s = p.subscription?.subscriptionPeriod else { return "once" }
        switch s.unit {
        case .year: return "per year"
        case .month: return s.value == 1 ? "per month" : "every \(s.value) months"
        case .week: return "per week"
        default: return ""
        }
    }

    private func subtitle(_ p: Product) -> String {
        if p.subscription == nil { return "Pay once, keep Pro forever" }
        if p.subscription?.subscriptionPeriod.unit == .year {
            let perMonth = p.price / 12
            return "Just \(perMonth.formatted(p.priceFormatStyle)) a month"
        }
        return "Cancel anytime"
    }

    /// "1 week free" when this person can still get the trial on this plan.
    private func freeTrialText(_ p: Product) -> String? {
        guard unlock.introEligible, let o = p.subscription?.introductoryOffer, o.paymentMode == .freeTrial else { return nil }
        return "\(lengthText(o.period)) free"
    }

    private func lengthText(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day: return n == 7 ? "1 week" : "\(n) day\(n == 1 ? "" : "s")"
        case .week: return "\(n) week\(n == 1 ? "" : "s")"
        case .month: return "\(n) month\(n == 1 ? "" : "s")"
        case .year: return "\(n) year\(n == 1 ? "" : "s")"
        @unknown default: return ""
        }
    }

    /// "SAVE 44%" for yearly vs paying monthly for 12 months.
    private func savings() -> String? {
        guard let y = unlock.plans.first(where: { $0.subscription?.subscriptionPeriod.unit == .year }),
              let m = unlock.plans.first(where: { $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1 })
        else { return nil }
        let yearly = NSDecimalNumber(decimal: y.price).doubleValue
        let monthly = NSDecimalNumber(decimal: m.price).doubleValue * 12
        guard monthly > 0, yearly < monthly else { return nil }
        return "SAVE \(Int(((1 - yearly / monthly) * 100).rounded()))%"
    }

    private var ctaTitle: String {
        guard let p = choice else { return "Continue" }
        if let free = freeTrialText(p) { return "Start \(free) trial" }
        if p.subscription == nil { return "Unlock forever · \(p.displayPrice)" }
        return "Subscribe · \(p.displayPrice) \(periodWord(p))"
    }

    /// Apple's required disclosure for auto-renewing subscriptions, right by the button.
    private func terms(for p: Product?) -> String {
        guard let p else { return "" }
        guard p.subscription != nil else { return "One payment. No subscription. Yours on every device signed in to your Apple ID." }
        let price = "\(p.displayPrice) \(periodWord(p))"
        let lead = freeTrialText(p).map { "Free for \($0.replacingOccurrences(of: " free", with: "")), then \(price). " } ?? "\(price). "
        return lead + "Renews automatically until cancelled. Payment is charged to your Apple ID; cancel anytime in Settings › your name › Subscriptions at least 24 hours before the period ends."
    }
}
