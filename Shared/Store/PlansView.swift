import SwiftUI
import StoreKit

/// Subscription paywall block: Yearly and Monthly (each with Apple's free trial while this person can still get it)
/// plus Lifetime. Apple's required renewal terms sit right under the button, then Restore, Terms of Use and Privacy
/// Policy (Manage subscription is on the card while subscribed). Lifetime owners are never offered a plan.
/// Prices always come from StoreKit; only the simulator review screenshot uses "-demoPlans" / "-demoPrice".
struct PlansBlock: View {
    let spec: PaywallSpec
    @ObservedObject private var unlock = Unlock.shared
    @State private var selected: String?
    @State private var manage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var options: [Product] {
        var all = unlock.plans
        if let life = unlock.product { all.append(life) }
        return all
    }
    private var choice: Product? {
        options.first { $0.id == (selected ?? unlock.plans.first?.id) } ?? options.first
    }
    private var labelColor: Color { FamilyContrast.label(on: spec.tint, spec.tint2, in: .dark) }

    var body: some View {
        VStack(spacing: FamilySpacing.m) {
            if unlock.subscribed {
                subscribedCard
            } else if unlock.owned {
                // Lifetime (or bought back when the app was paid): nothing more to buy here.
                ProOwnedCard(tint: spec.tint, title: "You're Pro for life",
                             message: "Everything is unlocked. No subscription needed.")
            } else if options.isEmpty && Unlock.demoPaywall {
                demoPlans
            } else if options.isEmpty {
                if unlock.storeUnavailable && !unlock.loadingProducts {
                    FamilyErrorRow(message: "Couldn't reach the App Store to load the plans. Check your connection and try again.",
                                   tint: spec.tint) { Task { await unlock.load() } }
                } else {
                    loadingPlans
                }
            } else {
                ForEach(options, id: \.id) { p in planRow(p) }
                cta
                termsText(terms(for: choice))
            }
            if let m = unlock.message {
                Text(m).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // While subscribed, "Manage subscription" sits on the card above, so the links skip it.
            PaywallLinks(spec: spec)
        }
        .manageSubscriptionsSheet(isPresented: $manage)
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Loading (placeholder rows instead of a spinner)

    private var loadingPlans: some View {
        VStack(spacing: FamilySpacing.m) {
            ForEach(0..<3, id: \.self) { i in
                PlanRowLabel(title: "Yearly plan", badge: nil, subtitle: "A short line about the plan",
                             price: "$00.00", period: "per year", isOn: i == 0, save: nil, tint: spec.tint, tint2: spec.tint2)
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
            Text("Loading plans from the App Store…")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Simulator screenshot (no App Store there): the same rows, priced from "-demoPlans" / "-demoPrice"

    private var demoPlans: some View {
        let plans = (Unlock.demoArg("-demoPlans") ?? "").split(separator: ",").map { String($0) }
        let yearly = plans.first ?? "19.99"
        let monthly = plans.count > 1 ? plans[1] : "2.99"
        let lifetime = Unlock.demoArg("-demoPrice")
        let y = Double(yearly) ?? 0, m = Double(monthly) ?? 0
        let save: String? = m > 0 && y < m * 12 ? "SAVE \(Int(((1 - y / (m * 12)) * 100).rounded()))%" : nil
        return VStack(spacing: FamilySpacing.m) {
            PlanRowLabel(title: "Yearly", badge: "1 week free", subtitle: String(format: "Just $%.2f a month", y / 12),
                         price: "$" + yearly, period: "per year", isOn: true, save: save, tint: spec.tint, tint2: spec.tint2)
            PlanRowLabel(title: "Monthly", badge: "1 week free", subtitle: "Cancel anytime",
                         price: "$" + monthly, period: "per month", isOn: false, save: nil, tint: spec.tint, tint2: spec.tint2)
            if let lifetime {
                PlanRowLabel(title: "Lifetime", badge: nil, subtitle: "Pay once, keep Pro forever",
                             price: "$" + lifetime, period: "once", isOn: false, save: nil, tint: spec.tint, tint2: spec.tint2)
            }
            Button {} label: {
                VStack(spacing: 2) {
                    Text("Start 1 week free trial")
                    Text("then $\(yearly) per year").font(.footnote.weight(.semibold)).opacity(0.8)
                }
            }
            .buttonStyle(FamilyGradientButtonStyle(tint: spec.tint, tint2: spec.tint2))
            termsText("Free for 1 week, then $\(yearly) per year. Renews automatically until cancelled. Payment is charged to your Apple ID; cancel anytime in Settings › your name › Subscriptions at least 24 hours before the period ends.")
        }
    }

    // MARK: Rows

    private func planRow(_ p: Product) -> some View {
        let isOn = choice?.id == p.id
        let isYear = p.subscription?.subscriptionPeriod.unit == .year
        let trial = freeTrialText(p)
        let save = isYear ? savings() : nil
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { selected = p.id }
        } label: {
            PlanRowLabel(title: title(p), badge: trial, subtitle: subtitle(p), price: p.displayPrice, period: p.familyPeriodWord,
                         isOn: isOn, save: save, tint: spec.tint, tint2: spec.tint2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title(p), "\(p.displayPrice) \(p.familyPeriodWord)", trial, subtitle(p), save]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var cta: some View {
        Button {
            guard let p = choice else { return }
            Task {
                if p.type == .autoRenewable { await unlock.subscribe(p) } else { await unlock.buy() }
            }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: FamilySpacing.s) {
                    if unlock.busy && !unlock.restoring { ProgressView().tint(labelColor) }
                    Text(ctaTitle)
                }
                // A free-trial button also says what it costs afterwards, so the billed amount is never hidden.
                if let then = ctaThen {
                    Text(then).font(.footnote.weight(.semibold)).opacity(0.8)
                }
            }
        }
        .buttonStyle(FamilyGradientButtonStyle(tint: spec.tint, tint2: spec.tint2))
        .disabled(unlock.busy || choice == nil)
        .accessibilityLabel(ctaAccessibilityLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: unlock.busy) { _, busy in busy && !unlock.restoring }
    }

    private var subscribedCard: some View {
        VStack(spacing: FamilySpacing.s) {
            Label(unlock.ownsLifetime ? "You're Pro for life" : "You're Pro", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.bold)).foregroundStyle(spec.tint)
            if let id = unlock.activePlanID, let p = unlock.plans.first(where: { $0.id == id }) {
                Text("\(title(p)) · \(p.displayPrice) \(p.familyPeriodWord)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            }
            if let d = unlock.renewsOrEnds {
                Text("Renews or ends \(d.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            if unlock.ownsLifetime {
                // Bought Lifetime while a subscription was running: say so, so they can cancel it.
                Text("You also own Lifetime, so this subscription isn't needed anymore. You can cancel it under Manage subscription.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            Button { manage = true } label: { Text("Manage subscription") }
                .buttonStyle(FamilySecondaryButtonStyle(tint: spec.tint))
                .padding(.top, FamilySpacing.xs)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private func termsText(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
        guard unlock.introEligible, let length = p.familyFreeTrialLength else { return nil }
        return "\(length) free"
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
        return "Subscribe · \(p.displayPrice) \(p.familyPeriodWord)"
    }

    /// "then $19.99 per year" under a free-trial button.
    private var ctaThen: String? {
        guard let p = choice, freeTrialText(p) != nil else { return nil }
        return "then \(p.displayPrice) \(p.familyPeriodWord)"
    }

    /// The button as VoiceOver reads it (no "·", and what happens after a trial).
    private var ctaAccessibilityLabel: String {
        guard let p = choice else { return "Continue" }
        if let free = freeTrialText(p) { return "Start \(free) trial, then \(p.displayPrice) \(p.familyPeriodWord)" }
        if p.subscription == nil { return "Unlock forever for \(p.displayPrice), one-time purchase" }
        return "Subscribe for \(p.displayPrice) \(p.familyPeriodWord)"
    }

    /// Apple's required disclosure for auto-renewing subscriptions, right by the button.
    private func terms(for p: Product?) -> String {
        guard let p else { return "" }
        guard p.subscription != nil else { return "One payment. No subscription. Yours on every device signed in to your Apple ID." }
        let price = "\(p.displayPrice) \(p.familyPeriodWord)"
        let lead = freeTrialText(p).map { "Free for \($0.replacingOccurrences(of: " free", with: "")), then \(price). " } ?? "\(price). "
        return lead + "Renews automatically until cancelled. Payment is charged to your Apple ID; cancel anytime in Settings › your name › Subscriptions at least 24 hours before the period ends."
    }
}

// MARK: - Plan row

/// One plan row, shared by the live plans and the simulator review screenshot so both look the same.
/// At accessibility text sizes it stacks (title, badge, line, price) instead of squeezing one line.
private struct PlanRowLabel: View {
    let title: String
    let badge: String?
    let subtitle: String
    let price: String
    let period: String
    let isOn: Bool
    let save: String?
    let tint: Color
    let tint2: Color
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous)
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(.white.opacity(isOn ? 0.12 : 0.05)))
            .overlay(shape.strokeBorder(isOn ? tint : .white.opacity(0.08), lineWidth: isOn ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if let save {
                    // Sits on the top edge, centered on it at every text size.
                    Text(save).font(.caption2.weight(.heavy))
                        .foregroundStyle(FamilyContrast.label(on: tint2, in: scheme))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(tint2))
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .padding(.trailing, 12)
                }
            }
            .contentShape(shape)
    }

    @ViewBuilder private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: FamilySpacing.xs) {
                HStack(spacing: FamilySpacing.s) { check; titleText }
                if let badge { badgeView(badge) }
                subtitleText
                HStack(alignment: .firstTextBaseline, spacing: 6) { priceText; periodText }
            }
        } else {
            HStack(spacing: FamilySpacing.m) {
                check
                VStack(alignment: .leading, spacing: 3) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { titleText; if let badge { badgeView(badge) } }
                        VStack(alignment: .leading, spacing: FamilySpacing.xs) { titleText; if let badge { badgeView(badge) } }
                    }
                    subtitleText
                }
                Spacer(minLength: FamilySpacing.s)
                VStack(alignment: .trailing, spacing: 2) { priceText; periodText }
            }
        }
    }

    private var check: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isOn ? tint : .white.opacity(0.35))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(title).font(.headline).foregroundStyle(.white)
    }

