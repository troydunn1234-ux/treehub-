import Foundation

/// The only file that knows WHOOP's API models. Maps them onto Pulse Lab's neutral types.
@MainActor
enum WhoopAdapter {
    static var client: WhoopClient { WhoopClient.shared }
    static var connected: Bool { client.isConnected }
    static var lastSync: Date? { client.lastSync }

    static func sync(days: Int = 90) async { await client.sync(days: days) }
    static func demo() { client.demo() }

    /// Per-day numbers from the WHOOP API: recovery, resting HR, HRV (RMSSD), SpO2, skin temp deviation,
    /// day strain and calories (kJ → kcal), plus respiratory rate from that night's sleep.
    static func days() -> [DayStat] {
        var out: [Date: DayStat] = [:]
        for c in client.cycles {
            // A WHOOP cycle runs wake-to-wake; label it with the day it started.
            let d = c.start.dayStart
            var s = out[d] ?? DayStat(day: d)
            s.strain = c.score?.strain
            if let kcal = c.kcal { s.activeKcal = nil; s.basalKcal = nil; s.totalKcalWhoop = kcal }
            s.avgHR = c.score?.averageHeartRate.map { Double($0) }
            out[d] = s
        }
        // Recovery belongs to the morning it was scored (the day you woke up).
        let byCycle = Dictionary(client.cycles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in client.recoveries {
            guard let sc = r.score else { continue }
            let when = r.createdAt ?? byCycle[r.cycleId]?.start ?? Date()
            let d = when.dayStart
            var s = out[d] ?? DayStat(day: d)
            s.recovery = sc.recoveryScore
            s.rhr = sc.restingHeartRate
            s.hrv = sc.hrvRmssdMilli
            s.spo2 = sc.spo2Percentage
            s.skinTempC = sc.skinTempCelsius
            out[d] = s
        }
        for sl in client.sleeps where sl.nap != true {
            let d = HealthPull.nightKey(sl.end)
            var s = out[d] ?? DayStat(day: d)
            s.resp = sl.score?.respiratoryRate ?? s.resp
            out[d] = s
        }
        // Skin temperature → deviation from your own 30-day average, so it lines up with the Watch's wrist temp.
        let temps = out.values.compactMap(\.skinTempC)
        if !temps.isEmpty {
            let base = temps.reduce(0, +) / Double(temps.count)
            for k in out.keys { if let t = out[k]?.skinTempC { out[k]?.tempDev = t - base } }
        }
        return out.values.sorted { $0.day < $1.day }
    }

    static func sleeps() -> [SleepNight] {
        client.sleeps.filter { $0.nap != true }.compactMap { sl in
            guard let st = sl.score?.stageSummary else { return nil }
            var n = SleepNight(night: HealthPull.nightKey(sl.end), source: .whoop)
            n.start = sl.start
            n.end = sl.end
            n.inBedMin = (st.totalInBedTimeMilli ?? 0) / 60_000
            n.awakeMin = (st.totalAwakeTimeMilli ?? 0) / 60_000
            n.coreMin = (st.totalLightSleepTimeMilli ?? 0) / 60_000
            n.deepMin = (st.totalSlowWaveSleepTimeMilli ?? 0) / 60_000
            n.remMin = (st.totalRemSleepTimeMilli ?? 0) / 60_000
            n.performance = sl.score?.sleepPerformancePercentage
            n.respRate = sl.score?.respiratoryRate
            return n
        }
        .sorted { $0.night < $1.night }
    }

    static func workouts() -> [WorkoutRec] {
        client.workouts.map { w in
            WorkoutRec(id: "whoop-\(w.id)", source: .whoop, name: w.displayName, symbol: "bolt.heart.fill",
                       start: w.start, end: w.end, kcal: w.kcal,
                       avgHR: w.score?.averageHeartRate.map { Double($0) },
                       maxHR: w.score?.maxHeartRate.map { Double($0) },
                       strain: w.score?.strain,
                       distanceKm: w.score?.distanceMeter.map { $0 / 1000 })
        }
    }

    static var profileName: String? {
        let n = client.profile?.name ?? ""
        return n.isEmpty ? nil : n
    }
}
