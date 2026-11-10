import SwiftUI
import UIKit
import SwiftData
import MapKit

@MainActor
struct ActivityDetailView: View {
    @Bindable var activity: Activity
    var isNew = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var showTrim = false
    @State private var probe: RoutePoint?
    @State private var gpxURL: URL?
    #if !TRACK_APP
    @Query(sort: \Hug.date) private var allHugs: [Hug]
    private var strollHugs: [Hug] { allHugs.filter { $0.strollID == activity.id } }
    #endif

    private var coords: [CLLocationCoordinate2D] { activity.route.map(\.coordinate) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                hero
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                if !activity.startPlace.isEmpty || !activity.endPlace.isEmpty {
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            placeRow("Started", activity.startPlace, "circle.fill", .white)
                            placeRow("Ended", activity.endPlace, "flag.checkered", Theme.gold)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(value: Format.distance(activity.distanceM), label: "Distance", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(value: Format.duration(activity.elapsedSec), label: "Total time", symbol: "clock")
                    StatTile(value: Format.paceOrSpeed(distance: activity.distanceM, seconds: max(activity.movingSec, 1), kind: activity.kind),
                             label: activity.kind.isOnFoot ? "Avg pace" : "Avg speed", symbol: "speedometer")
                    StatTile(value: activity.kind.isOnFoot ? Format.elevation(activity.elevGainM) : Format.speed(activity.maxSpeed),
                             label: activity.kind.isOnFoot ? "Climb" : "Top speed",
                             symbol: activity.kind.isOnFoot ? "mountain.2.fill" : "gauge.with.dots.needle.67percent")
                }

                if activity.kind == .drive { speedCard; laneCard }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 8) {
                        ForEach(ActivityKind.available) { k in
                            Button { activity.kind = k } label: {
                                Image(systemName: k.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(activity.kind == k ? Theme.forestDeep : .white)
                                    .background(activity.kind == k ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.07)),
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(k.title)
                        }
                    }
                }

                #if !TRACK_APP
                if !strollHugs.isEmpty {
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: strollHugs.count == 1 ? "1 tree hugged on the way" : "\(strollHugs.count) trees hugged on the way",
                                          symbol: "tree.fill")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(strollHugs) { h in
                                        VStack(spacing: 4) {
                                            PhotoView(data: h.treePhoto ?? h.selfiePhoto)
                                                .frame(width: 76, height: 76)
                                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                            Text(h.treeName).font(Theme.rounded(12, .bold)).lineLimit(1).frame(width: 76)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                #endif

                TextField("", text: $activity.notes, prompt: Text("Notes").foregroundStyle(Theme.textDim), axis: .vertical)
                    .lineLimit(2...6)
                    .font(Theme.rounded(15, .regular))
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if coords.count > 1, let gpxURL {
                    ShareLink(item: gpxURL) {
                        Label("Share route as GPX (Strava, Garmin…)", systemImage: "square.and.arrow.up")
                            .font(Theme.rounded(15, .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                if isNew {
                    Button("Done") { try? context.save(); dismiss() }.buttonStyle(PrimaryButtonStyle())
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash").font(Theme.rounded(15, .bold)).frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                }
                .padding(.horizontal, Theme.pad)
            }
            .padding(.bottom, 130)
        }
        .ignoresSafeArea(edges: isNew ? Edge.Set() : Edge.Set.top)
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if coords.count > 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showTrim = true } label: { Label("Trim start or end", systemImage: "scissors") }
                    } label: {
                        Image(systemName: "pencil.circle.fill").font(.system(size: 22)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Edit")
                }
            }
        }
        .sheet(isPresented: $showTrim) {
            TrimSheet(activity: activity) { startT, endT in
                activity.trim(startT: startT, endT: endT)
                try? context.save()
                gpxURL = GPX.write(activity)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { gpxURL = GPX.write(activity) }
        .onDisappear { try? context.save() }
        .alert("Delete this activity?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let target = activity
                dismiss()
                // Delete after the screen closes so nothing draws a deleted object.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    context.delete(target)
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Full-bleed route map that fades into the page, with the title on top.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if coords.count > 1 {
                    routeMap
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.moss, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
                        Image(systemName: activity.kind.symbol)
                            .font(.system(size: 90, weight: .bold))
                            .foregroundStyle(Theme.leafGradient)
                            .opacity(0.3)
                    }
                }
            }
            .frame(height: isNew ? 320 : 400)
            .overlay {
                LinearGradient(stops: [
                    .init(color: Theme.forestDeep.opacity(isNew ? 0 : 0.5), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: Theme.forestDeep.opacity(0.4), location: 0.65),
                    .init(color: Theme.forestDeep, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isNew { savedBadge }
                if activity.trimmedSec >= 60 || activity.autoFinished { trimBadge }
                HStack(spacing: 8) {
                    Image(systemName: activity.kind.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(width: 26, height: 26)
                        .background(Theme.leafGradient, in: Circle())
                    Text(Format.dayTime(activity.start).uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                TextField("", text: $activity.title, prompt: Text(activity.displayTitle).foregroundStyle(.white))
                    .font(Theme.title(32))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 4)
        }
    }

    /// "Trimmed 8 idle minutes at the end" / "Finished automatically".
    private var trimBadge: some View {
        let mins = Int((activity.trimmedSec / 60).rounded())
        let text = mins >= 1
            ? "Trimmed \(mins) idle minute\(mins == 1 ? "" : "s")\(activity.autoFinished ? " · finished automatically" : "")"
            : "Finished automatically after you stopped"
        return Label(text, systemImage: "scissors")
            .font(Theme.rounded(12, .bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var savedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
            Text("Saved")
            #if !TRACK_APP
            Text("· +\(GameEngine.xp(for: activity)) XP").foregroundStyle(Theme.gold)
            #endif
        }
        .font(Theme.rounded(14, .heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glow.opacity(0.5)))
    }

    /// Lane changes: total, quick cuts, and per 10 miles.
    private var laneCard: some View {
        let lanes = activity.laneChanges
        let cuts = lanes.filter(\.quick).count
        let miles = activity.distanceM / 1609.344
        let per10 = miles > 0.5 ? Double(lanes.count) / miles * 10 : 0
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Lane changes", systemImage: "arrow.left.arrow.right").font(Theme.rounded(16, .heavy)).foregroundStyle(.white)
                HStack(spacing: 0) {
                    laneStat("\(lanes.count)", "changes")
                    laneStat("\(cuts)", "quick cuts")
                    laneStat(per10 > 0 ? String(format: "%.1f", per10) : "—", "per 10 mi")
                }
                Text("Estimated from your phone's motion. Most accurate with the phone mounted.")
                    .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func laneStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.rounded(24, .black)).foregroundStyle(.white).monospacedDigit()
            Text(label.uppercased()).font(Theme.rounded(10, .heavy)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
    }

    /// Speed legend and how much of the drive was over the limit.
    private var speedCard: some View {
        let pts = activity.route
        let zones = SpeedZones.overZones(pts)
        let known = pts.filter { $0.limit > 0 }.count
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ForEach([(SpeedBand.cruise, "Under"), (.fast, "+10"), (.over, "+20"), (.wayOver, "20+")], id: \.1) { b, label in
                        HStack(spacing: 4) {
                            Capsule().fill(b.color).frame(width: 16, height: 5).shadow(color: b.color, radius: 3)
                            Text(label).font(Theme.rounded(11, .bold)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                if known == 0 {
                    Text("No speed limits on this drive, so it's colored by speed alone.")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                } else if zones.isEmpty {
                    Label("Stayed within 5 of the limit the whole way", systemImage: "checkmark.seal.fill")
                        .font(Theme.rounded(14, .bold)).foregroundStyle(SpeedBand.cruise.color)
                } else {
                    let top = zones.map(\.peakOverMph).max() ?? 0
                    let secs = zones.reduce(0) { $0 + $1.seconds }
                    let topShown = Units.metric ? Int((top * 1.609344).rounded()) : Int(top.rounded())
                    Label("\(zones.count) stretch\(zones.count == 1 ? "" : "es") over the limit · \(Format.duration(secs)) total · peak +\(topShown) \(Units.metric ? "km/h" : "mph")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.rounded(13, .bold)).foregroundStyle(SpeedBand.over.color)
                }
            }
        }
    }

    private var routeMap: some View {
        MapReader { proxy in
        Map(initialPosition: .automatic) {
            if let p = probe {
                Annotation("", coordinate: p.coordinate, anchor: .bottom) { SpeedCallout(point: p) }
                    .annotationTitles(.hidden)
            }
            if activity.kind == .drive {
                ForEach(SpeedZones.segments(activity.route)) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.band.color.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.band.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(SpeedZones.overZones(activity.route)) { z in
                    Annotation("", coordinate: z.peak, anchor: .bottom) { OverZoneBadge(overMph: z.peakOverMph) }
                }
                ForEach(activity.laneChanges, id: \.t) { c in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)) { LaneMarker(change: c) }
                        .annotationTitles(.hidden)
                }
            } else {
                MapPolyline(coordinates: coords)
                    .stroke(Theme.glow.opacity(0.35), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: coords)
                    .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let s = coords.first {
                Annotation("Start", coordinate: s) {
                    Circle().fill(.white).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.forestDeep, lineWidth: 3))
                }
            }
            #if !TRACK_APP
            ForEach(strollHugs.filter { $0.coordinate != nil }) { h in
                Annotation(h.treeName, coordinate: h.coordinate!) { TreePin(photo: h.treePhoto, size: 36) }
            }
            #endif
            if let e = coords.last {
                Annotation("Finish", coordinate: e) {
                    Image(systemName: "flag.checkered.circle.fill").font(.system(size: 22))
                        .foregroundStyle(Theme.forestDeep, Theme.gold)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .onTapGesture { pt in
            guard activity.kind == .drive else { return }
            let p = RouteProbe.nearest(activity.route, tap: pt, proxy: proxy)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { probe = p }
            if let p {
                UISelectionFeedbackGenerator().selectionChanged()
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if probe?.t == p.t { withAnimation(.easeOut) { probe = nil } }
                }
            }
        }
        }
    }

    private func placeRow(_ label: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint).frame(width: 18)
            Text(label).font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim).frame(width: 60, alignment: .leading)
            Text(value.isEmpty ? "—" : value).font(Theme.rounded(15, .semibold)).foregroundStyle(.white)
        }
    }
}

enum GPX {
    static func write(_ a: Activity) -> URL? {
        let pts = a.route
        guard pts.count > 1 else { return nil }
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(AppInfo.name)" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escape(a.displayTitle))</name><type>\(a.kind.rawValue)</type><trkseg>

        """
        for p in pts {
            s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lng)\">"
            if p.alt.isFinite { s += "<ele>\(String(format: "%.1f", p.alt))</ele>" }
            s += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time></trkpt>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        let name = "\(AppInfo.name)-\(a.kind.title)-\(Int(a.start.timeIntervalSince1970)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try s.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}


/// Drag the handles to cut idle time (or a wrong-turn start) off a saved recording.
/// The map and numbers update as you drag; nothing changes until you tap Trim.
@MainActor
struct TrimSheet: View {
    let activity: Activity
    var onTrim: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var startT: Double = 0
    @State private var endT: Double = 1
    @State private var loaded = false
    private let pts: [RoutePoint]

    init(activity: Activity, onTrim: @escaping (Double, Double) -> Void) {
        self.activity = activity
        self.onTrim = onTrim
        self.pts = activity.route
    }

    private var lo: Double { pts.first?.t ?? 0 }
    private var hi: Double { pts.last?.t ?? 1 }
    private var kept: [RoutePoint] { pts.filter { $0.t >= startT && $0.t <= endT } }
    private var keptCoords: [CLLocationCoordinate2D] { kept.map(\.coordinate) }
    private var cut: Double { max(0, (startT - lo) + (hi - endT)) }

    var body: some View {
        let s = Activity.stats(kept)
        NavigationStack {
            VStack(spacing: 16) {
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: pts.map(\.coordinate))
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if keptCoords.count > 1 {
                        MapPolyline(coordinates: keptCoords)
                            .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    if let a = keptCoords.first {
                        Annotation("", coordinate: a) { Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(Theme.forestDeep, lineWidth: 2)) }
                    }
                    if let b = keptCoords.last {
                        Annotation("", coordinate: b) { Image(systemName: "flag.checkered.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.gold, .white) }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 14) {
                    handle("Start", value: $startT, range: lo...max(lo + 1, endT - 1), tint: .white)
                    handle("End", value: $endT, range: min(hi - 1, startT + 1)...hi, tint: Theme.gold)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    stat(Format.duration(max(0, endT - startT)), "Time")
                    stat(Format.distance(s.distance), "Distance")
                    stat(cut >= 60 ? "−\(Int((cut / 60).rounded())) min" : "—", "Cut")
                }

                Spacer(minLength: 0)
                Button {
                    onTrim(startT, endT)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } label: {
                    Text(cut >= 1 ? "Trim" : "Nothing to trim").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cut < 1 || kept.count < 2)
            }
            .padding(Theme.pad)
            .forestScreen()
            .navigationTitle("Trim recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                startT = lo
                // Suggest cutting the idle tail if there is one.
                endT = RouteTracker.idleTailStart(pts, kind: activity.kind).map { max(lo + 1, $0) } ?? hi
            }
        }
    }

    private func handle(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.rounded(13, .heavy)).foregroundStyle(Theme.textDim)
                Spacer()
                Text(Date(timeIntervalSince1970: value.wrappedValue), style: .time)
                    .font(Theme.rounded(14, .heavy)).foregroundStyle(tint).monospacedDigit()
            }
            Slider(value: value, in: range).tint(tint)
                .accessibilityLabel("\(label) time")
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(Theme.rounded(18, .black)).foregroundStyle(.white).monospacedDigit().contentTransition(.numericText())
            Text(l.uppercased()).font(Theme.rounded(10, .heavy)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
