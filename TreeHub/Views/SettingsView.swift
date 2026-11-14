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
    @State private var csvURLs: [URL] = []
    @State private var gpxURL: URL?
    @State private var showPlans = false
    @State private var plansContext: String?
    @ObservedObject private var unlock = Unlock.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { plansContext = nil; showPlans = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.gold)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.gold.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Rootbound Pro").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                Text(unlock.isPro ? "Unlocked · thank you!"
                                     : unlock.priceText.isEmpty ? "Tree selfies, insights, CSV + GPX export"
                                     : "One payment of \(unlock.priceText), no subscription")
                                    .font(.system(size: 12.5, design: .rounded)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: unlock.isPro ? "checkmark.seal.fill" : "chevron.right")
                                .font(.system(size: unlock.isPro ? 17 : 12, weight: .bold))
                                .foregroundStyle(unlock.isPro ? Theme.glow : .secondary)
                        }
                    }
                    Button {
                        Task { await unlock.restore() }
                    } label: {
                        HStack {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                            if unlock.busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(unlock.busy)
                    if let m = unlock.message, !showPlans {
                        Text(m).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Logging hugs, the map, your grove, strolls, every badge and leaf, and the JSON export are free forever.")
                }
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
                    if unlock.isPro {
                        if !csvURLs.isEmpty {
                            ShareLink(items: csvURLs) { Label("Export spreadsheet (CSV)", systemImage: "tablecells") }
                        }
                        if let gpxURL {
                            ShareLink(item: gpxURL) { Label("Export routes (GPX)", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        } else if !activities.isEmpty {
                            Label("No recorded routes to export yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        lockedRow("Export spreadsheet (CSV)", symbol: "tablecells", context: "CSV export")
                        lockedRow("Export routes (GPX)", symbol: "point.topleft.down.to.point.bottomright.curvepath", context: "GPX export")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything stays on your iPhone and syncs to your private iCloud. Nobody else can see it. \(hugs.count) hugs · \(activities.count) activities.")
                }
                Section("About") {
                    MoreAppsRow()
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ForestBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { writeExports() }
            .onChange(of: unlock.isPro) { _, _ in writeExports() }
        }
        .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: plansContext)
    }

    private func lockedRow(_ title: String, symbol: String, context: String) -> some View {
        Button { plansContext = context; showPlans = true } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                ProLockBadge(tint: Theme.gold)
            }
        }
    }

    private func writeExports() {
        exportURL = DataExport.write(hugs: hugs, activities: activities)
        if unlock.isPro {
            csvURLs = DataExport.csv(hugs: hugs, activities: activities)
            gpxURL = DataExport.gpx(activities: activities)
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

// MARK: - Rootbound Pro exports

extension DataExport {
    private static func cell(_ v: String) -> String {
        if v.contains(",") || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
    private static func num(_ v: Double?, _ f: String = "%.1f") -> String { v.map { String(format: f, $0) } ?? "" }

    /// Two spreadsheet-ready files: every hug, and every stroll or hike.
    static func csv(hugs: [Hug], activities: [Activity]) -> [URL] {
        let iso = ISO8601DateFormatter()
        var h = "date,tree,species,place,lat,lng,minutes,barefoot,tags,weather,mood_before,mood_after,exercise,avg_hr,min_hr,max_hr,resp_rate,stress_start,stress_end,body_battery,xp,leaf,notes\n"
        for x in hugs {
            let row: [String] = [
                iso.string(from: x.date), x.treeName, x.species, x.placeName,
                num(x.latitude, "%.6f"), num(x.longitude, "%.6f"), num(x.durationMin),
                x.barefoot ? "yes" : "no", x.tags.joined(separator: " "), x.weather,
                x.moodBefore > 0 ? "\(x.moodBefore)" : "", x.moodAfter > 0 ? "\(x.moodAfter)" : "", x.exercise,
                num(x.avgHR, "%.0f"), num(x.minHR, "%.0f"), num(x.maxHR, "%.0f"), num(x.respRate),
                num(x.stressStart, "%.0f"), num(x.stressEnd, "%.0f"), num(x.bodyBattery, "%.0f"),
                "\(x.xp)", LeafType.find(x.leafKey)?.name ?? x.leafKey, x.notes,
            ]
            h += row.map(cell).joined(separator: ",") + "\n"
        }
        var a = "start,end,kind,title,distance_m,moving_sec,elev_gain_m,max_speed_mps,start_place,end_place,points,notes\n"
        for x in activities {
            let row: [String] = [
                iso.string(from: x.start), iso.string(from: x.end), x.kindRaw, x.displayTitle,
                num(x.distanceM, "%.0f"), num(x.movingSec, "%.0f"), num(x.elevGainM, "%.0f"), num(x.maxSpeed, "%.2f"),
                x.startPlace, x.endPlace, "\(x.route.count)", x.notes,
            ]
            a += row.map(cell).joined(separator: ",") + "\n"
        }
        let dir = FileManager.default.temporaryDirectory
        var out: [URL] = []
        for (name, text) in [("Rootbound-hugs.csv", h), ("Rootbound-strolls.csv", a)] {
            let url = dir.appendingPathComponent(name)
            if (try? Data(text.utf8).write(to: url)) != nil { out.append(url) }
        }
        return out
    }

    private static func xml(_ v: String) -> String {
        v.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One GPX file with a track per recorded stroll or hike. Nil when nothing has a route.
    static func gpx(activities: [Activity]) -> URL? {
        let withRoutes = activities.filter { !$0.route.isEmpty }
        guard !withRoutes.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        var g = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Rootbound\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for x in withRoutes {
            g += "  <trk>\n    <name>\(xml(x.displayTitle))</name>\n    <type>\(xml(x.kindRaw))</type>\n    <trkseg>\n"
            for p in x.route {
                g += String(format: "      <trkpt lat=\"%.7f\" lon=\"%.7f\">", p.lat, p.lng)
                if p.alt.isFinite { g += String(format: "<ele>%.1f</ele>", p.alt) }
                g += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time></trkpt>\n"
            }
            g += "    </trkseg>\n  </trk>\n"
        }
        g += "</gpx>\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Rootbound-routes.gpx")
        do { try Data(g.utf8).write(to: url); return url } catch { return nil }
    }
}
