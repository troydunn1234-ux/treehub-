import SwiftUI

// Still Pointz <-> Rootbound (the tree-hugging app). The shared feed and URLs live in Shared/Wellness/WellnessBridge.swift.
//  • publishes this app's sessions + streak for Rootbound ("Calm minutes", Breath & Bark)
//  • reads Rootbound's tree hugs (≥ 1 min) so they count in Progress ("Trees") and keep the streak alive
//  • stillpoint://session?practice=…&minutes=3&context=tree&name=<tree> starts "Breathing with <tree>"
// Nothing here writes to Apple Health: each app already saves its own sessions there.

enum StillPointWellness {
    /// Publish our half of the feed and pull in Rootbound's hugs. Cheap; called on launch, foreground and log changes.
    @MainActor
    static func sync() {
        let log = SessionLog.shared
        let heat = HeatStore.shared
        enrichTreeSessions(log)
        if let rb = WellnessBridge.rootbound() {
            let trees = rb.hugs.map { TreeEntry(id: $0.id, start: $0.date, minutes: $0.minutes, name: $0.tree) }
            log.mergeTrees(trees, window: treeWindow(rb))
        }
        var out: [WellnessBridge.Session] = log.records.filter { $0.seconds >= 60 }.map(feedSession)
        out += heat.history.filter { $0.end != nil && $0.minutes >= 1 }.map {
            WellnessBridge.Session(id: $0.id, date: $0.start, kind: $0.kind.rawValue, minutes: $0.minutes)
        }
        WellnessBridge.publishStillPoint(sessions: out, streak: log.streak)
    }

    /// One session as Rootbound, Roamr and Pulse Lab see it in stillpoint.json: its time, practice, the tree it was
    /// done with and every heart number Still Pointz has for it (pure, so it's testable).
    static func feedSession(_ r: SessionRecord) -> WellnessBridge.Session {
        var s = WellnessBridge.Session(id: r.id, date: r.start, kind: (r.kind ?? "breath").lowercased(), minutes: r.minutes)
        s.end = r.end
        s.practice = r.practiceId
        s.treeID = r.treeID
        s.treeName = r.treeName
        s.avgHR = r.hrAvg
        s.minHR = r.hrMin ?? r.hrLow
        s.startHR = r.hrStart
        s.hrDrop = r.hrDrop
        s.hrv = r.hrv
        s.endHR = r.hrEnd
        s.respRate = r.respiratoryRate
        s.calmSeconds = r.calmZoneSeconds
        s.breathsPerMin = r.breathsPerMinute
        return s
    }

    /// From when Rootbound's feed lists every hug: 120 days back, or only back to its oldest hug once it holds
    /// `WellnessBridge.maxItems` (older ones were trimmed, not deleted in Rootbound, so they stay counted here).
    static func treeWindow(_ rb: WellnessBridge.RootboundPart, now: Date = Date()) -> Date {
        let since = now.addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
        guard rb.hugs.count >= WellnessBridge.maxItems, let oldest = rb.hugs.map(\.date).min() else { return since }
        return max(since, oldest)
    }

