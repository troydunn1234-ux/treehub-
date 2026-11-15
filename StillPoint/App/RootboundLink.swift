import SwiftUI

// Still Pointz <-> Rootbound (the tree-hugging app). The shared feed and URLs live in Shared/Wellness/WellnessBridge.swift.
//  • publishes this app's sessions + streak for Rootbound ("Calm minutes", Breath & Bark)
//  • reads Rootbound's tree hugs (≥ 1 min) so they count in Progress ("Trees") and keep the streak alive
//  • stillpoint://session?practice=…&minutes=3&context=tree&name=<tree> starts "Breathing with <tree>"
// Nothing here writes to Apple Health: each app already saves its own sessions there.

enum StillPointWellness {
    /// Publish our half of the feed and pull in Rootbound's hugs. Cheap; called on launch, foreground and log changes.
    @MainActor
    static func sync(log: SessionLog = .shared, heat: HeatStore = .shared) {
        if let rb = WellnessBridge.rootbound() {
            let since = Date().addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
            let trees = rb.hugs.map { TreeEntry(id: $0.id, start: $0.date, minutes: $0.minutes, name: $0.tree) }
            log.mergeTrees(trees, window: since)
        }
        var out: [WellnessBridge.Session] = log.records.filter { $0.seconds >= 60 }.map {
            WellnessBridge.Session(id: $0.id, date: $0.start, kind: ($0.kind ?? "breath").lowercased(), minutes: $0.minutes)
        }
        out += heat.history.filter { $0.end != nil && $0.minutes >= 1 }.map {
            WellnessBridge.Session(id: $0.id, date: $0.start, kind: $0.kind.rawValue, minutes: $0.minutes)
        }
        WellnessBridge.publishStillPoint(sessions: out, streak: log.streak)
    }

    /// The tree a "Breathe with a tree" request should name: the last one hugged in Rootbound, if any.
    static var lastTreeName: String? {
        let n = WellnessBridge.rootbound()?.hugs.first?.tree.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? nil : n
    }

    /// stillpoint://session?practice=<id>&minutes=<n>&context=tree&name=<tree>
    struct SessionRequest {
        var practiceId: String
        var minutes: Int
        var treeName: String?
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
        return SessionRequest(practiceId: q("practice") ?? "resonance", minutes: max(1, min(20, mins)), treeName: tree)
    }

    /// A calm breathing practice this person can run right now: the one asked for if it's open, else the free
    /// Box Breathing, else the quick default.
    static func calmPractice(preferred id: String) -> Practice {
        let lib = PracticeLibrary.shared
        if let p = lib.practice(id), !p.isMovement, !lib.isLocked(p) { return p }
        for alt in ["resonance", "box", "physiological-sigh"] {
            if let p = lib.practice(alt), !lib.isLocked(p) { return p }
        }
        return lib.quickPractice
    }
}

extension Router {
    /// Pending "Breathe with a tree" from Siri (tree name; picked up like the practice queue).
    static let pendingTreeKey = "sp.pendingTree"

    static func queueTreeBreath(name: String) {
        UserDefaults.standard.set(name, forKey: pendingTreeKey)
        NotificationCenter.default.post(name: pendingNote, object: nil)
    }

    /// Start a short session from a stillpoint://session link. Ignored while a session is running.
    func handle(session req: StillPointWellness.SessionRequest) {
        guard running == nil else { return }
        showSettings = false
        showHeatGuide = false
        tab = 0
        let p = StillPointWellness.calmPractice(preferred: req.practiceId)
        var plan = SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: req.minutes)
        plan.treeName = req.treeName
        run(plan)
    }

    func consumePendingTree() {
        guard let name = UserDefaults.standard.string(forKey: Self.pendingTreeKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingTreeKey)
        handle(session: .init(practiceId: "resonance", minutes: 3, treeName: name.isEmpty ? "a tree" : name))
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
                    Text(title).font(SP.serif(17)).foregroundStyle(SP.ink)
                    Text(installed ? subtitle : "Get Rootbound on the App Store, a tree-hugging companion to Still Pointz.")
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
