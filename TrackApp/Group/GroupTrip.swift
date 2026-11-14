import Foundation
import CloudKit
import CoreLocation
import SwiftUI
import Combine
import UIKit

// "Go together": a live group activity with friends. Everyone records their own trip as usual
// (it still lands in History); while the group is on, each phone upserts its own Rider record in
// the CloudKit public database every few seconds and reads everyone else's.
//
// Record types (public database of iCloud.com.troydunn.roamr):
//   GroupTrip  recordName "trip-<code>"           code, kind, hostName, createdAt, endedAt?
//   Rider      recordName "rider-<code>-<riderID>" tripCode, riderID, name, lat, lon, speed (m/s),
//                                                  heading, kind, color (hex), updatedAt

/// Someone else in the group, as last uploaded.
struct RiderState: Identifiable, Equatable {
    let id: String          // riderID
    var name: String
    var latitude: Double
    var longitude: Double
    var speed: Double       // m/s
    var heading: Double     // degrees from north, -1 unknown
    var kind: ActivityKind
    var colorHex: String
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var color: Color { Color(groupHex: colorHex) }
    func age(_ now: Date = Date()) -> TimeInterval { max(0, now.timeIntervalSince(updatedAt)) }
    func isStale(_ now: Date = Date()) -> Bool { age(now) > 30 }
}

/// A trip someone invited you to, waiting for you to say yes.
struct GroupInvite: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let hostName: String
    let kind: ActivityKind
}

@MainActor
final class GroupSession: ObservableObject {
    static let shared = GroupSession()

    enum State: String { case idle, hosting, joined }

    // MARK: Published state

    @Published private(set) var state: State = .idle
    @Published private(set) var code: String?
    @Published private(set) var kind: ActivityKind = .drive
    @Published private(set) var hostName: String = ""
    /// Everyone else in the group (never includes you).
    @Published private(set) var riders: [RiderState] = []
    /// Something went wrong that the user should see (shown as an alert).
    @Published var lastError: String?
    /// Soft, self-healing problems (no signal etc.), shown inline on the live screen.
    @Published private(set) var connectionNote: String?
    /// Set when the host ended the trip for everyone ("Trip ended by Sam").
    @Published var endedNotice: String?
    /// "Sam joined" / "Sam left": a short toast on the live screen.
    @Published var toast: String?
    /// An invite from a link or a typed code, waiting for "Join?".
    @Published var pendingInvite: GroupInvite?
    /// Busy talking to iCloud for create / join.
    @Published private(set) var working = false
    /// Your display name for the group (persisted).
    @Published var myName: String {
        didSet { UserDefaults.standard.set(myName, forKey: Self.nameKey) }
    }

    var isActive: Bool { state != .idle }
    /// True until you've picked a display name once.
    var needsName: Bool { UserDefaults.standard.string(forKey: Self.nameKey) == nil }
    /// This phone's id in every group, random and kept forever.
    let riderID: String
    /// Your badge color.
    var myColorHex: String { Self.palette[abs(Self.stableHash(riderID)) % Self.palette.count] }
    /// The app started a recording for this group (so "Stop & save trip" is the natural way out).
    private(set) var startedTracking = false

    // MARK: Private

    private static let nameKey = "group.myName"
    private static let riderKey = "group.riderID"
    private static let safetyKey = "group.safetySeen"
    static let containerID = "iCloud.com.troydunn.roamr"
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no 0/O/1/I
    static let palette = ["#FF6B35", "#4FC3F7", "#9CCC65", "#FFD54F", "#BA68C8", "#F06292", "#4DB6AC", "#FF8A65"]

    private lazy var database: CKDatabase = CKContainer(identifier: Self.containerID).publicCloudDatabase
    private weak var tracker: RouteTracker?
    private var loop: Task<Void, Never>?
    private var tickCount = 0
    private var knownNames: [String: String] = [:]
    private var firstFetchDone = false

