import Foundation
import SwiftData
import SwiftUI

/// Finds hugs that went missing on Nov 15 and puts them back.
///
/// 1. Hugs saved while Rootbound was (by mistake) writing to the shared App Group store (see GroupStoreRescue)
///    are copied back into Rootbound's own store, photos and all, with their original ids.
/// 2. Still Pointz sessions done "with a tree" that have no hug of that tree around that time are listed, so the
///    owner can restore each one (tree, time, place and breathwork; the photo can be added afterwards).
/// Runs once on launch after this update and any time from Settings > Find missing hugs.
@MainActor
enum HugRescue {
    struct MissingHug: Identifiable, Hashable {
        /// treeID + day, so two days with the same tree are two rows.
        let id: String
        let treeID: UUID
        var name: String
        var sessions: [WellnessBridge.Session]
        var date: Date { sessions.map(\.date).min() ?? Date() }
    }

    struct Report: Identifiable {
        let id = UUID()
        /// The stray shared store was on this iPhone.
        var checkedOldStore = false
        /// Hugs in the stray store, and how many of them came back (the rest were already here).
        var foundInOldStore = 0
        var restored = 0
        var alreadyHere = 0
        /// Couldn't read the stray store (the reason).
        var problem: String?
        var missing: [MissingHug] = []

        /// Worth showing the owner on launch.
        var hasNews: Bool { restored > 0 || !missing.isEmpty }
    }

    private static let doneKey = "rescue.groupStore.hugs.v1"

    /// Once per install, right after this update. Returns a report only when something was found.
    static func runOnce(in context: ModelContext) async -> Report? {
        guard !DemoData.isOn, !UserDefaults.standard.bool(forKey: doneKey) else { return nil }
        let report = await run(in: context)
        if report.problem == nil { UserDefaults.standard.set(true, forKey: doneKey) }
        return report.hasNews ? report : nil
    }

    static func run(in context: ModelContext) async -> Report {
        var r = Report()
        guard !DemoData.isOn else { return r }
        if let stray = GroupStoreRescue.strayStoreURL {
            r.checkedOldStore = true
            do {
                let scratch = try await Task.detached(priority: .userInitiated) {
                    try GroupStoreRescue.makePrivateCopy(of: stray)
                }.value
                defer { GroupStoreRescue.discard(scratch) }
                let old = try GroupStoreRescue.openCopy(scratch, schema: Schema([Hug.self, Activity.self]))
                let oldHugs = try ModelContext(old).fetch(FetchDescriptor<Hug>())
                r.foundInOldStore = oldHugs.count
                var here = try context.fetch(FetchDescriptor<Hug>())
                for h in oldHugs {
                    if here.contains(where: { isSame($0, h) }) { r.alreadyHere += 1; continue }
                    let n = copy(of: h)
                    context.insert(n)
                    here.append(n)
                    r.restored += 1
                }
                if r.restored > 0 { try context.save() }
            } catch {
                r.problem = error.localizedDescription
            }
        }
        r.missing = missingFromStillPoint(in: context)
        return r
    }

    /// Same hug: same id, or the same tree within two minutes (a hug logged again by hand).
    static func isSame(_ a: Hug, _ b: Hug) -> Bool {
        if a.id == b.id { return true }
        guard abs(a.date.timeIntervalSince(b.date)) < 120 else { return false }
        if a.treeID == b.treeID { return true }
        return !a.treeName.isEmpty && a.treeName.caseInsensitiveCompare(b.treeName) == .orderedSame
    }

    // MARK: From Still Pointz

    /// Breath sessions done with a tree (Still Pointz' feed) where Rootbound has no hug of that tree within
    /// 3 hours and no hug links the session. Grouped by tree and day, newest first.
    static func missingFromStillPoint(in context: ModelContext) -> [MissingHug] {
        let sessions = (WellnessBridge.stillPoint()?.sessions ?? []).filter { ($0.treeID ?? "").isEmpty == false }
        guard !sessions.isEmpty, let hugs = try? context.fetch(FetchDescriptor<Hug>()) else { return [] }
        let linkedFeedIDs = Set(hugs.flatMap { $0.linkedSessions.compactMap(\.feedID) })
        let cal = Calendar.current
        var groups: [String: MissingHug] = [:]
        for s in sessions {
            guard let raw = s.treeID, let treeID = UUID(uuidString: raw), !linkedFeedIDs.contains(s.id) else { continue }
            let covered = hugs.contains { $0.treeID == treeID && abs($0.date.timeIntervalSince(s.date)) <= 3 * 3600 }
            if covered { continue }
            let day = cal.startOfDay(for: s.date)
            let key = "\(treeID.uuidString)-\(Int(day.timeIntervalSince1970))"
            let known = hugs.first { $0.treeID == treeID && !$0.treeName.isEmpty }?.treeName
            groups[key, default: MissingHug(id: key, treeID: treeID, name: known ?? s.treeName ?? "Tree", sessions: [])]
                .sessions.append(s)
        }
        var list = Array(groups.values)
        for i in list.indices { list[i].sessions.sort { a, b in a.date < b.date } }
        return list.sorted { a, b in a.date > b.date }
    }