    private var subtitleText: some View {
        Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var priceText: some View {
        Text(price).font(.headline.monospacedDigit()).foregroundStyle(.white)
    }

    private var periodText: some View {
        Text(period).font(.caption).foregroundStyle(.white.opacity(0.6))
    }

    private func badgeView(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.heavy)).tracking(0.6)
            .foregroundStyle(FamilyContrast.label(on: tint, in: scheme))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(tint))
            .fixedSize()
    }
}

// MARK: - Plan wording from StoreKit

extension Product {
    /// "per month", "per year", "every 3 months", or "once" for the lifetime unlock.
    var familyPeriodWord: String {
        guard let s = subscription?.subscriptionPeriod else { return "once" }
        switch s.unit {
        case .day: return s.value == 1 ? "per day" : "every \(s.value) days"
        case .week: return s.value == 1 ? "per week" : "every \(s.value) weeks"
        case .month: return s.value == 1 ? "per month" : "every \(s.value) months"
        case .year: return s.value == 1 ? "per year" : "every \(s.value) years"
        @unknown default: return ""
        }
    }

    /// "a month", "a year": for sentences like "$2.99 a month".
    var familyPerWord: String {
        guard let s = subscription?.subscriptionPeriod, s.value == 1 else { return familyPeriodWord }
        switch s.unit {
        case .day: return "a day"
        case .week: return "a week"
        case .month: return "a month"
        case .year: return "a year"
        @unknown default: return familyPeriodWord
        }
    }

    /// The length of this plan's free-trial introductory offer ("1 week"), if it has one. Whether this person
    /// can still get it is `Unlock.introEligible` (one free trial per person per subscription group).
    var familyFreeTrialLength: String? {
        guard let o = subscription?.introductoryOffer, o.paymentMode == .freeTrial else { return nil }
        let n = o.period.value
        switch o.period.unit {
        case .day: return n == 7 ? "1 week" : "\(n) day\(n == 1 ? "" : "s")"
        case .week: return "\(n) week\(n == 1 ? "" : "s")"
        case .month: return "\(n) month\(n == 1 ? "" : "s")"
        case .year: return "\(n) year\(n == 1 ? "" : "s")"
        @unknown default: return nil
        }
    }
}
