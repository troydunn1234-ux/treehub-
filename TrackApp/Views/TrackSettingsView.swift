import SwiftUI
import SwiftData

@MainActor
struct TrackSettingsView: View {
    @AppStorage("useMetric") private var useMetric = false
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
                            healthStatus = ok ? "Done. Your Garmin and Whoop workouts show up on the Track tab." : "Apple Health isn't available on this device."
                        }
                    }
                    if !healthStatus.isEmpty { Text(healthStatus).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Garmin · Whoop")
                } footer: {
                    Text("In Garmin Connect: More → Settings → Connected Apps → Apple Health. Roamr then lists those workouts so you can add them with one tap.")
                }
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export my trips (JSON)", systemImage: "square.and.arrow.up") }
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Stored on your iPhone and your private iCloud only. \(activities.count) trips.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .forestScreen()
            .navigationTitle("Settings")
            .onAppear { exportURL = Self.export(activities) }
            .padding(.bottom, 80)
        }
    }

    static func export(_ activities: [Activity]) -> URL? {
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = activities.map { a in
            [
                "id": a.id.uuidString, "kind": a.kindRaw, "title": a.displayTitle,
                "start": iso.string(from: a.start), "end": iso.string(from: a.end),
                "distanceM": a.distanceM, "movingSec": a.movingSec, "elevGainM": a.elevGainM, "maxSpeedMps": a.maxSpeed,
                "startPlace": a.startPlace, "endPlace": a.endPlace, "notes": a.notes,
                "route": a.route.map { [$0.lat, $0.lng] },
            ]
        }
        let root: [String: Any] = ["exported": iso.string(from: Date()), "activities": rows]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Roamr-export.json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
