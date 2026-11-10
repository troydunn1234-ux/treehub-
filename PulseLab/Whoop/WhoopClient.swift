import Foundation
import Observation

/// Pulls everything from the WHOOP Developer API v2 and keeps a copy on disk,
/// so the app opens instantly (and offline) with the last sync.
@MainActor
@Observable
final class WhoopClient {
    static let shared = WhoopClient()

    private(set) var isConnected = false
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var isDemo = false

    private(set) var profile: WhoopProfile?
    private(set) var body: WhoopBody?
    /// Newest first.
    private(set) var cycles: [WhoopCycle] = []
    private(set) var recoveries: [WhoopRecovery] = []
    private(set) var sleeps: [WhoopSleep] = []
    private(set) var workouts: [WhoopWorkout] = []

    /// One line per request, newest first (last 20), so Settings → Data check can show what the API said.
    struct SyncEntry: Identifiable {
        let id = UUID()
        let time: Date
        let path: String
        let status: Int      // HTTP status, 0 = no response (network)
        var count: Int?      // records in this page, when it was a collection page
        var note: String = ""
        var ok: Bool { status == 200 }
    }
    private(set) var log: [SyncEntry] = []
    private func record(_ e: SyncEntry) { log.insert(e, at: 0); if log.count > 20 { log.removeLast(log.count - 20) } }

    @ObservationIgnored private let base = "https://api.prod.whoop.com/developer"
    private var auth: WhoopAuth { WhoopAuth.shared }

    init() {
        isConnected = auth.isConnected
        loadCache()
        if ProcessInfo.processInfo.arguments.contains("-demo") { demo() }
    }

    // MARK: connect

    func connect() async {
        lastError = nil
        do {
            try await auth.connect()
            isConnected = true
            await sync()
        } catch {
            lastError = error.localizedDescription
            isConnected = auth.isConnected
        }
    }