    private init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: Self.riderKey) {
            riderID = id
        } else {
            let id = UUID().uuidString
            d.set(id, forKey: Self.riderKey)
            riderID = id
        }
        myName = d.string(forKey: Self.nameKey) ?? "Me"
    }

    /// Called once from the app root so the group can read your live position and start recordings.
    func attach(tracker: RouteTracker) { self.tracker = tracker }

    /// Shown once: the driving-safety line on the live screen.
    var safetyNoteSeen: Bool {
        get { UserDefaults.standard.bool(forKey: Self.safetyKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.safetyKey) }
    }

    // MARK: Codes & links

    static func makeCode() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// Uppercases and keeps only characters a code can have ("k7q h2m" -> "K7QH2M").
    static func cleanCode(_ raw: String) -> String {
        let kept = raw.uppercased().filter { alphabet.contains($0) }
        return String(kept.prefix(6))
    }

    static func isValidCode(_ s: String) -> Bool { s.count == 6 && s.allSatisfy { alphabet.contains($0) } }

    static func shareURL(code: String, kind: ActivityKind) -> URL {
        var c = URLComponents(string: "https://troydunn1234-ux.github.io/treehub-/join/")!
        c.queryItems = [URLQueryItem(name: "c", value: code), URLQueryItem(name: "k", value: kind.rawValue)]
        return c.url!
    }

    func shareMessage() -> String {
        guard let code else { return "" }
        let link = Self.shareURL(code: code, kind: kind).absoluteString
        let lead: String
        switch kind {
        case .drive: lead = "Roll home with me on Roamr 🚗"
        case .walk: lead = "Walk with me on Roamr 🚶"
        case .run: lead = "Run with me on Roamr 🏃"
        case .hike: lead = "Hike with me on Roamr 🥾"
        case .bike: lead = "Ride with me on Roamr 🚲"
        }
        return "\(lead) Tap to join: \(link)  (or in Roamr: Go together › Join › \(code))"
    }

    /// Handles roamr://join?c=CODE&k=kind and the https join-page link. Returns true if it was a join link.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let isScheme = url.scheme?.lowercased() == "roamr" && (url.host?.lowercased() == "join" || url.path.lowercased().contains("join"))
        let isWeb = (url.scheme == "https" || url.scheme == "http") && url.path.lowercased().contains("/join")
        guard isScheme || isWeb else { return false }
        let raw = comps.queryItems?.first(where: { $0.name.lowercased() == "c" })?.value ?? ""
        let code = Self.cleanCode(raw)
        guard Self.isValidCode(code) else {
            lastError = "That invite link is missing its code. Ask your friend to send it again."
            return true
        }
        if code == self.code, isActive { return true }   // already in it
        Task { await prepareJoin(code: code) }
        return true
    }

    // MARK: Create / join / leave

    /// Starts a new group and your recording of it.
    func create(kind: ActivityKind) async {
        guard state == .idle, !working else { return }
        working = true
        defer { working = false }
        guard await iCloudReady() else { return }
        do {
            var newCode = Self.makeCode()
            // Rare clash with a live trip: pick another code.
            for _ in 0..<3 {
                if try await fetchTrip(code: newCode) == nil { break }
                newCode = Self.makeCode()
            }
            let rec = CKRecord(recordType: "GroupTrip", recordID: CKRecord.ID(recordName: "trip-\(newCode)"))
            rec["code"] = newCode as NSString
            rec["kind"] = kind.rawValue as NSString
            rec["hostName"] = myName as NSString
            rec["createdAt"] = Date() as NSDate
            _ = try await database.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys, atomically: true)
            begin(code: newCode, kind: kind, host: myName, as: .hosting)
        } catch {
            lastError = friendly(error, action: "start the group")
        }
    }

    /// Looks up a code and, if the trip is live, asks "Join <host>'s group drive?".
    func prepareJoin(code raw: String) async {
        let code = Self.cleanCode(raw)
        guard Self.isValidCode(code) else {
            lastError = "Codes are 6 letters and numbers, like K7QH2M."
            return
        }
        guard !working else { return }
        working = true
        defer { working = false }
        guard await iCloudReady() else { return }
        do {
            guard let trip = try await fetchTrip(code: code) else {
                lastError = "No group with code \(code). Check the code with your friend."
                return
            }
            if trip["endedAt"] as? Date != nil {
                let host = (trip["hostName"] as? String) ?? "the host"
                lastError = "That trip already ended (\(host) ended it)."
                return
            }
            let kind = ActivityKind(rawValue: (trip["kind"] as? String) ?? "") ?? .drive
            let host = (trip["hostName"] as? String) ?? "Your friend"
            pendingInvite = GroupInvite(code: code, hostName: host, kind: kind)
        } catch {
            lastError = friendly(error, action: "find that group")
        }
    }

    /// "Join" on the invite prompt.
    func accept(_ invite: GroupInvite) {
        pendingInvite = nil
        if isActive { leave() }
        begin(code: invite.code, kind: invite.kind, host: invite.hostName, as: .joined)
    }

    /// Leaves the group. Your recording keeps going; the caller decides whether to stop and save it.
    func leave() {
        guard let code else { reset(); return }
        loop?.cancel()
        loop = nil
        let id = CKRecord.ID(recordName: "rider-\(code)-\(riderID)")
        let db = database
        Task { _ = try? await db.deleteRecord(withID: id) }   // best effort
        reset()
    }

    /// Host only: marks the trip ended so everyone else sees "Trip ended by <host>", then leaves.
    func endForEveryone() async {
        guard state == .hosting, let code else { return }
        do {
            let rec = try await fetchTrip(code: code)
                ?? CKRecord(recordType: "GroupTrip", recordID: CKRecord.ID(recordName: "trip-\(code)"))
            rec["code"] = code as NSString
            rec["kind"] = kind.rawValue as NSString
            rec["hostName"] = hostName as NSString
            if rec.object(forKey: "createdAt") == nil { rec["createdAt"] = Date() as NSDate }
            rec["endedAt"] = Date() as NSDate
            _ = try await database.modifyRecords(saving: [rec], deleting: [], savePolicy: .changedKeys, atomically: true)
        } catch {
            // Still leave; the others drop off once your record goes stale.
            lastError = friendly(error, action: "end the trip for everyone")
        }
        leave()
    }

    // MARK: Internals

    private func begin(code: String, kind: ActivityKind, host: String, as newState: State) {
        self.code = code
        self.kind = kind
        self.hostName = host
        riders = []
        knownNames = [:]
        firstFetchDone = false
        tickCount = 0
        connectionNote = nil
        endedNotice = nil
        state = newState
        // Same path as the Start button, so the trip is recorded into History as usual.
        startedTracking = false
        if let t = tracker, !t.isActive {
            if !t.canTrack { t.requestPermission() }
            t.start(kind: kind)
            startedTracking = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        startLoop()
    }

    private func reset() {
        loop?.cancel()
        loop = nil
        state = .idle
        code = nil
        riders = []
        knownNames = [:]
        connectionNote = nil
        startedTracking = false
        tickCount = 0
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                // Every 3 s in the app; back off to 6 s in the background.
                let background = UIApplication.shared.applicationState == .background
                let seconds: UInt64 = background ? 6 : 3
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
    }

    private func tick() async {
        guard isActive, let code else { return }
        tickCount += 1
        await uploadMe(code: code)
        guard isActive, self.code == code else { return }
        await fetchRiders(code: code)
        if state == .joined, tickCount % 5 == 0 {
            await checkEnded(code: code)
        }
    }

    private func uploadMe(code: String) async {
        guard let t = tracker, let here = t.lastCoordinate else { return }
        let rec = CKRecord(recordType: "Rider", recordID: CKRecord.ID(recordName: "rider-\(code)-\(riderID)"))
        rec["tripCode"] = code as NSString
        rec["riderID"] = riderID as NSString
        rec["name"] = myName as NSString
        rec["lat"] = NSNumber(value: here.latitude)
        rec["lon"] = NSNumber(value: here.longitude)
        rec["speed"] = NSNumber(value: max(0, t.currentSpeed.isFinite ? t.currentSpeed : 0))
        rec["heading"] = NSNumber(value: t.course.isFinite ? t.course : -1)
        rec["kind"] = (t.isActive ? t.kind : kind).rawValue as NSString
        rec["color"] = myColorHex as NSString
        rec["updatedAt"] = Date() as NSDate
        do {
            let result = try await database.modifyRecords(saving: [rec], deleting: [], savePolicy: .allKeys, atomically: false)
            if case .failure(let e)? = result.saveResults[rec.recordID] { throw e }
            connectionNote = nil
        } catch {
            connectionNote = softNote(error)
        }
    }

    private func fetchRiders(code: String) async {
        let cutoff = Date().addingTimeInterval(-90)
        let predicate = NSPredicate(format: "tripCode == %@ AND updatedAt > %@", code, cutoff as NSDate)
        let query = CKQuery(recordType: "Rider", predicate: predicate)
        do {
            let (matches, _) = try await database.records(matching: query, resultsLimit: 50)
            guard isActive, self.code == code else { return }
            var list: [RiderState] = []
            for (_, result) in matches {
                guard case .success(let r) = result, let rider = Self.rider(from: r), rider.id != riderID else { continue }
                list.append(rider)
            }
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            noteArrivals(list)
            riders = list
        } catch {
            connectionNote = softNote(error)
        }
    }

    private func checkEnded(code: String) async {
        guard let trip = try? await fetchTrip(code: code) else { return }
        guard isActive, self.code == code, trip["endedAt"] as? Date != nil else { return }
        let host = (trip["hostName"] as? String) ?? hostName
        leave()
        endedNotice = "Trip ended by \(host)"
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Haptic + toast when someone shows up or drops off.
    private func noteArrivals(_ list: [RiderState]) {
        let now = Set(list.map(\.id))
        let before = Set(knownNames.keys)
        if firstFetchDone {
            let joined = list.filter { !before.contains($0.id) }
            let left = before.subtracting(now)
            if let j = joined.first {
                toast = joined.count == 1 ? "\(j.name) joined" : "\(joined.count) people joined"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else if let l = left.first {
                let name = knownNames[l] ?? "Someone"
                toast = left.count == 1 ? "\(name) left" : "\(left.count) people left"
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        firstFetchDone = true
        var names: [String: String] = [:]
        for r in list { names[r.id] = r.name }
        knownNames = names
    }

    private func fetchTrip(code: String) async throws -> CKRecord? {
        do {
            return try await database.record(for: CKRecord.ID(recordName: "trip-\(code)"))
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    private static func rider(from r: CKRecord) -> RiderState? {
        guard let id = r["riderID"] as? String,
              let lat = (r["lat"] as? NSNumber)?.doubleValue,
              let lon = (r["lon"] as? NSNumber)?.doubleValue else { return nil }
        let name = (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Friend"
        return RiderState(
            id: id,
            name: name,
            latitude: lat,
            longitude: lon,
            speed: (r["speed"] as? NSNumber)?.doubleValue ?? 0,
            heading: (r["heading"] as? NSNumber)?.doubleValue ?? -1,
            kind: ActivityKind(rawValue: (r["kind"] as? String) ?? "") ?? .drive,
            colorHex: (r["color"] as? String) ?? "#4FC3F7",
            updatedAt: (r["updatedAt"] as? Date) ?? r.modificationDate ?? Date.distantPast
        )
    }

    private func iCloudReady() async -> Bool {
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            if status == .available { return true }
        } catch {}
        lastError = "Sign in to iCloud in Settings to go together."
        return false
    }

    private func friendly(_ error: Error, action: String) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to go together."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "Couldn't reach iCloud to \(action). Check your connection and try again."
            case .permissionFailure: return "iCloud didn't allow that. Only the host can end the trip for everyone."
            case .unknownItem: return "That group isn't there anymore."
            default: break
            }
        }
        return "Couldn't \(action). Try again in a moment."
    }

    private func softNote(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "No signal. Reconnecting…"
            case .notAuthenticated: return "Sign in to iCloud in Settings to go together."
            case .requestRateLimited, .serviceUnavailable, .zoneBusy: return "iCloud is busy. Retrying…"
            default: break
            }
        }
        return "Having trouble syncing. Retrying…"
    }

    /// Deterministic (unlike String.hashValue, which changes every launch).
    private static func stableHash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33) &+ Int(b) }
        return h == Int.min ? 0 : h
    }

    // MARK: Geometry helpers for the UI

    /// Your own position right now (from the recording).
    var myCoordinate: CLLocationCoordinate2D? { tracker?.lastCoordinate }

    /// "0.4 mi ahead" / "0.4 mi behind" / "0.4 mi away".
    func relation(to rider: RiderState) -> String {
        guard let me = myCoordinate else { return "" }
        let here = CLLocation(latitude: me.latitude, longitude: me.longitude)
        let d = here.distance(from: rider.location)
        let dist = Format.distance(d)
        if d < 25 { return "right here" }
        guard let course = tracker?.course, course >= 0 else { return "\(dist) away" }
        let bearing = Self.bearing(from: me, to: rider.coordinate)
        var diff = (bearing - course).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 } else if diff < -180 { diff += 360 }
        return abs(diff) < 90 ? "\(dist) ahead" : "\(dist) behind"
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Siri: "Start a group drive"

enum GroupPending {
    static let key = "group.pendingStart"
    static let note = Notification.Name("roamr.groupPendingStart")

    static func queue() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        NotificationCenter.default.post(name: note, object: nil)
    }

    /// True once if a start was asked for in the last two minutes.
    static func take() -> Bool {
        let d = UserDefaults.standard
        let at = d.double(forKey: key)
        guard at > 0 else { return false }
        d.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - at < 120
    }
}

// MARK: - Hex colors

extension Color {
    init(groupHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self = Color(red: 0.31, green: 0.76, blue: 0.97)
            return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}
