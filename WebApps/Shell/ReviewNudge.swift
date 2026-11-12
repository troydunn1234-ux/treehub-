import StoreKit
import UIKit

/// Ask for an App Store rating only after the app has done something good for the person
/// a few times, and at most every couple of months (Apple also caps it at 3 a year).
enum ReviewNudge {
    private static let winsKey = "reviews.wins"
    private static let lastKey = "reviews.lastAsked"

    @MainActor static func noteWin(threshold: Int = 4) {
        let d = UserDefaults.standard
        let wins = d.integer(forKey: winsKey) + 1
        d.set(wins, forKey: winsKey)
        guard wins >= threshold else { return }
        let last = d.object(forKey: lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 60 * 60 * 24 * 60 else { return }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        d.set(Date(), forKey: lastKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { SKStoreReviewController.requestReview(in: scene) }
    }
}
