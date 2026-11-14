import Foundation
import StoreKit
import SwiftUI

/// One-time "Pro" unlock, shared by the paid apps.
///
/// Model: the app is free to download with a useful free tier; one non-consumable
/// in-app purchase (`<bundle id>.pro`) unlocks everything, forever. People who bought
/// the app back when it was paid-upfront are grandfathered in: the App Store's
/// `AppTransaction.originalAppVersion` (the build number of the first download) is
/// compared with `PaidUntilBuild` in Info.plist.
@MainActor
final class Unlock: ObservableObject {
    static let shared = Unlock()

    @Published private(set) var isPro: Bool
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    @Published var message: String?
    /// Set when some part of the app wants the paywall shown; the root view presents it.
    @Published var requested: PaywallRequest?

    let productID: String
    /// Free 7-day trial: a $0 non-consumable ("7-day Trial"), the way Apple asks one-time-unlock apps to do trials.
    let trialProductID: String
    static let trialDays = 7
    @Published private(set) var trialProduct: Product?
    /// When the trial runs out, once one has been started on this Apple ID.
    @Published private(set) var trialEnds: Date?
    /// Bought Pro (or bought the app back when it was paid upfront).
    @Published private(set) var owned = false
    private var expiryTask: Task<Void, Never>?

    // MARK: Subscriptions (opt-in per app via Info.plist "SubscriptionProductIDs")
    /// Auto-renewable plans, e.g. monthly + yearly. Empty = this app only sells the one-time unlock.
    let subscriptionIDs: [String]
    var usesSubscriptions: Bool { !subscriptionIDs.isEmpty }
    /// Loaded plans, longest period first (yearly before monthly).
    @Published private(set) var plans: [Product] = []
    /// Has a live subscription (including Apple's free-trial period).
    @Published private(set) var subscribed = false
    @Published private(set) var activePlanID: String?
    @Published private(set) var renewsOrEnds: Date?
    /// Can still use the free-trial introductory offer (one per person per subscription group).
    @Published private(set) var introEligible = false
    private let paidUntilBuild: Int
    private var updates: Task<Void, Never>?
    private static let cacheKey = "unlock.pro"

