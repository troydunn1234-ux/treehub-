import Foundation
import SwiftData

extension TopSpeedRepair {
    /// Once per install, after this update: past trips whose top speed was a GPS spike get the cleaned-up value
    /// from their own saved route (see `TopSpeedRepair.corrected`). Only `maxSpeed` (lowered) and `rawMaxSpeed`
    /// (the original) change. The flag is set only after a successful save, and the repair is idempotent.
    ///
    /// A big history used to be decoded all at once on the main thread (the screen froze for seconds after launch).
    /// Now a few trips at a time: only their stored route bytes are read here (SwiftData objects stay on the main
    /// actor); decoding and checking run in the background. A trip deleted or edited in the meantime is left alone.
    @MainActor
    static func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) async -> Int {
        guard !TrackDemo.isOn, !defaults.bool(forKey: doneKey) else { return 0 }
        guard let all = try? context.fetch(FetchDescriptor<Activity>()) else { return 0 }
        let trips = all.filter { $0.rawMaxSpeed == nil && $0.maxSpeed.isFinite && $0.maxSpeed > 0 }
        var changed = 0
        var next = 0
        while next < trips.count {
            let batch = Array(trips[next..<min(next + 12, trips.count)])
            next += batch.count
            let inputs: [(data: Data?, top: Double, kind: ActivityKind)] = batch.map {
                (data: $0.routeData, top: $0.maxSpeed, kind: $0.kind)
            }
            let fixes: [Double?] = await Task.detached(priority: .utility) {
                inputs.map { TopSpeedRepair.corrected(maxSpeed: $0.top, routeData: $0.data, kind: $0.kind) }
            }.value
            for (i, a) in batch.enumerated() {
                guard let fixed = fixes[i], a.modelContext != nil, !a.isDeleted,
                      a.rawMaxSpeed == nil, a.maxSpeed == inputs[i].top else { continue }
                a.rawMaxSpeed = a.maxSpeed
                a.maxSpeed = fixed
                changed += 1
            }
        }
        do {
            if changed > 0 { try context.save() }
            defaults.set(true, forKey: doneKey)
        } catch {
            context.rollback()
        }
        return changed
    }
}