    func disconnect() {
        auth.disconnect()
        isConnected = false
        profile = nil; body = nil
        cycles = []; recoveries = []; sleeps = []; workouts = []
        lastSync = nil
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    // MARK: sync

    func sync(days: Int = 30) async {
        guard !isDemo else { return }
        guard auth.isConnected else { isConnected = false; return }
        guard !isSyncing else { return }
        isSyncing = true; lastError = nil
        defer { isSyncing = false }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end.addingTimeInterval(Double(-days) * 86400)
        do {
            profile = try? await get("/v2/user/profile/basic", as: WhoopProfile.self)
            body = try? await get("/v2/user/measurement/body", as: WhoopBody.self)
            cycles = try await collect("/v2/cycle", start: start, end: end, as: WhoopCycle.self)
                .sorted { $0.start > $1.start }
            recoveries = try await collect("/v2/recovery", start: start, end: end, as: WhoopRecovery.self)
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            sleeps = try await collect("/v2/activity/sleep", start: start, end: end, as: WhoopSleep.self)
                .sorted { $0.start > $1.start }
            workouts = try await collect("/v2/activity/workout", start: start, end: end, as: WhoopWorkout.self)
                .sorted { $0.start > $1.start }
            lastSync = Date()
            isConnected = true
            saveCache()
        } catch {
            lastError = error.localizedDescription
            isConnected = auth.isConnected
        }
    }

    // MARK: lookups for comparisons

    /// Recovery whose cycle started on this calendar day.
    func recovery(on day: Date) -> WhoopRecovery? {
        guard let c = cycles.first(where: { Calendar.current.isDate($0.start, inSameDayAs: day) }) else { return nil }
        return recoveries.first { $0.cycleId == c.id }
    }
    func cycle(on day: Date) -> WhoopCycle? { cycles.first { Calendar.current.isDate($0.start, inSameDayAs: day) } }
    /// Main (non-nap) sleep that ended on this day.
    func sleep(endingOn day: Date) -> WhoopSleep? {
        sleeps.first { $0.nap != true && Calendar.current.isDate($0.end, inSameDayAs: day) }
    }
    func workouts(on day: Date) -> [WhoopWorkout] { workouts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) } }

    // MARK: networking

    enum APIError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(0, let m): return m.isEmpty ? "WHOOP: no connection." : m
            case .http(401, _): return "WHOOP sign-in expired. Connect again."
            case .http(let c, let m): return "WHOOP error \(c)" + (m.isEmpty ? "" : ": \(m)")
            }
        }
    }

    private func collect<T: Codable>(_ path: String, start: Date, end: Date, as type: T.Type) async throws -> [T] {
        var out: [T] = []
        var next: String? = nil
        var pages = 0
        repeat {
            var q = [URLQueryItem(name: "limit", value: "25"),
                     URLQueryItem(name: "start", value: WhoopJSON.isoString(start)),
                     URLQueryItem(name: "end", value: WhoopJSON.isoString(end))]
            if let next { q.append(URLQueryItem(name: "nextToken", value: next)) }
            let page = try await get(path, query: q, as: WhoopPage<T>.self)
            if !log.isEmpty { log[0].count = page.records.count }
            out += page.records
            next = (page.nextToken?.isEmpty == false) ? page.nextToken : nil
            pages += 1
        } while next != nil && pages < 40
        return out
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        var comps = URLComponents(string: base + path)!
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.http(0, "bad URL") }

        var refreshed = false
        var backoffs = 0
        while true {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let result: (Data, URLResponse)
            do {
                result = try await URLSession.shared.data(for: req)
            } catch {
                record(SyncEntry(time: Date(), path: path, status: 0, note: error.localizedDescription))
                throw APIError.http(0, "No connection: \(error.localizedDescription)")
            }
            let data = result.0
            let http = result.1 as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            switch code {
            case 200:
                do {
                    let value = try WhoopJSON.decoder.decode(T.self, from: data)
                    record(SyncEntry(time: Date(), path: path, status: 200))
                    return value
                } catch {
                    record(SyncEntry(time: Date(), path: path, status: 200, note: "Couldn't read reply: \(error.localizedDescription)"))
                    throw APIError.http(200, "Unexpected reply shape for \(path)")
                }
            case 401 where !refreshed:
                refreshed = true
                try await auth.refresh()
            case 429 where backoffs < 4:
                backoffs += 1
                let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? Double(2 << backoffs)
                try await Task.sleep(nanoseconds: UInt64(min(max(wait, 1), 60) * 1_000_000_000))
            case 500...599 where backoffs < 2:
                backoffs += 1
                try await Task.sleep(nanoseconds: 1_500_000_000)
            default:
                if code == 401 { auth.disconnect(); isConnected = false }
                let msg = String(decoding: data.prefix(160), as: UTF8.self)
                record(SyncEntry(time: Date(), path: path, status: code, note: msg))
                throw APIError.http(code, msg)
            }
        }
    }

    // MARK: cache

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("whoop-cache.json")
    }

    private func saveCache() {
        let snap = WhoopSnapshot(profile: profile, body: body, cycles: cycles, recoveries: recoveries,
                                 sleeps: sleeps, workouts: workouts, lastSync: lastSync)
        if let data = try? WhoopJSON.cacheEncoder.encode(snap) {
            try? data.write(to: Self.cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let snap = try? WhoopJSON.decoder.decode(WhoopSnapshot.self, from: data) else { return }
        profile = snap.profile; body = snap.body
        cycles = snap.cycles; recoveries = snap.recoveries
        sleeps = snap.sleeps; workouts = snap.workouts
        lastSync = snap.lastSync
    }

    // MARK: demo

    /// 30 days of realistic fake data (no network) for screenshots.
    func demo() {
        isDemo = true
        isConnected = true
        lastSync = Date()
        profile = WhoopProfile(userId: 1, email: nil, firstName: "Troy", lastName: nil)
        body = WhoopBody(heightMeter: 1.80, weightKilogram: 80, maxHeartRate: 194)
        var rng = SeededRandom(seed: 42)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cs: [WhoopCycle] = [], rs: [WhoopRecovery] = [], ss: [WhoopSleep] = [], ws: [WhoopWorkout] = []
        let sports = ["running", "weightlifting", "cycling", "basketball", "walking", "functional-fitness"]
        for d in 0..<30 {
            let day = cal.date(byAdding: .day, value: -d, to: today)!
            let cycleStart = day.addingTimeInterval(-1.5 * 3600 + rng.next(-1800, 1800))   // ~10:30pm previous night
            let cid = 1000 + (30 - d)
            let strain = rng.next(6, 18.5)
            cs.append(WhoopCycle(id: cid, start: cycleStart, end: d == 0 ? nil : cycleStart.addingTimeInterval(86400),
                                 scoreState: "SCORED",
                                 score: .init(strain: strain, kilojoule: rng.next(8500, 14500),
                                              averageHeartRate: Int(rng.next(62, 78)), maxHeartRate: Int(rng.next(150, 188)))))
            let sleepStart = day.addingTimeInterval(-1 * 3600 + rng.next(-2400, 2400))
            let inBed = rng.next(6.2, 9.0) * 3600
            let awake = rng.next(0.3, 0.9) * 3600
            let asleep = inBed - awake
            let deep = asleep * rng.next(0.17, 0.25), rem = asleep * rng.next(0.20, 0.27)
            let sid = "demo-sleep-\(d)"
            ss.append(WhoopSleep(id: sid, cycleId: cid, start: sleepStart, end: sleepStart.addingTimeInterval(inBed), nap: false,
                                 scoreState: "SCORED",
                                 score: .init(stageSummary: .init(totalInBedTimeMilli: inBed * 1000, totalAwakeTimeMilli: awake * 1000,
                                                                  totalNoDataTimeMilli: 0,
                                                                  totalLightSleepTimeMilli: (asleep - deep - rem) * 1000,
                                                                  totalSlowWaveSleepTimeMilli: deep * 1000, totalRemSleepTimeMilli: rem * 1000,
                                                                  sleepCycleCount: Int(rng.next(3, 6)), disturbanceCount: Int(rng.next(4, 14))),
                                              sleepNeeded: .init(baselineMilli: 8 * 3_600_000, needFromSleepDebtMilli: rng.next(0, 2_400_000),
                                                                 needFromRecentStrainMilli: rng.next(0, 1_800_000), needFromRecentNapMilli: 0),
                                              respiratoryRate: rng.next(14.2, 16.4),
                                              sleepPerformancePercentage: rng.next(68, 99),
                                              sleepConsistencyPercentage: rng.next(55, 92),
                                              sleepEfficiencyPercentage: rng.next(84, 96))))
            let hrv = rng.next(38, 92)
            rs.append(WhoopRecovery(cycleId: cid, sleepId: sid, createdAt: sleepStart.addingTimeInterval(inBed),
                                    updatedAt: sleepStart.addingTimeInterval(inBed), scoreState: "SCORED",
                                    score: .init(userCalibrating: false, recoveryScore: min(99, max(8, (hrv - 30) * 1.4 + rng.next(-10, 10))),
                                                 restingHeartRate: rng.next(48, 62), hrvRmssdMilli: hrv,
                                                 spo2Percentage: rng.next(95, 99), skinTempCelsius: rng.next(33.2, 34.6))))
            if rng.next(0, 1) < 0.7 {
                let ws0 = day.addingTimeInterval(rng.next(7, 19) * 3600)
                let mins = rng.next(25, 85)
                let z = [0.05, 0.2, 0.3, 0.25, 0.15, 0.05].map { $0 * mins * 60_000 }
                ws.append(WhoopWorkout(id: "demo-w-\(d)", start: ws0, end: ws0.addingTimeInterval(mins * 60),
                                       sportName: sports[Int(rng.next(0, Double(sports.count) - 0.01))], sportId: nil, scoreState: "SCORED",
                                       score: .init(strain: rng.next(6, 16), averageHeartRate: Int(rng.next(115, 152)),
                                                    maxHeartRate: Int(rng.next(160, 189)), kilojoule: rng.next(900, 3200),
                                                    percentRecorded: 100, distanceMeter: rng.next(0, 9000),
                                                    altitudeGainMeter: rng.next(0, 120), altitudeChangeMeter: nil,
                                                    zoneDurations: .init(zoneZeroMilli: z[0], zoneOneMilli: z[1], zoneTwoMilli: z[2],
                                                                         zoneThreeMilli: z[3], zoneFourMilli: z[4], zoneFiveMilli: z[5]))))
            }
        }
        cycles = cs; recoveries = rs; sleeps = ss; workouts = ws
    }
}

/// Small deterministic RNG so demo data looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let u = Double(state >> 11) / Double(1 << 53)
        return lo + (hi - lo) * u
    }
}
