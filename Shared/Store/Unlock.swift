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
    private let paidUntilBuild: Int
    private var updates: Task<Void, Never>?
    private static let cacheKey = "unlock.pro"

    private init() {
        let bundle = Bundle.main.bundleIdentifier ?? "app"
        productID = (Bundle.main.object(forInfoDictionaryKey: "ProProductID") as? String) ?? bundle + ".pro"
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

    deinit { updates?.cancel() }

    var priceText: String { product?.displayPrice ?? "" }

    /// Show the paywall for a locked feature. Returns true if the feature is already unlocked.
    @discardableResult
    func gate(_ context: String) -> Bool {
        if isPro { return true }
        requested = PaywallRequest(context: context)
        return false
    }

    /// Fetch the product so the paywall can show the localized price.
    func load() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [productID]).first
    }

    /// Re-check entitlements: current purchases, then the paid-upfront grandfather clause.
    func refresh() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == productID, t.revocationDate == nil { pro = true }
        }
        if !pro, paidUntilBuild > 0, let shared = try? await AppTransaction.shared, case .verified(let at) = shared {
            let original = Int(at.originalAppVersion.split(separator: ".").first ?? "") ?? Int.max
            if original <= paidUntilBuild { pro = true }
        }
        set(pro)
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
        guard wins == 5 || (wins > 5 && (wins - 5) % 40 == 0) else { return }
        guard Date().timeIntervalSince(last) > 60 * 60 * 24 * 45 else { return }
        d.set(Date(), forKey: lastKey)
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
