import Foundation

/// Believable fake data for screenshots and the simulator (no HealthKit, no network).
enum DemoData {
    struct Pack { var watch: [DayStat]; var whoop: [DayStat]; var sleeps: [SleepNight]; var hypnogram: [HypnoSegment]; var workouts: [WorkoutRec] }

    /// Small deterministic random generator so screenshots look the same every run.
    struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double((s >> 33) % 10_000) / 10_000 } }

    static func make(days: Int = 90) -> Pack {
        var r = RNG(s: 42)
        func n(_ sd: Double) -> Double { (r.next() + r.next() + r.next() - 1.5) * sd * 1.15 }
        var watch: [DayStat] = [], whoop: [DayStat] = [], sleeps: [SleepNight] = [], workouts: [WorkoutRec] = []
        let today = Date().dayStart
        var fitness = 0.0
        for i in stride(from: days - 1, through: 0, by: -1) {
            let day = today.adding(days: -i)
            fitness += 0.02
            let stress = sin(Double(i) / 5.3) * 0.8 + n(0.6)          // shared "true" body state
            let trueRHR = 56 - fitness * 0.04 + stress * 2.2
            let trueHRV = 62 + fitness * 0.08 - stress * 9
            let sleepH = 7.1 - stress * 0.35 + n(0.45)

            var w = DayStat(day: day)
            w.rhr = (trueRHR + 1.2 + n(1.2)).rounded()
            w.hrv = max(20, trueHRV * 0.82 + n(5))            // SDNN tends to read lower than RMSSD here
            w.resp = 14.6 + stress * 0.25 + n(0.3)
            w.spo2 = min(100, 96.8 + n(0.8))
            w.tempDev = stress * 0.15 + n(0.12)
            w.activeKcal = max(180, 620 + n(170) - stress * 40)
            w.basalKcal = 1760 + n(25)
            w.steps = max(2500, 9400 + n(2600))
            w.distanceKm = (w.steps ?? 0) * 0.00076
            w.flights = max(0, 9 + n(5)).rounded()
            w.exerciseMin = max(5, 42 + n(22))
            w.standMin = max(120, 640 + n(90))
            w.daylightMin = max(5, 48 + n(30))
            w.vo2 = 44.5 + fitness * 0.01 + n(0.4)
            w.weightKg = 84.5 - fitness * 0.012 + n(0.25)
            w.walkHR = 98 + stress * 2 + n(2)
            w.avgHR = 72 + stress * 2 + n(2)
            watch.append(w)

            var h = DayStat(day: day)
            h.rhr = (trueRHR + n(1.0)).rounded()
            h.hrv = max(22, trueHRV + n(6))
            h.resp = 14.9 + stress * 0.25 + n(0.25)
            h.spo2 = min(100, 95.9 + n(0.9))
            h.tempDev = stress * 0.14 + n(0.1)
            h.totalKcalWhoop = 2290 + n(260) - stress * 30
            h.strain = max(4, min(19.5, 11.5 + n(3)))
            h.recovery = max(8, min(99, 62 - stress * 22 + n(8))).rounded()
            whoop.append(h)

            var sw = SleepNight(night: day, source: .watch)
            let asleep = max(4.6, sleepH) * 60
            sw.start = day.addingTimeInterval(-60 * 60 * 1.7)
            sw.end = sw.start!.addingTimeInterval(asleep * 60 + 30 * 60)
            sw.deepMin = asleep * (0.15 + n(0.02)); sw.remMin = asleep * (0.22 + n(0.03)); sw.coreMin = asleep - sw.deepMin - sw.remMin
            sw.awakeMin = 18 + abs(n(8)); sw.inBedMin = asleep + sw.awakeMin + 9
            sleeps.append(sw)
            var sh = SleepNight(night: day, source: .whoop)
            let asleepH = asleep + n(14)
            sh.start = sw.start; sh.end = sw.end
            sh.deepMin = asleepH * (0.2 + n(0.03)); sh.remMin = asleepH * (0.24 + n(0.03)); sh.coreMin = asleepH - sh.deepMin - sh.remMin
            sh.awakeMin = 24 + abs(n(9)); sh.inBedMin = asleepH + sh.awakeMin
            sh.performance = max(40, min(100, asleepH / 60 / 8 * 100))
            sh.respRate = h.resp
            sleeps.append(sh)

            if i % 2 == 0 || i % 7 == 3 {
                let kinds: [(String, String)] = [("Strength", "dumbbell.fill"), ("Run", "figure.run"), ("Ride", "figure.outdoor.cycle"), ("HIIT", "bolt.heart.fill")]
                let k = kinds[(days - i) % kinds.count]
                let st = day.addingTimeInterval(60 * 60 * 17.5)
                let mins = 38 + n(12)
                let en = st.addingTimeInterval(mins * 60)
                let kcal = mins * 9.2 + n(40)
                workouts.append(WorkoutRec(id: "w\(i)", source: .watch, name: k.0, symbol: k.1, start: st, end: en, kcal: kcal,
                                           avgHR: 138 + n(8), maxHR: 171 + n(6), strain: nil, distanceKm: k.0 == "Run" ? mins * 0.17 : nil))
                workouts.append(WorkoutRec(id: "h\(i)", source: .whoop, name: k.0, symbol: "bolt.heart.fill", start: st.addingTimeInterval(40), end: en.addingTimeInterval(-30),
                                           kcal: kcal * 1.08 + n(30), avgHR: 140 + n(7), maxHR: 173 + n(5), strain: max(6, 12.5 + n(2.5)), distanceKm: nil))
            }
        }
        // Last night's hypnogram.
        var hypno: [HypnoSegment] = []
        if let last = sleeps.last(where: { $0.source == .watch }), var t = last.start {
            let pattern: [(SleepStage, Double)] = [(.awake, 9), (.core, 24), (.deep, 38), (.core, 22), (.rem, 18), (.core, 30), (.deep, 26), (.core, 28),
                                                   (.rem, 26), (.awake, 4), (.core, 34), (.deep, 12), (.core, 26), (.rem, 34), (.core, 22), (.awake, 3),
                                                   (.core, 18), (.rem, 31), (.awake, 7)]
            for (stage, m) in pattern {
                let e = t.addingTimeInterval(m * 60)
                hypno.append(HypnoSegment(start: t, end: e, stage: stage)); t = e
            }
        }
        return Pack(watch: watch, whoop: whoop, sleeps: sleeps, hypnogram: hypno, workouts: workouts.sorted { $0.start > $1.start })
    }
}
