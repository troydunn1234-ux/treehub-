import Foundation
import SwiftData
import UIKit
import WatchConnectivity

/// iPhone side of the Apple Watch link: sends today's calories, macros, quick foods and the
/// supplement checklist, and logs a food / checks off a supplement when the watch asks.
@MainActor
final class FoodWatchBridge: NSObject {
    static let shared = FoodWatchBridge()

    private var container: ModelContainer?
    private var saveObserver: NSObjectProtocol?
    private var pushTask: Task<Void, Never>?

    func attach(container: ModelContainer) {
        guard WCSession.isSupported() else { return }
        self.container = container
        let s = WCSession.default
        s.delegate = self
        s.activate()
        // Anything saved on the phone (new food, a check-off) refreshes the watch.
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        }
    }

    /// Coalesce bursts of saves into one push.
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.push()
        }
    }

    /// Push right away (e.g. just after logging from the camera), skipping the coalescing delay.
    func pushNow() {
        pushTask?.cancel()
        push()
    }

    private func push() {
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let state = snapshot()
        try? s.updateApplicationContext(state)
        if s.isReachable { s.sendMessage(state, replyHandler: nil, errorHandler: nil) }
    }

    func snapshot() -> [String: Any] {
        guard let container else { return [:] }
        let ctx = container.mainContext
        let today = Day.key(Date())
        let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day == today }))) ?? []
        func total(_ k: KeyPath<FoodEntry, Double>) -> Double { entries.reduce(0) { $0 + $1[keyPath: k] * $1.servings } }

        // Quick foods: your 6 most recent distinct foods, or popular picks if you're new.
        var recentFD = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recentFD.fetchLimit = 80
        var seen = Set<String>()
        var quick: [[String: Any]] = []
        for e in (try? ctx.fetch(recentFD)) ?? [] where !seen.contains(e.name.lowercased()) {
            seen.insert(e.name.lowercased())
            var item: [String: Any] = ["id": e.name, "name": e.name, "cal": e.cal * e.servings]
            if let t = Self.watchThumb(e.photo) { item["thumb"] = t }
            quick.append(item)
            if quick.count == 6 { break }
        }
        if quick.isEmpty {
            quick = QuickFood.all.prefix(6).map { ["id": "qf:" + $0.name, "name": $0.name, "cal": Double($0.cal)] as [String: Any] }
        }

        let supps = (try? ctx.fetch(FetchDescriptor<Supplement>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let doses = (try? ctx.fetch(FetchDescriptor<SuppDose>(predicate: #Predicate { $0.day == today }))) ?? []
        let taken = Set(doses.map(\.suppID))
        let suppList: [[String: Any]] = supps.map {
            ["id": $0.id.uuidString, "name": $0.name, "dose": $0.dose, "emoji": $0.emoji,
             "time": $0.time.rawValue, "taken": taken.contains($0.id)] as [String: Any]
        }

        // The most recent thing logged today, shown on the watch's Today page.
        var last: [String: Any]?
        if let e = entries.max(by: { $0.createdAt < $1.createdAt }) {
            var d: [String: Any] = ["name": e.name, "cal": e.cal * e.servings, "at": e.createdAt.timeIntervalSince1970]
            if let t = Self.watchThumb(e.photo) { d["thumb"] = t }
            last = d
        }

        // Burned today from Apple Health (Whoop + Apple Watch); the goal grows by the eat-back share you chose.
        let health = FoodHealth.shared
        let burn = health.showing ? health.active : 0
        let eatBack = Double(UserDefaults.standard.integer(forKey: "eatBackPct"))
        let goal = (UserDefaults.standard.object(forKey: "goal") as? Double ?? 2200) + burn * eatBack / 100
        var state: [String: Any] = ["day": today, "cal": total(\.cal), "goal": goal, "burn": burn,
                                    "p": total(\.protein), "c": total(\.carbs), "f": total(\.fat), "caf": total(\.caffeine),
                                    "quick": quick, "supps": suppList]
        if let last { state["last"] = last }

        // Stay well under WatchConnectivity's size limits: drop photos if the payload gets big.
        if Self.size(of: state) > 60_000 {
            state["quick"] = quick.map { q -> [String: Any] in var q = q; q["thumb"] = nil; return q }
            if var l = last { l["thumb"] = nil; state["last"] = l }
        }
        return state
    }

    /// 64×64 JPEG of an entry's photo for the watch.
    private static func watchThumb(_ data: Data?) -> Data? {
        guard let data, let img = UIImage(data: data) else { return nil }
        let side: CGFloat = 64
        let s = img.size
        guard s.width > 0, s.height > 0 else { return nil }
        let crop = min(s.width, s.height), scale = side / crop
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            img.draw(in: CGRect(x: -(s.width - crop) / 2 * scale, y: -(s.height - crop) / 2 * scale,
                                width: s.width * scale, height: s.height * scale))
        }
        return small.jpegData(compressionQuality: 0.5)
    }

    private static func size(of dict: [String: Any]) -> Int {
        (try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0))?.count ?? 0
    }

    // MARK: Commands from the watch

    fileprivate func handle(_ msg: [String: Any]) -> [String: Any] {
        guard let container, let cmd = msg["cmd"] as? String, let id = msg["id"] as? String else { return snapshot() }
        let ctx = container.mainContext
        let today = Day.key(Date())
        switch cmd {
        case "logQuick":
            if id.hasPrefix("qf:"), let q = QuickFood.all.first(where: { "qf:" + $0.name == id }) {
                ctx.insert(FoodEntry(name: q.name, cal: Double(q.cal), protein: q.p, carbs: q.c, fat: q.f,
                                     caffeine: Double(q.caf), meal: .now, day: today))
            } else {
                var fd = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.name == id },
                                                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                fd.fetchLimit = 1
                if let last = try? ctx.fetch(fd).first {
                    ctx.insert(FoodEntry(name: last.name, cal: last.cal, protein: last.protein, carbs: last.carbs, fat: last.fat,
                                         caffeine: last.caffeine, servings: last.servings, meal: .now, day: today, photo: last.photo))
                }
            }
        case "toggleSupp":
            guard let uuid = UUID(uuidString: id) else { break }
            let fd = FetchDescriptor<SuppDose>(predicate: #Predicate { $0.day == today && $0.suppID == uuid })
            if let existing = try? ctx.fetch(fd).first { ctx.delete(existing) }
            else { ctx.insert(SuppDose(suppID: uuid, day: today)) }
        default:
            break
        }
        try? ctx.save()
        return snapshot()
    }
}

extension FoodWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handle(message) }
    }

    /// Queued from the watch while the phone was out of reach.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in _ = self.handle(userInfo); self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            // An empty message is the watch asking for a refresh.
            replyHandler(message["cmd"] == nil ? self.snapshot() : self.handle(message))
        }
    }
}
