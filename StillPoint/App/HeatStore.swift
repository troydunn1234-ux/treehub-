import Foundation
import SwiftUI
import UserNotifications

/// Sauna or steam room.
enum HeatKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case sauna, steam

    var id: String { rawValue }
    var title: String { self == .sauna ? "Sauna" : "Steam room" }
    var short: String { self == .sauna ? "Sauna" : "Steam" }
    var symbol: String { self == .sauna ? "flame.fill" : "cloud.fog.fill" }
    var tint: Color { self == .sauna ? Color(spHex: "#F29A5B") : Color(spHex: "#7FC8D9") }
    var tint2: Color { self == .sauna ? Color(spHex: "#C2474A") : Color(spHex: "#5B7FD6") }
    /// When to send the "time to step out?" nudge.
    var checkInMinutes: Int { self == .sauna ? 20 : 15 }
}

/// One heat session: a start and end time, plus the heart rate Apple Health had for that window.
struct HeatSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: HeatKind
    var start: Date
    var end: Date? = nil
    var heart: HeartWindow? = nil
    /// Last time we asked Apple Health for this window.
    var checked: Date? = nil

    var seconds: Double { (end ?? Date()).timeIntervalSince(start) }
    var minutes: Double { seconds / 60 }
}

/// Keeps the running heat session (so it survives leaving the app) and the heat log.
@MainActor
final class HeatStore: ObservableObject {
    static let shared = HeatStore()

    @Published private(set) var active: HeatSession?
    @Published private(set) var history: [HeatSession] = []

    private let key = "sp.heat.v1"
    private struct Saved: Codable { var active: HeatSession?; var history: [HeatSession] }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            active = saved.active
            history = saved.history
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(active: active, history: history)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Start timing. If another session is running it is finished first.
    func start(_ kind: HeatKind) {
        if active != nil { finish() }
        active = HeatSession(kind: kind, start: Date())
        save()
        scheduleCheckIn(kind)
    }

    /// Stop timing, keep it in the log and look up heart rate for the window.
    func finish() {
        guard var s = active else { return }
        s.end = Date()
        active = nil
        cancelCheckIn()
        // Under a minute is almost certainly a mis-tap.
        guard s.seconds >= 60 else { save(); return }
        history.insert(s, at: 0)
        save()
        lookUpHeart(s.id)
        // WHOOP often syncs a few minutes late; ask again shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in self?.lookUpHeart(s.id) }
    }

    func cancel() {
        active = nil
        cancelCheckIn()
        save()
    }

    func delete(_ id: UUID) {
        history.removeAll { $0.id == id }
        save()
    }

    /// Ask Apple Health for heart rate during this session.
    func lookUpHeart(_ id: UUID) {
        guard let s = history.first(where: { $0.id == id }), let end = s.end else { return }
        MindfulHealth.shared.heartRateStats(start: s.start, end: end) { [weak self] w in
            guard let self, let i = self.history.firstIndex(where: { $0.id == id }) else { return }
            if let w { self.history[i].heart = w }
            self.history[i].checked = Date()
            self.save()
        }
    }

    /// Re-check recent sessions that have no heart rate yet (WHOOP may have synced since).
    func refreshMissing() {
        let cutoff = Date().addingTimeInterval(-3 * 86_400)
        for s in history where s.heart == nil && s.start > cutoff { lookUpHeart(s.id) }
    }

    var thisWeekMinutes: Double {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return history.filter { $0.start > weekAgo }.reduce(0) { $0 + $1.minutes }
    }

    // MARK: - Step-out nudge

    private let noteID = "sp.heat.checkin"

    private func scheduleCheckIn(_ kind: HeatKind) {
        let center = UNUserNotificationCenter.current()
        let id = noteID
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "\(kind.checkInMinutes) minutes in the \(kind.short.lowercased())"
            c.body = "Time to step out, cool down and drink some water. Tap to end the session."
            c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(kind.checkInMinutes * 60), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        }
    }

    private func cancelCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [noteID])
    }
}
