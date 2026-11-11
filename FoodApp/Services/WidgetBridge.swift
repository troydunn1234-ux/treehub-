import Foundation
import SwiftData
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Keeps the Home Screen widget current: today's calories / protein (eaten and left) and water,
/// written to the App Group after anything is saved, then the widget timeline is reloaded.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    static let appGroup = "group.com.troydunn.foodbook"

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?

    func attach(container: ModelContainer) {
        self.container = container
        guard observers.isEmpty else { return }
        // Meals, water taps and goal changes all end in a save or a defaults change.
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.writeNow() }
        })
        writeNow()
    }

    /// Coalesce bursts of saves into one write.
    private func schedule() {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self.writeNow()
        }
    }

    func writeNow() {
        guard let container, let d = UserDefaults(suiteName: Self.appGroup) else { return }
        let ctx = container.mainContext
        let today = Day.key(Date())
        let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day == today }))) ?? []
        let kcal = entries.reduce(0) { $0 + $1.cal * $1.servings }
        let protein = entries.reduce(0) { $0 + $1.protein * $1.servings }
        let log = try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.day == today })).first

        let health = FoodHealth.shared
        let burn = health.showing ? health.active : 0
        let eatBack = Double(UserDefaults.standard.integer(forKey: "eatBackPct"))
        let goal = (UserDefaults.standard.object(forKey: "goal") as? Double ?? 2200) + burn * eatBack / 100
        let proteinGoal = UserDefaults.standard.object(forKey: "proteinGoal") as? Double ?? 150

        let snapshot: [String: Double] = [
            "kcal": kcal, "protein": protein,
            "kcalLeft": goal - kcal, "proteinLeft": proteinGoal - protein,
            "kcalGoal": goal, "proteinGoal": proteinGoal,
            "water": Double(log?.water ?? 0),
        ]
        // Skip the reload when nothing changed (UserDefaults.didChange fires often).
        var changed = false
        for (k, v) in snapshot where d.double(forKey: k) != v { d.set(v, forKey: k); changed = true }
        if d.string(forKey: "day") != today { d.set(today, forKey: "day"); changed = true }
        guard changed else { return }
        d.set(Date().timeIntervalSince1970, forKey: "updatedAt")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
