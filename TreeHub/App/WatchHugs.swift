import SwiftUI
import SwiftData
import WatchConnectivity
import CoreLocation

/// A hug timed on the Rootbound Watch app (RootboundWatch/HugWorkout.swift), waiting to be put under a tree.
struct WatchHug: Codable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    var avgHR: Double?
    var minHR: Double?
    var maxHR: Double?
    var startHR: Double?
    var endHR: Double?

    var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }

    init?(_ d: [String: Any]) {
        guard d["rbWatchHug"] != nil, let s = d["start"] as? Double, let e = d["end"] as? Double else { return nil }
        id = (d["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        start = Date(timeIntervalSince1970: s)
        end = Date(timeIntervalSince1970: e)
        avgHR = d["avgHR"] as? Double; minHR = d["minHR"] as? Double; maxHR = d["maxHR"] as? Double
        startHR = d["startHR"] as? Double; endHR = d["endHR"] as? Double
    }
}

/// Phone side of WatchConnectivity: Watch hugs land here (kept until logged or dismissed).
final class WatchHugInbox: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchHugInbox()
    private static let key = "rb.watchHugs"

    @Published private(set) var pending: [WatchHug] = []

    override init() {
        super.init()
        pending = Self.load()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private static func load() -> [WatchHug] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let l = try? JSONDecoder().decode([WatchHug].self, from: d) else { return [] }
        return l
    }

    private func save() {
        if let d = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    @MainActor func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
        save()
    }

    private func receive(_ info: [String: Any]) {
        guard let hug = WatchHug(info) else { return }
        DispatchQueue.main.async {
            guard !self.pending.contains(where: { $0.id == hug.id }) else { return }
            self.pending.append(hug)
            self.pending.sort { $0.start > $1.start }
            self.save()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
}

/// "Hug from Watch — pick tree": nearest trees first; picking one opens the hug logger with the Watch data filled in.
@MainActor
struct WatchHugPrompt: View {
    let hug: WatchHug
    var onPick: (UUID?) -> Void
    var onDiscard: () -> Void
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @State private var here: CLLocationCoordinate2D?
    @State private var fetcher = LocationFetcher()
    @Environment(\.dismiss) private var dismiss

    private var trees: [(TreeSummary, Double?)] {
        TreeSummary.build(from: hugs).map { t -> (TreeSummary, Double?) in
            guard let here, let c = t.coordinate else { return (t, nil) }
            return (t, Geo.distance(here, c))
        }.sorted { ($0.1 ?? .infinity) < ($1.1 ?? .infinity) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    RBSectionTitle(title: "Which tree?", symbol: "tree.fill")
                    Button { onPick(nil) } label: {
                        row(name: "New tree", sub: "Make a new friend", photo: nil, symbol: "plus")
                    }
                    .buttonStyle(.plain)
                    ForEach(trees.prefix(12), id: \.0.id) { pair in
                        Button { onPick(pair.0.id) } label: {
                            row(name: pair.0.name,
                                sub: pair.1.map { $0 < 1000 ? "\(Int($0)) m away" : Format.distance($0) + " away" }
                                    ?? "\(pair.0.hugCount) hug\(pair.0.hugCount == 1 ? "" : "s")",
                                photo: pair.0.coverPhoto, symbol: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.pad)
            }
            .forestScreen()
            .navigationTitle("Hug from Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) { Button("Discard", role: .destructive) { onDiscard() } }
            }
            .task { here = await fetcher.current()?.coordinate }
        }
    }

    private var summary: some View {
        RBCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(Format.dayTime(hug.start))", systemImage: "applewatch")
                    .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.textDim)
                HStack(spacing: 10) {
                    RBStatTile(value: Format.minutes((hug.minutes * 10).rounded() / 10), label: "Hug")
                    RBStatTile(value: hug.avgHR.map { "\(Int($0))" } ?? "--", label: "Avg bpm")
                    if let a = hug.startHR, let b = hug.endHR {
                        RBStatTile(value: String(format: "%+.0f", b - a), label: "HR change")
                    }
                }
            }
        }
    }

    private func row(name: String, sub: String, photo: Data?, symbol: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let symbol {
                    Theme.card
                    Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.glow)
                } else {
                    PhotoView(data: photo)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                Text(sub).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}