    /// Adds the hug for a missing Still Pointz row: the tree (name, species and place from its other hugs when
    /// it has any), the time of the first session and every session's breathwork. Returns the new hug.
    @discardableResult
    static func restore(_ m: MissingHug, in context: ModelContext) -> Hug? {
        let all = (try? context.fetch(FetchDescriptor<Hug>())) ?? []
        let sameTree = all.filter { $0.treeID == m.treeID }.sorted { $0.date > $1.date }
        let h = Hug()
        h.treeID = m.treeID
        h.treeName = sameTree.first { !$0.treeName.isEmpty }?.treeName ?? m.name
        h.species = sameTree.first { !$0.species.isEmpty }?.species ?? ""
        if let placed = sameTree.first(where: { $0.coordinate != nil }) {
            h.latitude = placed.latitude
            h.longitude = placed.longitude
            h.placeName = placed.placeName
        }
        h.date = m.date
        h.exercise = m.sessions.first?.practice.map { $0.replacingOccurrences(of: "-", with: " ").capitalized } ?? ""
        h.linkedSessions = m.sessions.map(HugSessions.linked(from:))
        let hr = h.linkedSessions
        h.avgHR = hr.avgHR
        h.minHR = hr.lowestHR
        h.hrv = hr.avgHRV
        h.respRate = hr.avgResp
        h.hrStart = hr.first?.startHR
        h.hrEnd = hr.last?.endHR
        h.durationMin = (hr.totalMinutes * 10).rounded() / 10
        h.notes = String(localized: "Brought back from your Still Pointz sessions with this tree.")
        h.leafKey = GameEngine.rollLeaf(for: h).id
        h.xp = GameEngine.xp(for: h, existing: all).total
        context.insert(h)
        do { try context.save() } catch { context.delete(h); return nil }
        return h
    }

    // MARK: Copy

    /// Every stored property of Hug. RootboundTests checks this against the model, so a new field can't be left
    /// out of `copy(of:)` by accident.
    static let copiedProperties: Set<String> = [
        "id", "date", "treeID", "treeName", "species", "latitude", "longitude", "placeName",
        "treePhoto", "selfiePhoto", "garminPhoto", "tagsRaw", "barefoot", "feetInWater", "waterSetting", "weather",
        "moodBefore", "moodAfter", "notes", "exercise", "durationMin", "avgHR", "minHR", "maxHR", "respRate",
        "stressStart", "stressEnd", "bodyBattery", "hrStart", "hrEnd", "hrv", "fromWatch", "linkedSessionsData",
        "strollID", "linkedWalksData", "xp", "leafKey",
    ]

    /// A new Hug holding every stored value of `o` (same id, same tree).
    static func copy(of o: Hug) -> Hug {
        let h = Hug()
        h.id = o.id
        h.date = o.date
        h.treeID = o.treeID
        h.treeName = o.treeName
        h.species = o.species
        h.latitude = o.latitude
        h.longitude = o.longitude
        h.placeName = o.placeName
        h.treePhoto = o.treePhoto
        h.selfiePhoto = o.selfiePhoto
        h.garminPhoto = o.garminPhoto
        h.tagsRaw = o.tagsRaw
        h.barefoot = o.barefoot
        h.feetInWater = o.feetInWater
        h.waterSetting = o.waterSetting
        h.weather = o.weather
        h.moodBefore = o.moodBefore
        h.moodAfter = o.moodAfter
        h.notes = o.notes
        h.exercise = o.exercise
        h.durationMin = o.durationMin
        h.avgHR = o.avgHR
        h.minHR = o.minHR
        h.maxHR = o.maxHR
        h.respRate = o.respRate
        h.stressStart = o.stressStart
        h.stressEnd = o.stressEnd
        h.bodyBattery = o.bodyBattery
        h.hrStart = o.hrStart
        h.hrEnd = o.hrEnd
        h.hrv = o.hrv
        h.fromWatch = o.fromWatch
        h.linkedSessionsData = o.linkedSessionsData
        h.strollID = o.strollID
        h.linkedWalksData = o.linkedWalksData
        h.xp = o.xp
        h.leafKey = o.leafKey
        return h
    }
}

/// What the owner sees after a rescue: what came back, and the hugs Still Pointz remembers that can be restored.
struct HugRescueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let report: HugRescue.Report
    @State private var restoredIDs: Set<String> = []
    @State private var failedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if report.restored > 0 {
                        Label(report.restored == 1 ? "1 hug is back." : "\(report.restored) hugs are back.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if report.checkedOldStore {
                        Text(report.foundInOldStore == 0
                             ? "The old storage had no hugs left in it."
                             : "Every hug in the old storage is already here.")
                    } else {
                        Text("Nothing was saved in the wrong place on this iPhone.")
                    }
                    if let problem = report.problem {
                        Text("Couldn't read the old storage: \(problem)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Saved in the wrong place")
                } footer: {
                    Text("For a few hours on Nov 15 an update saved hugs to the wrong place. Anything still there comes back with its photos.")
                }

                if !report.missing.isEmpty {
                    Section {
                        ForEach(report.missing) { m in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.name).font(.headline)
                                    Text(m.date.formatted(date: .abbreviated, time: .shortened)
                                         + " · " + (m.sessions.count == 1 ? "1 breath session"
                                                    : "\(m.sessions.count) breath sessions"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if restoredIDs.contains(m.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Restored")
                                } else {
                                    Button(failedIDs.contains(m.id) ? "Try again" : "Restore") {
                                        if HugRescue.restore(m, in: context) != nil {
                                            restoredIDs.insert(m.id)
                                            failedIDs.remove(m.id)
                                        } else {
                                            failedIDs.insert(m.id)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .sensoryFeedback(.success, trigger: restoredIDs.contains(m.id))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Hugs Still Pointz remembers")
                    } footer: {
                        Text("You did these breath sessions with a tree, but Rootbound has no hug of it then. Restore adds the hug with the tree, time, place and breathwork. Add the photo afterwards from the hug's Edit screen.")
                    }
                }
            }
            .navigationTitle("Missing hugs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
