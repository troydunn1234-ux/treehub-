import Foundation
import SwiftData

/// Keeps rootbound.json (Shared/Wellness/WellnessBridge.swift) current for Still Pointz, Roamr and Pulse Lab:
/// once at launch and shortly after every save (a tree renamed on its page, a hug deleted, sessions or walks
/// linked), not only when the number of hugs changes or the app goes to the background.
/// Read-only on the hugs; it only rewrites Rootbound's own feed file.
@MainActor
enum RootboundFeedSync {
    private static var saveObserver: NSObjectProtocol?
    private static var pending: DispatchWorkItem?

    /// RootView.onAppear. An empty list isn't published here, so a store that's still opening never replaces the
    /// copy the other apps have with nothing (a real "all hugs deleted" still goes out through the save hook).
    static func start(hugs: [Hug], context: ModelContext) {
        guard !DemoData.isOn else { return }
        if !hugs.isEmpty { RootboundWellness.publish(hugs: hugs) }
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { schedule(context) }
        }
    }

    /// Saves come in bursts (a hug plus its sessions and walks): publish once, 1.5 s after the last one.
    private static func schedule(_ context: ModelContext) {
        pending?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated { publishNow(context) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private static func publishNow(_ context: ModelContext) {
        // A failed fetch publishes nothing (never an empty list by accident).
        guard let hugs = try? context.fetch(FetchDescriptor<Hug>(sortBy: [SortDescriptor(\.date, order: .reverse)])) else { return }
        RootboundWellness.publish(hugs: hugs)
    }
}