    /// The tree a "Breathe with a tree" request should use: the last one hugged in Rootbound, if any.
    static var lastTree: (name: String, id: String?)? {
        guard let h = WellnessBridge.rootbound()?.hugs.first else { return nil }
        let n = h.tree.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n.isEmpty ? "a tree" : n, h.treeID?.uuidString)
    }

    // MARK: Heart data for tree sessions

    /// Last time each tree session was looked up in Apple Health (WHOOP / Watch data can arrive minutes later).
    private static var lastLookup: [UUID: Date] = [:]

    /// Fill heart rate (avg, lowest, start, end), the curve and HRV for recent tree sessions from Apple Health
    /// (read-only; the session's mindful minutes were already saved once when it finished). The updated record is
    /// re-published to the feed, so Rootbound shows the stats under the tree.
    @MainActor
    static func enrichTreeSessions(_ log: SessionLog = .shared) {
        enrichSessions(log)
    }

    /// Fill missing heart data (curve, start / low / avg / end, HRV, breathing rate, calm-zone time) for every
    /// session of the last two days from Apple Health, read-only. Watch data can land minutes late, so this runs
    /// on launch, foreground, right after a session and when a session's results are opened.
    @MainActor
    static func enrichSessions(_ log: SessionLog = .shared, only: UUID? = nil, force: Bool = false) {
        let since = Date().addingTimeInterval(-2 * 86400)
        for r in log.records where (only == nil || r.id == only) && (only != nil || r.start >= since)
            && r.seconds >= 30 && (r.hrAvg == nil || r.hrv == nil || r.respiratoryRate == nil || r.calmSeconds == nil) {
            if !force, let t = lastLookup[r.id], Date().timeIntervalSince(t) < 90 { continue }
            lastLookup[r.id] = Date()
            let id = r.id
            if r.hrAvg == nil || r.calmSeconds == nil {
                MindfulHealth.shared.heartRateStats(start: r.start, end: r.end) { w in
                    guard let w else { return }
                    log.update(id) { rec in
                        if rec.hrAvg == nil { rec.hrAvg = (w.avg * 10).rounded() / 10 }
                        if rec.hrMin == nil { rec.hrMin = w.min }
                        if rec.hrStart == nil { rec.hrStart = w.points.first?.bpm }
                        if rec.hrEnd == nil { rec.hrEnd = w.points.last?.bpm }
                        if rec.hrSamples == nil, w.points.count >= 2 { rec.hrSamples = w.points }
                        if rec.calmSeconds == nil {
                            rec.calmSeconds = SessionRecord.calmSeconds(samples: rec.hrSamples, start: rec.hrStart, total: rec.seconds)
                        }
                    }
                }
            }
            if r.hrv == nil {
                MindfulHealth.shared.sessionHRV(start: r.start, end: r.end) { v in
                    guard let v else { return }
                    log.update(id) { $0.hrv = (v * 10).rounded() / 10 }
                }
            }
            if r.respiratoryRate == nil {
                MindfulHealth.shared.respiratoryRate(start: r.start, end: r.end) { v in
                    guard let v else { return }
                    log.update(id) { $0.respiratoryRate = (v * 10).rounded() / 10 }
                }
            }
        }
    }

    /// Right after any session: look now, then again as late Watch / WHOOP data arrives.
    @MainActor
    static func sessionFinished(_ id: UUID) {
        for delay in [3.0, 25.0, 120.0, 300.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                enrichSessions(only: id, force: true)
                sync()
            }
        }
    }

    /// Right after a tree session ends: publish at once (so "Back to <tree>" shows it), then fill heart data now
    /// and again in a few minutes.
    @MainActor
    static func treeSessionFinished() {
        sync()
        for delay in [20.0, 180.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                lastLookup = [:]
                enrichTreeSessions()
            }
        }
    }

    /// stillpoint://session?practice=<id>&minutes=<n>&context=tree&name=<tree>&tree=<id>
    struct SessionRequest {
        var practiceId: String
        var minutes: Int
        var treeName: String?
        var treeID: String? = nil
    }

    static func sessionRequest(from url: URL) -> SessionRequest? {
        guard url.scheme?.lowercased() == "stillpoint", url.host?.lowercased() == "session" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
        let mins = Int(q("minutes") ?? "") ?? 3
        var tree: String? = nil
        if q("context")?.lowercased() == "tree" {
            let n = (q("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            tree = n.isEmpty ? "a tree" : String(n.prefix(40))
        }
        let treeID = tree == nil ? nil : q("tree").flatMap { UUID(uuidString: $0)?.uuidString }
        return SessionRequest(practiceId: q("practice") ?? "rooted-breath", minutes: max(1, min(20, mins)), treeName: tree, treeID: treeID)
    }

    /// A calm breathing practice this person can run right now: the one asked for if it's open, else the free
    /// Box Breathing, else the quick default.
    static func calmPractice(preferred id: String) -> Practice {
        let lib = PracticeLibrary.shared
        if let p = lib.practice(id), !p.isMovement, !lib.isLocked(p) { return p }
        for alt in ["rooted-breath", "resonance", "box", "sigh"] {
            if let p = lib.practice(alt), !lib.isLocked(p) { return p }
        }
        return lib.quickPractice
    }
}

extension Router {
    /// Pending "Breathe with a tree" from Siri (tree name; picked up like the practice queue).
    static let pendingTreeKey = "sp.pendingTree"

    static func queueTreeBreath(name: String, treeID: String?) {
        UserDefaults.standard.set(name + "\n" + (treeID ?? ""), forKey: pendingTreeKey)
        NotificationCenter.default.post(name: pendingNote, object: nil)
    }

    /// Start a short session from a stillpoint://session link. Ignored while a session is running.
    func handle(session req: StillPointWellness.SessionRequest) {
        guard running == nil else { return }
        tab = 0   // run() closes Settings / the heat guide first when they're up
        let p = StillPointWellness.calmPractice(preferred: req.practiceId)
        var plan = SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: req.minutes)
        plan.treeName = req.treeName
        plan.treeID = req.treeID
        run(plan)
    }

    func consumePendingTree() {
        guard let raw = UserDefaults.standard.string(forKey: Self.pendingTreeKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingTreeKey)
        let parts = raw.components(separatedBy: "\n")
        let name = parts.first ?? ""
        let id = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        handle(session: .init(practiceId: "rooted-breath", minutes: 3, treeName: name.isEmpty ? "a tree" : name, treeID: id))
    }
}

// MARK: - "Go hug a tree" (opens Rootbound's hug logger, or its App Store page)

struct RootboundLinkCard: View {
    var title: String = "Go hug a tree"
    var subtitle: String = "Log it in Rootbound. Hugs of a minute or more count here too."
    var url: URL = WellnessLinks.hugLogger
    var symbol: String = "tree"
    @State private var installed = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if !WellnessLinks.open(url) {
                installed = false
                if let store = WellnessLinks.storeURL(bundleID: WellnessLinks.rootboundBundleID) { openURL(store) }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color(spHex: "#8CCB7E"))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(spHex: "#8CCB7E").opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title)).font(SP.serif(17)).foregroundStyle(SP.ink)
                    Text(installed ? LocalizedStringKey(subtitle) : "Get Rootbound on the App Store, a tree-hugging companion to Still Pointz.")
                        .font(SP.rounded(12)).foregroundStyle(SP.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: installed ? "arrow.up.forward" : "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(SP.faint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SP.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SP.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPress())
        .onAppear { installed = WellnessLinks.rootboundInstalled }
        .accessibilityHint(installed ? "Opens Rootbound" : "Opens the App Store")
    }
}
