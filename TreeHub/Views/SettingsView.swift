import SwiftUI
import SwiftData

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetric") private var useMetric = false
    @Query(sort: \Hug.date) private var hugs: [Hug]
    @Query(sort: \Activity.start) private var activities: [Activity]
    @State private var healthStatus = ""
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Toggle("Metric (km, m)", isOn: $useMetric)
                }
                Section {
                    Button("Connect Apple Health") {
                        Task {
                            let ok = await HealthService.shared.requestAccess()
                            healthStatus = ok ? "Done. Rootbound can read what you allowed." : "Apple Health isn't available on this device."
                        }
                    }
                    if !healthStatus.isEmpty { Text(healthStatus).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Garmin · Whoop · Strava")
                } footer: {
                    Text("These apps share into Apple Health. In Garmin Connect: More → Settings → Connected Apps → Apple Health. In Whoop and Strava, turn on Apple Health in their settings. Rootbound then reads heart rate, breathing rate, mindful minutes and workouts.")
                }
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export my data (JSON)", systemImage: "square.and.arrow.up") }
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything stays on your iPhone and syncs to your private iCloud. Nobody else can see it. \(hugs.count) hugs · \(activities.count) activities.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ForestBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { exportURL = DataExport.write(hugs: hugs, activities: activities) }
        }
    }
}

enum DataExport {
    static func write(hugs: [Hug], activities: [Activity]) -> URL? {
        let iso = ISO8601DateFormatter()
        let hugRows: [[String: Any]] = hugs.map { h in
            var r: [String: Any] = [
                "id": h.id.uuidString, "date": iso.string(from: h.date), "treeId": h.treeID.uuidString,
                "treeName": h.treeName, "species": h.species, "place": h.placeName, "tags": h.tags,
                "barefoot": h.barefoot, "weather": h.weather, "moodBefore": h.moodBefore, "moodAfter": h.moodAfter,
                "notes": h.notes, "exercise": h.exercise, "durationMin": h.durationMin, "xp": h.xp, "leaf": h.leafKey,
                "hasTreePhoto": h.treePhoto != nil, "hasSelfie": h.selfiePhoto != nil,
            ]
            if let v = h.latitude { r["lat"] = v }
            if let v = h.longitude { r["lng"] = v }
            if let v = h.avgHR { r["avgHR"] = v }
            if let v = h.minHR { r["minHR"] = v }
            if let v = h.maxHR { r["maxHR"] = v }
            if let v = h.respRate { r["respRate"] = v }
            if let v = h.stressStart { r["stressStart"] = v }
            if let v = h.stressEnd { r["stressEnd"] = v }
            if let v = h.bodyBattery { r["bodyBattery"] = v }
            return r
        }
        let actRows: [[String: Any]] = activities.map { a in
            [
                "id": a.id.uuidString, "kind": a.kindRaw, "title": a.displayTitle,
                "start": iso.string(from: a.start), "end": iso.string(from: a.end),
                "distanceM": a.distanceM, "movingSec": a.movingSec, "elevGainM": a.elevGainM, "maxSpeedMps": a.maxSpeed,
                "startPlace": a.startPlace, "endPlace": a.endPlace, "notes": a.notes, "points": a.route.count,
            ]
        }
        let root: [String: Any] = ["exported": iso.string(from: Date()), "hugs": hugRows, "activities": actRows]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rootbound-export.json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
