import Foundation

/// Turns raw sleep-analysis samples (already split by tracker) into one honest night per morning.
///
/// What Apple Health hands us is messy on purpose: every writer adds its own samples, an Apple Watch writes
/// staged samples (core / deep / REM / awake), older software writes one long "asleep", two Watches (an old
/// and a new one) can both write the same night, the iPhone writes "in bed" from the Sleep schedule, and a
/// nap is just more "asleep". Adding all of those minutes together is how a 7 h night turned into 12.8 h.
///
/// The rules here:
/// 1. Time asleep is the **union** of every asleep interval (core, deep, REM, unspecified), never the sum, so
///    overlapping samples from several writers or a duplicated "unspecified" layer count once.
/// 2. Each instant gets exactly one stage (deep > REM > core > unspecified > awake > in bed), so stages add up
///    to the night instead of overlapping.
/// 3. Asleep intervals less than `sessionGap` apart form one session. A night is credited to the morning it
///    ended (`nightKey`); when a morning has several sessions only the main (longest) one is the night — naps
///    don't inflate it.
/// 4. "Awake" is only counted inside the session, and "time in bed" is everything the tracker covered there.
enum SleepMath {
    /// One raw sample from one tracker.
    struct Sample: Equatable {
        enum Stage: Int, Comparable {
            // Ordered by priority: when samples overlap, the higher one wins that instant.
            case inBed = 0, awake, unspecified, core, rem, deep
            static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
            var isAsleep: Bool { self >= .unspecified }
        }
        let start: Date
        let end: Date
        let stage: Stage
    }

    /// One morning's main sleep plus its stage-by-stage timeline.
    struct Night {
        var night: SleepNight
        var segments: [HypnoSegment]
        /// Asleep minutes in other, smaller sessions credited to the same morning (naps), left out of `night`.
        var otherSessionsMin: Double
    }

    /// Asleep intervals further apart than this are separate sessions (a nap and the night, two nights).
    static let sessionGap: TimeInterval = 3 * 3600
    /// "Awake" / "in bed" samples are only counted this close to the session's asleep span.
    static let edge: TimeInterval = 2 * 3600

    /// Nights are credited to the morning you woke up: a session ending at or after 6 pm counts toward tomorrow.
    static func nightKey(_ end: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: end)
        guard calendar.component(.hour, from: end) >= 18 else { return day }
        return calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    /// Every night in `samples` (all from one tracker), oldest first.
    static func nights(_ samples: [Sample], source: Source, calendar: Calendar = .current) -> [Night] {
        let valid = samples.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        let asleep = valid.filter { $0.stage.isAsleep }.sorted { $0.start < $1.start }
        guard !asleep.isEmpty else { return [] }

        // 1. Sessions: clusters of asleep intervals.
        var sessions: [(start: Date, end: Date)] = []
        for s in asleep {
            if let last = sessions.last, s.start.timeIntervalSince(last.end) <= sessionGap {
                sessions[sessions.count - 1].end = max(last.end, s.end)
            } else {
                sessions.append((s.start, s.end))
            }
        }

        // 2. Resolve each session into one stage per instant.
        var built: [(key: Date, night: SleepNight, segments: [HypnoSegment], asleep: Double)] = []
        for sess in sessions {
            let lo = sess.start.addingTimeInterval(-edge), hi = sess.end.addingTimeInterval(edge)
            // `valid` is sorted by start: skip straight to samples that can touch this session (none lasts a day).
            var i0 = 0, i1 = valid.count
            let from = lo.addingTimeInterval(-86_400)
            while i0 < i1 { let m = (i0 + i1) / 2; if valid[m].start < from { i0 = m + 1 } else { i1 = m } }
            var near: [Sample] = []
            var j = i0
            while j < valid.count, valid[j].start < hi { near.append(valid[j]); j += 1 }
            let mine = near.filter { s in
                if s.stage.isAsleep { return s.start < sess.end.addingTimeInterval(1) && s.end > sess.start.addingTimeInterval(-1) }
                return s.end > lo && s.start < hi
            }.map { Sample(start: max($0.start, lo), end: min($0.end, hi), stage: $0.stage) }
            let timeline = resolve(mine)
            let key = nightKey(sess.end, calendar: calendar)
            var n = SleepNight(night: key, source: source)
            n.start = sess.start
            n.end = sess.end
            var covered = 0.0
            for seg in timeline {
                let m = seg.end.timeIntervalSince(seg.start) / 60
                covered += m
                switch seg.stage {
                case .deep: n.deepMin += m
                case .rem: n.remMin += m
                case .core: n.coreMin += m
                case .unspecified: n.unspecifiedMin += m
                case .awake: n.awakeMin += m
                case .inBed: break
                }
            }
            n.inBedMin = covered
            let segs: [HypnoSegment] = timeline.compactMap { seg in
                let st: SleepStage
                switch seg.stage {
                case .deep: st = .deep
                case .rem: st = .rem
                case .core, .unspecified: st = .core
                case .awake: st = .awake
                case .inBed: return nil
                }
                return HypnoSegment(start: seg.start, end: seg.end, stage: st)
            }
            built.append((key, n, mergeAdjacent(segs), n.asleepMin))
        }

        // 3. One night per morning: the main session; the rest are naps.
        let byKey = Dictionary(grouping: built, by: { $0.key })
        return byKey.values.compactMap { group -> Night? in
            guard let main = group.max(by: { $0.asleep < $1.asleep }) else { return nil }
            let others = group.map { $0.asleep }.reduce(0, +) - main.asleep
            return Night(night: main.night, segments: main.segments, otherSessionsMin: others)
        }
        .sorted { $0.night.night < $1.night.night }
    }

    /// Splits overlapping samples at every boundary and keeps the highest-priority stage in each piece.
    static func resolve(_ samples: [Sample]) -> [Sample] {
        guard !samples.isEmpty else { return [] }
        let cuts = Array(Set(samples.flatMap { [$0.start, $0.end] })).sorted()
        var out: [Sample] = []
        for i in 0..<(cuts.count - 1) {
            let a = cuts[i], b = cuts[i + 1]
            var best: Sample.Stage?
            for s in samples where s.start <= a && s.end >= b {
                if best == nil || s.stage > best! { best = s.stage }
            }
            guard let best else { continue }
            if let last = out.last, last.stage == best, last.end == a {
                out[out.count - 1] = Sample(start: last.start, end: b, stage: best)
            } else {
                out.append(Sample(start: a, end: b, stage: best))
            }
        }
        return out
    }

    private static func mergeAdjacent(_ segs: [HypnoSegment]) -> [HypnoSegment] {
        var out: [HypnoSegment] = []
        for s in segs {
            if let last = out.last, last.stage == s.stage, last.end == s.start {
                out[out.count - 1] = HypnoSegment(start: last.start, end: s.end, stage: s.stage)
            } else {
                out.append(s)
            }
        }
        return out
    }
}
