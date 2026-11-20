import Foundation
import SwiftData

extension TopSpeedRepair {
    /// Once per install, after this update: past trips whose top speed was a GPS spike get the cleaned-up value
    /// from their own saved route (see `TopSpeedRepair.repair`). Only `maxSpeed` (lowered) and `rawMaxSpeed`
    /// (the original) change. The flag is set only after a successful save, and the repair is idempotent.
    @MainActor
    static func runOnce(in context: ModelContext) -> Int {
        guard !TrackDemo.isOn, !UserDefaults.standard.bool(forKey: doneKey) else { return 0 }
        guard let trips = try? context.fetch(FetchDescriptor<Activity>()) else { return 0 }
        let changed = repair(trips)
        do {
            if changed > 0 { try context.save() }
            UserDefaults.standard.set(true, forKey: doneKey)
        } catch {
            context.rollback()
        }
        return changed
    }
}