    private init() {
        let bundle = Bundle.main.bundleIdentifier ?? "app"
        productID = (Bundle.main.object(forInfoDictionaryKey: "ProProductID") as? String) ?? bundle + ".pro"
        trialProductID = (Bundle.main.object(forInfoDictionaryKey: "TrialProductID") as? String) ?? bundle + ".trial"
        subscriptionIDs = (Bundle.main.object(forInfoDictionaryKey: "SubscriptionProductIDs") as? [String]) ?? []
        paidUntilBuild = (Bundle.main.object(forInfoDictionaryKey: "PaidUntilBuild") as? NSNumber)?.intValue ?? 0
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pro") { isPro = true }
        if ProcessInfo.processInfo.arguments.contains("-free") { isPro = false }
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    await self?.refresh()
                }
            }
        }
        Task { await load(); await refresh() }
    }

    deinit { updates?.cancel(); expiryTask?.cancel() }

    var priceText: String { product?.displayPrice ?? "" }

    /// Everything is open right now because of the free trial (not a purchase).
    var inTrial: Bool { !owned && (trialEnds.map { $0 > Date() } ?? false) }
    /// The trial can still be started: never used on this Apple ID and the product exists.
    var trialAvailable: Bool { !owned && trialEnds == nil && trialProduct != nil }
    var trialDaysLeft: Int {
        guard let end = trialEnds else { return 0 }
        return max(0, Int((end.timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    /// Show the paywall for a locked feature. Returns true if the feature is already unlocked.
    @discardableResult
    func gate(_ context: String) -> Bool {
        if isPro { return true }
        requested = PaywallRequest(context: context)
        return false
    }

    /// Fetch the product so the paywall can show the localized price.
    func load() async {
        guard product == nil || trialProduct == nil || (usesSubscriptions && plans.isEmpty) else { return }
        let found = (try? await Product.products(for: [productID, trialProductID] + subscriptionIDs)) ?? []
        if product == nil { product = found.first { $0.id == productID } }
        if trialProduct == nil { trialProduct = found.first { $0.id == trialProductID } }
        let subs = found.filter { subscriptionIDs.contains($0.id) }
        if !subs.isEmpty {
            plans = subs.sorted { Self.days($0) > Self.days($1) }
            introEligible = await plans.first?.subscription?.isEligibleForIntroOffer ?? false
        }
    }

    /// Rough length of a plan in days, for sorting and per-month maths.
    static func days(_ p: Product) -> Int {
        guard let s = p.subscription?.subscriptionPeriod else { return 0 }
        switch s.unit {
        case .day: return s.value
        case .week: return s.value * 7
        case .month: return s.value * 30
        case .year: return s.value * 365
        @unknown default: return 0
        }
    }

    /// Re-check entitlements: current purchases, then the paid-upfront grandfather clause.
    func refresh() async {
        var pro = false
        var trialStart: Date?
        var sub: StoreKit.Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == productID { pro = true }
            if subscriptionIDs.contains(t.productID), (t.expirationDate ?? .distantFuture) > Date() { sub = t }
            if t.productID == trialProductID { trialStart = t.originalPurchaseDate }
        }
        trialEnds = trialStart.map { $0.addingTimeInterval(Double(Self.trialDays) * 86_400) }
        if !pro, paidUntilBuild > 0, let shared = try? await AppTransaction.shared, case .verified(let at) = shared {
            let original = Int(at.originalAppVersion.split(separator: ".").first ?? "") ?? Int.max
            if original <= paidUntilBuild { pro = true }
        }
        subscribed = sub != nil
        activePlanID = sub?.productID
        renewsOrEnds = sub?.expirationDate
        if usesSubscriptions, let first = plans.first {
            introEligible = await first.subscription?.isEligibleForIntroOffer ?? false
        }
        owned = pro || subscribed
        set(owned || inTrial)
        scheduleTrialExpiry()
        scheduleSubscriptionCheck()
    }

    /// Re-check right after the current period ends, so a lapsed subscription locks again
    /// (and a renewal is picked up) even if the app stays open.
    private var subTask: Task<Void, Never>?
    private func scheduleSubscriptionCheck() {
        subTask?.cancel()
        guard subscribed, let end = renewsOrEnds else { return }
        let wait = end.timeIntervalSinceNow + 60
        guard wait > 0, wait < 40 * 86_400 else { return }
        subTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Buy one of the subscription plans.
    func subscribe(_ plan: Product) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        message = nil
        do {
            switch try await plan.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    await refresh()
                } else {
                    message = "Apple couldn't verify that purchase."
                }
            case .pending: message = "Waiting for approval (Ask to Buy)."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Start the free trial (a $0 purchase, so Apple shows its usual confirm sheet).
    func startTrial() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        message = nil
        if trialProduct == nil { await load() }
        guard let trialProduct else { message = "The App Store didn't answer. Try again in a moment."; return }
        do {
            switch try await trialProduct.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification { await t.finish() }
                await refresh()
            case .pending: message = "Waiting for approval (Ask to Buy)."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Lock things back up the moment the trial runs out, even if the app stays open.
    private func scheduleTrialExpiry() {
        expiryTask?.cancel()
        guard inTrial, let end = trialEnds else { return }
        let wait = end.timeIntervalSinceNow
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, wait) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func buy() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        message = nil
        if product == nil { await load() }
        guard let product else { message = "The App Store didn't answer. Try again in a moment."; return }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    owned = true
                    set(true)
                } else {
                    message = "Apple couldn't verify that purchase."
                }
            case .pending: message = "Waiting for approval (Ask to Buy)."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        message = nil
        try? await AppStore.sync()
        await refresh()
        if !isPro { message = "No previous purchase found for this Apple ID." }
    }

    private func set(_ pro: Bool) {
        if isPro != pro { isPro = pro }
        UserDefaults.standard.set(pro, forKey: Self.cacheKey)
    }
}

struct PaywallRequest: Identifiable { let id = UUID(); let context: String }

// MARK: - Review prompts

/// Ask for a rating only after the app has done something good for the person, a few
/// times, and never more than Apple allows (they throttle to 3 prompts a year anyway).
enum Reviews {
    private static let winsKey = "reviews.wins"
    private static let lastKey = "reviews.lastAsked"

    /// Call after a real success: a session finished, a TV responded, a chart drawn.
    @MainActor static func noteWin() {
        let d = UserDefaults.standard
        let wins = d.integer(forKey: winsKey) + 1
        d.set(wins, forKey: winsKey)
        let last = d.object(forKey: lastKey) as? Date ?? .distantPast
        // First ask after a handful of good moments, then at most every ~2 months.
        guard wins >= 4 else { return }
        guard Date().timeIntervalSince(last) > 60 * 60 * 24 * 60 else { return }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        d.set(Date(), forKey: lastKey)
        // A short pause so the prompt lands after the success animation, not on top of it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { SKStoreReviewController.requestReview(in: scene) }
    }
}
