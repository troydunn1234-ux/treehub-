import Foundation

// WHOOP Developer API v2 models. Every field is optional where WHOOP may omit it
// (scores are missing until score_state == "SCORED"). Keys are snake_case in JSON;
// the decoder uses .convertFromSnakeCase, so properties are camelCase.

struct WhoopPage<T: Codable>: Codable {
    var records: [T]
    var nextToken: String?
}

struct WhoopProfile: Codable, Equatable {
    var userId: Int?
    var email: String?
    var firstName: String?
    var lastName: String?
    var name: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ") }
}

struct WhoopBody: Codable, Equatable {
    var heightMeter: Double?
    var weightKilogram: Double?
    var maxHeartRate: Int?
}

struct WhoopCycle: Codable, Identifiable, Equatable {
    var id: Int
    var start: Date
    var end: Date?
    var scoreState: String?
    var score: Score?

    struct Score: Codable, Equatable {
        var strain: Double?
        var kilojoule: Double?
        var averageHeartRate: Int?
        var maxHeartRate: Int?
    }

    /// Calories burned over the cycle (kJ → kcal).
    var kcal: Double? { score?.kilojoule.map { $0 / 4.184 } }
}

struct WhoopRecovery: Codable, Identifiable, Equatable {
    var cycleId: Int
    var sleepId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var scoreState: String?
    var score: Score?
    var id: Int { cycleId }

    struct Score: Codable, Equatable {
        var userCalibrating: Bool?
        var recoveryScore: Double?
        var restingHeartRate: Double?
        var hrvRmssdMilli: Double?
        var spo2Percentage: Double?
        var skinTempCelsius: Double?
    }
}

struct WhoopSleep: Codable, Identifiable, Equatable {
    var id: String
    var cycleId: Int?
    var start: Date
    var end: Date
    var nap: Bool?
    var scoreState: String?
    var score: Score?

    struct Score: Codable, Equatable {
        var stageSummary: StageSummary?
        var sleepNeeded: SleepNeeded?
        var respiratoryRate: Double?
        var sleepPerformancePercentage: Double?
        var sleepConsistencyPercentage: Double?
        var sleepEfficiencyPercentage: Double?
    }

    struct StageSummary: Codable, Equatable {
        var totalInBedTimeMilli: Double?
        var totalAwakeTimeMilli: Double?
        var totalNoDataTimeMilli: Double?
        var totalLightSleepTimeMilli: Double?
        var totalSlowWaveSleepTimeMilli: Double?
        var totalRemSleepTimeMilli: Double?
        var sleepCycleCount: Int?
        var disturbanceCount: Int?
    }

    struct SleepNeeded: Codable, Equatable {
        var baselineMilli: Double?
        var needFromSleepDebtMilli: Double?
        var needFromRecentStrainMilli: Double?
        var needFromRecentNapMilli: Double?
    }

    /// Time actually asleep (light + deep + REM), in hours.
    var asleepHours: Double? {
        guard let s = score?.stageSummary else { return nil }
        let ms = (s.totalLightSleepTimeMilli ?? 0) + (s.totalSlowWaveSleepTimeMilli ?? 0) + (s.totalRemSleepTimeMilli ?? 0)
        return ms > 0 ? ms / 3_600_000 : nil
    }
    var inBedHours: Double { end.timeIntervalSince(start) / 3600 }
}

struct WhoopWorkout: Codable, Identifiable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var sportName: String?
    var sportId: Int?
    var scoreState: String?
    var score: Score?

    struct Score: Codable, Equatable {
        var strain: Double?
        var averageHeartRate: Int?
        var maxHeartRate: Int?
        var kilojoule: Double?
        var percentRecorded: Double?
        var distanceMeter: Double?
        var altitudeGainMeter: Double?
        var altitudeChangeMeter: Double?
        var zoneDurations: Zones?
    }

    struct Zones: Codable, Equatable {
        var zoneZeroMilli: Double?
        var zoneOneMilli: Double?
        var zoneTwoMilli: Double?
        var zoneThreeMilli: Double?
        var zoneFourMilli: Double?
        var zoneFiveMilli: Double?
        /// Minutes in zones 0…5.
        var minutes: [Double] {
            [zoneZeroMilli, zoneOneMilli, zoneTwoMilli, zoneThreeMilli, zoneFourMilli, zoneFiveMilli].map { ($0 ?? 0) / 60_000 }
        }
    }

    var kcal: Double? { score?.kilojoule.map { $0 / 4.184 } }
    var minutes: Double { end.timeIntervalSince(start) / 60 }
    var displayName: String {
        if let n = sportName, !n.isEmpty { return n.replacingOccurrences(of: "-", with: " ").capitalized }
        return "Workout"
    }
}

/// Everything WHOOP gave us, cached to disk as one file.
struct WhoopSnapshot: Codable {
    var profile: WhoopProfile?
    var body: WhoopBody?
    var cycles: [WhoopCycle] = []
    var recoveries: [WhoopRecovery] = []
    var sleeps: [WhoopSleep] = []
    var workouts: [WhoopWorkout] = []
    var lastSync: Date?
}

enum WhoopJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self) {
                if let date = isoFrac.date(from: s) ?? iso.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
            }
            return Date(timeIntervalSince1970: try c.decode(Double.self))
        }
        return d
    }()

    /// For the on-disk cache (our own format).
    static let cacheEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(isoFrac.string(from: date))
        }
        return e
    }()

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func isoString(_ d: Date) -> String { isoFrac.string(from: d) }
}
