import Foundation
import HealthKit
import WatchKit

/// A finished hug from the Watch: what the iPhone logs under a tree.
struct WatchHugRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var avgHR: Double?
    var minHR: Double?
    var maxHR: Double?
    /// First and last heart-rate readings: start -> end shows how you settled.
    var startHR: Double?
    var endHR: Double?

    var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }

    /// The dictionary the iPhone reads (TreeHub/App/WatchHugs.swift uses the same keys).
    var payload: [String: Any] {
        var d: [String: Any] = ["rbWatchHug": 1, "id": id.uuidString,
                                "start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970]
        if let avgHR { d["avgHR"] = avgHR }
        if let minHR { d["minHR"] = minHR }
        if let maxHR { d["maxHR"] = maxHR }
        if let startHR { d["startHR"] = startHR }
        if let endHR { d["endHR"] = endHR }
        return d
    }
}

/// "Start hug": a Mind & Body workout session, so the Watch measures heart rate live for the whole hug.
@MainActor
final class HugWorkout: NSObject, ObservableObject {
    static let shared = HugWorkout()

    @Published private(set) var running = false
    @Published private(set) var startDate: Date?
    @Published private(set) var heartRate: Double?
    @Published private(set) var lastHug: WatchHugRecord?
    @Published var errorText = ""

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var readings: [Double] = []

    private var hrType: HKQuantityType { HKQuantityType(.heartRate) }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let read: Set<HKObjectType> = [hrType, HKQuantityType(.heartRateVariabilitySDNN), HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
            return true
        } catch {
            return false
        }
    }

    func start() async {
        guard !running else { return }
        errorText = ""
        guard await requestAuthorization() else {
            errorText = "Allow Health access in the Watch app to measure heart rate."
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .outdoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            readings = []
            heartRate = nil
            let now = Date()
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
            startDate = now
            running = true
            WKInterfaceDevice.current().play(.start)
        } catch {
            errorText = "Couldn't start: \(error.localizedDescription)"
            session = nil
            builder = nil
        }
    }

    /// Ends the hug, saves it to Health as a Mind & Body workout and returns the record (sent to the iPhone).
    @discardableResult
    func finish() async -> WatchHugRecord? {
        guard running, let start = startDate else { return nil }
        let end = Date()
        running = false
        session?.end()
        if let b = builder {
            try? await b.endCollection(at: end)
            _ = try? await b.finishWorkout()
        }
        WKInterfaceDevice.current().play(.stop)
        let v = readings
        let rec = WatchHugRecord(start: start, end: end,
                                 avgHR: v.isEmpty ? nil : (v.reduce(0, +) / Double(v.count)).rounded(),
                                 minHR: v.min()?.rounded(), maxHR: v.max()?.rounded(),
                                 startHR: v.first?.rounded(), endHR: v.last?.rounded())
        session = nil
        builder = nil
        startDate = nil
        lastHug = rec
        PhoneLink.shared.send(rec)
        return rec
    }

    /// Stop without keeping the hug.
    func discard() {
        guard running else { return }
        running = false
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        startDate = nil
        WKInterfaceDevice.current().play(.failure)
    }

    fileprivate func add(_ bpm: Double) {
        guard running, bpm > 25, bpm < 230 else { return }
        heartRate = bpm
        readings.append(bpm)
    }
}

extension HugWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in HugWorkout.shared.errorText = text }
    }
}

extension HugWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let q = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let bpm = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in HugWorkout.shared.add(bpm) }
    }
}
