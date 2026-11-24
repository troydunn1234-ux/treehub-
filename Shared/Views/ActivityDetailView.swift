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
    #if TRACK_APP
    @State private var showRecap = false
    @ObservedObject private var groups = GroupHistory.shared
    // Map-first layout
    @State var sheetDetent: TripSheetDetent = .peek
    @State var sheetDrag: CGFloat = 0
    @State var headerHeight: CGFloat = 150
    @State var camera: MapCameraPosition = .automatic
    @State var visibleSpan: Double?
    @AppStorage("roamr.tripMapStyle.v2") var mapStyleRaw = TripMapStyle.night.rawValue
    #endif
    #if !TRACK_APP
    @Query(sort: \Hug.date) private var allHugs: [Hug]
    private var strollHugs: [Hug] { allHugs.filter { $0.strollID == activity.id } }
    #endif

    /// The route, decoded once (and again only after a trim or type change), not on every redraw: the page redraws
    /// on every frame of a sheet drag, and decoding a long drive each time made it stutter.
    @State private var routeCache = TripRouteCache()
    private var route: TripRouteCache { routeCache.load(activity) }
    private var coords: [CLLocationCoordinate2D] { route.coords }

    var body: some View {
        layout
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if coords.count > 1, let gpxURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: gpxURL, preview: SharePreview(activity.displayTitle, image: Image(systemName: activity.kind.symbol))) {
                        toolbarIcon("square.and.arrow.up.circle.fill")
                    }
                    .accessibilityLabel("Share GPX")
                }
            }
            if coords.count > 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showTrim = true } label: { Label("Trim start or end", systemImage: "scissors") }
                    } label: {
                        toolbarIcon("pencil.circle.fill")
                    }
                    .accessibilityLabel("Edit")
                }
            }
        }
        #if TRACK_APP
        .onAppear {
            if TrackDemo.open == "recap" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showRecap = true } }
            if isNew { sheetDetent = .medium }
        }
        .sheet(isPresented: $showRecap) {
            RecapShareView(activity: activity)
                .presentationDragIndicator(.visible)
        }
        #endif
        .sheet(isPresented: $showTrim) {
            TrimSheet(activity: activity, points: route.points) { startT, endT in
                activity.trim(startT: startT, endT: endT)
                try? context.save()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // The GPX file is built off the main thread, again after a trim.
        .task(id: route.version) {
            let r = route
            gpxURL = await GPX.file(points: r.points, title: activity.displayTitle, kind: activity.kind, start: activity.start)
        }
        .onDisappear { try? context.save() }
        .alert("Delete this activity?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

    @ViewBuilder private var layout: some View {
        #if TRACK_APP
        mapFirstLayout
        #else
        classicLayout
        #endif
    }

    @ViewBuilder private func toolbarIcon(_ name: String) -> some View {
        #if TRACK_APP
        // Dark disc behind a white glyph so it reads over a bright map.
        Image(systemName: name).font(.system(size: 26))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.55))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        #else
        Image(systemName: name).font(.system(size: 22)).foregroundStyle(.white)
        #endif
    }

    private var placesCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                placeRow("Started", activity.startPlace, "circle.fill", .white)
                placeRow("Ended", activity.endPlace, "flag.checkered", Theme.gold)
            }
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: Format.distance(activity.distanceM), label: "Distance", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            StatTile(value: Format.duration(activity.elapsedSec), label: "Total time", symbol: "clock")
            StatTile(value: Format.paceOrSpeed(distance: activity.distanceM, seconds: max(activity.movingSec, 1), kind: activity.kind),
                     label: activity.kind.isOnFoot ? "Avg pace" : "Avg speed", symbol: "speedometer")
            StatTile(value: activity.kind.isOnFoot ? Format.elevation(activity.elevGainM) : Format.speed(activity.maxSpeed),
                     label: activity.kind.isOnFoot ? "Climb" : "Top speed",
                     symbol: activity.kind.isOnFoot ? "mountain.2.fill" : "gauge.with.dots.needle.67percent")
        }
    }

    /// Kind picker, notes, recap / GPX sharing, Done and Delete: the rest of the page, same in both layouts.
    @ViewBuilder private var lowerSections: some View {
                #if !TRACK_APP
                // Roamr is drive-only, so its trip page has no type picker (old walks keep their type as saved).
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 8) {
                        ForEach(ActivityKind.available) { k in
                            Button { activity.applyKind(k) } label: {
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
                            .accessibilityAddTraits(activity.kind == k ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: activity.kindRaw)
                }
                #endif

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

                #if TRACK_APP
                // Tree hugs (Rootbound) and breathwork (Still Pointz) on and right after this trip (TripConnections.swift).
                TripConnectionsSection(tripID: activity.id, kind: activity.kind, start: activity.start, end: activity.end)
                TripTreesCard(tripID: activity.id, kind: activity.kind)
                #endif

                TextField("", text: $activity.notes, prompt: Text("Notes").foregroundStyle(Theme.textDim), axis: .vertical)
                    .lineLimit(2...6)
                    .font(Theme.rounded(15, .regular))
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                #if TRACK_APP
                Button {
                    showRecap = true
                } label: {
                    Label("Share recap card", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(PrimaryButtonStyle(gradient: isNew ? Theme.goldGradient : Theme.leafGradient))
                .sensoryFeedback(.impact(weight: .light), trigger: showRecap)
                .accessibilityHint("Makes a picture of this trip's map and stats to post or send")
                #endif

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

    /// Rootbound (and the original Roamr) layout: hero map on top, everything else scrolls under it.
    private var classicLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                hero
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    if !activity.startPlace.isEmpty || !activity.endPlace.isEmpty { placesCard }
                    statGrid
                    if activity.kind == .drive { speedCard; laneCard }
                    lowerSections
                }
                .padding(.horizontal, Theme.pad)
            }
            .padding(.bottom, 130)
        }
        .ignoresSafeArea(edges: isNew ? Edge.Set() : Edge.Set.top)
        .scrollIndicators(.hidden)
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
                    .accessibilityLabel("Title")
                #if TRACK_APP
                if let g = groups.log(for: activity.id) {
                    Label(g.withLabel, systemImage: "person.2.fill")
                        .font(Theme.rounded(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Go together \(g.withLabel)")
                }
                #endif
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
        let lanes = route.laneChanges
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
        let pts = route.points
        let zones = route.overZones
        let known = pts.contains { $0.limit > 0 } ? 1 : 0
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
                ForEach(route.segments) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.band.color.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.band.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(route.overZones) { z in
                    Annotation("", coordinate: z.peak, anchor: .bottom) { OverZoneBadge(overMph: z.peakOverMph) }
                }
                ForEach(route.laneChanges, id: \.t) { c in
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
            let p = RouteProbe.nearest(route.points, tap: pt, proxy: proxy)
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

#if TRACK_APP
// MARK: - Roamr: map-first trip detail

enum TripSheetDetent: Int, CaseIterable { case peek, medium, large }

enum TripMapStyle: Int, CaseIterable, Identifiable {
    case day, night, satellite, hybrid
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .night: String(localized: "Night")
        case .satellite: String(localized: "Satellite")
        case .hybrid: String(localized: "Hybrid")
        }
    }
    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .night: "moon.fill"
        case .satellite: "globe.americas.fill"
        case .hybrid: "map.fill"
        }
    }
    var style: MapStyle {
        switch self {
        case .day, .night: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }
}

private struct TripHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Nearby over-the-limit bubbles merged into one so they don't pile up when zoomed out.
private struct ZoneCluster: Identifiable {
    let id: Int
    let coord: CLLocationCoordinate2D
    let peakOverMph: Double
    var count: Int
}

extension ActivityDetailView {
    private var tripMapStyle: TripMapStyle { TripMapStyle(rawValue: mapStyleRaw) ?? .night }

    /// Room the app's floating tab bar takes at the bottom (it stays on screen over pushed pages).
    private var tabBarReserve: CGFloat { isNew ? 0 : 84 }

    /// The map fills the screen; stats float on its edge; details live in a draggable sheet.
    var mapFirstLayout: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets
            let fullW = geo.size.width + inset.leading + inset.trailing
            let fullH = geo.size.height + inset.top + inset.bottom
            let landscape = fullW > fullH
            let sheetW = landscape ? min(440, fullW * 0.48) : fullW
            let heights = sheetHeights(fullH: fullH, top: inset.top, bottom: inset.bottom, landscape: landscape)
            let base = heights[sheetDetent.rawValue]
            let live = min(max(base - sheetDrag, heights[0]), heights[2])
            // Where the route is fitted: below the nav bar, above the sheet (or beside it in landscape), clear of the stat rail.
            let showRail = sheetDetent == .peek || landscape
            let mapInsets = EdgeInsets(top: inset.top + 8,
                                       leading: (landscape ? sheetW : 0) + inset.leading + 16,
                                       bottom: (landscape ? tabBarReserve : base) + 16,
                                       trailing: inset.trailing + (showRail ? 96 : 16))

            ZStack(alignment: .bottomLeading) {
                Group {
                    if coords.count > 1 { bigMap.safeAreaPadding(mapInsets) } else { noRouteBackdrop }
                }
                .frame(width: fullW, height: fullH)

                // Light scrim only behind the status bar / back button, never over the route.
                LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: inset.top + 24)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                if showRail {
                    statRail
                        .padding(.top, inset.top + 10)
                        .padding(.trailing, inset.trailing + 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if sheetDetent != .large && coords.count > 1 {
                    mapButtons
                        .padding(.leading, (landscape ? sheetW : 0) + inset.leading + 12)
                        .padding(.bottom, (landscape ? tabBarReserve : live) + 12)
                        .transition(.opacity)
                }

                tripSheet(height: live, heights: heights, bottomInset: inset.bottom)
                    .frame(width: sheetW)
                    .padding(.leading, landscape ? inset.leading + 8 : 0)
            }
            .frame(width: fullW, height: fullH)
            .ignoresSafeArea()
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: sheetDetent)
            .onPreferenceChange(TripHeaderHeightKey.self) { h in
                if h > 0, abs(h - headerHeight) > 0.5 { headerHeight = h }
            }
        }
    }

    /// Peek (title + date + start → end), medium (stats + speeding), large (everything).
    private func sheetHeights(fullH: CGFloat, top: CGFloat, bottom: CGFloat, landscape: Bool) -> [CGFloat] {
        let large = fullH - top - (landscape ? 4 : 10)
        let peek = min(headerHeight + bottom + tabBarReserve, large)
        let medium = min(max(peek + 250, fullH * 0.55), large)
        return [peek, medium, large]
    }

    private var noRouteBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
            Image(systemName: activity.kind.symbol)
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(Theme.leafGradient)
                .opacity(0.3)
        }
    }

    // MARK: Map

    private var routeLatSpan: Double { route.latSpan }

    private func clusters(_ zones: [OverZone]) -> [ZoneCluster] {
        // Roughly one bubble's height (~8% of the visible map) in degrees.
        let span = visibleSpan ?? routeLatSpan * 1.6
        let dLat = span * 0.08
        var out: [ZoneCluster] = []
        for z in zones.sorted(by: { $0.peakOverMph > $1.peakOverMph }) {
            let dLng = dLat / max(cos(z.peak.latitude * .pi / 180), 0.2)
            if let i = out.firstIndex(where: { abs($0.coord.latitude - z.peak.latitude) < dLat && abs($0.coord.longitude - z.peak.longitude) < dLng * 1.6 }) {
                out[i].count += 1
            } else {
                out.append(ZoneCluster(id: z.id, coord: z.peak, peakOverMph: z.peakOverMph, count: 1))
            }
        }
        return out
    }

    /// Turn / lane-change icons only once you've zoomed in (or when there are just a few).
    private var showLaneMarkers: Bool {
        let n = route.laneChanges.count
        if n <= 6 { return true }
        guard let v = visibleSpan else { return false }
        return v < routeLatSpan * 0.5
    }

    private var bigMap: some View {
        let night = tripMapStyle == .night
        let casing: Color = night ? .black.opacity(0.75) : .white
        return MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                if activity.kind == .drive {
                    MapPolyline(coordinates: coords)
                        .stroke(casing, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    ForEach(route.segments) { seg in
                        MapPolyline(coordinates: seg.coords)
                            .stroke(seg.band.color, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }
                    if showLaneMarkers {
                        ForEach(route.laneChanges, id: \.t) { c in
                            Annotation("", coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)) {
                                LaneMarker(change: c).scaleEffect(0.72)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    ForEach(clusters(route.overZones)) { z in
                        Annotation("", coordinate: z.coord, anchor: .bottom) {
                            OverZoneBadge(overMph: z.peakOverMph)
                                .scaleEffect(0.88, anchor: .bottom)
                                .overlay(alignment: .topTrailing) {
                                    if z.count > 1 {
                                        Text("×\(z.count)")
                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Capsule().fill(.black.opacity(0.85)))
                                            .offset(x: 8, y: -6)
                                    }
                                }
                                .accessibilityLabel(z.count > 1 ? "\(z.count) stretches over the limit" : "Over the limit")
                        }
                        .annotationTitles(.hidden)
                    }
                } else {
                    MapPolyline(coordinates: coords)
                        .stroke(casing, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                if let s = coords.first {
                    Annotation("Start", coordinate: s) {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color(red: 0.1, green: 0.65, blue: 0.3), lineWidth: 4))
                            .shadow(color: .black.opacity(0.35), radius: 3)
                    }
                }
                if let e = coords.last {
                    Annotation("Finish", coordinate: e) {
                        Image(systemName: "flag.checkered.circle.fill").font(.system(size: 24))
                            .foregroundStyle(Theme.forestDeep, Theme.gold)
                            .shadow(color: .black.opacity(0.35), radius: 3)
                    }
                }
                if let p = probe {
                    Annotation("", coordinate: p.coordinate, anchor: .bottom) {
                        SpeedCallout(point: p).environment(\.colorScheme, .dark)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(tripMapStyle.style)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .environment(\.colorScheme, night ? .dark : .light)
            .onMapCameraChange(frequency: .onEnd) { ctx in
                visibleSpan = ctx.region.span.latitudeDelta
            }
            .onTapGesture { pt in
                guard activity.kind == .drive else { return }
                let p = RouteProbe.nearest(route.points, tap: pt, proxy: proxy)
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

    /// Map style menu + recenter, floating just above the sheet.
    private var mapButtons: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Map style", selection: $mapStyleRaw) {
                    ForEach(TripMapStyle.allCases) { s in
                        Label(s.title, systemImage: s.symbol).tag(s.rawValue)
                    }
                }
            } label: {
                mapButtonFace(tripMapStyle.symbol)
            }
            .accessibilityLabel("Map style, \(tripMapStyle.title)")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeInOut(duration: 0.6)) { camera = .automatic }
            } label: {
                mapButtonFace("scope")
            }
            .accessibilityLabel("Recenter on route")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func mapButtonFace(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .background(Theme.forestDeep.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .environment(\.colorScheme, .dark)
    }

    // MARK: Stat rail

    private var statRail: some View {
        let onFoot = activity.kind.isOnFoot
        return VStack(alignment: .leading, spacing: 10) {
            railItem(Format.distance(activity.distanceM), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
            railItem(Format.duration(activity.elapsedSec), "Time", "clock")
            railItem(Format.paceOrSpeed(distance: activity.distanceM, seconds: max(activity.movingSec, 1), kind: activity.kind),
                     onFoot ? "Pace" : "Avg", "speedometer")
            if !onFoot { railItem(Format.speed(activity.maxSpeed), "Top", "gauge.with.dots.needle.67percent") }
            if onFoot { railItem(Format.elevation(activity.elevGainM), "Climb", "mountain.2.fill") }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(maxWidth: 104, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Theme.forestDeep.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .combine)
        .onTapGesture { sheetDetent = .medium }
    }

    private func railItem(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.glow)
                Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Theme.textDim)
            }
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: Sheet

    private func tripSheet(height: CGFloat, heights: [CGFloat], bottomInset: CGFloat) -> some View {
        let drag = DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in sheetDrag = v.translation.height }
            .onEnded { v in
                let base = heights[sheetDetent.rawValue]
                let projected = base - v.predictedEndTranslation.height
                let target = TripSheetDetent.allCases.min { abs(heights[$0.rawValue] - projected) < abs(heights[$1.rawValue] - projected) } ?? .peek
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    sheetDetent = target
                    sheetDrag = 0
                }
            }

        return VStack(spacing: 0) {
            sheetHeader
                .background(GeometryReader { g in Color.clear.preference(key: TripHeaderHeightKey.self, value: g.size.height) })
                .contentShape(Rectangle())
                .gesture(drag)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    statGrid
                    if activity.kind == .drive { speedCard; laneCard }
                    if !activity.startPlace.isEmpty || !activity.endPlace.isEmpty { placesCard }
                    lowerSections
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 4)
                .padding(.bottom, tabBarReserve + bottomInset + 24)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(sheetDetent != .large)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.forestDeep.opacity(0.82))
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: -4)
        .environment(\.colorScheme, .dark)
        // Below full height the whole sheet drags; at full height the content scrolls and the header drags.
        .gesture(drag, including: sheetDetent == .large ? .subviews : .all)
    }

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                let next = TripSheetDetent(rawValue: (sheetDetent.rawValue + 1) % 3) ?? .peek
                sheetDetent = next
            } label: {
                Capsule().fill(.white.opacity(0.4)).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trip details")
            .accessibilityValue(sheetDetent == .peek ? "Collapsed" : sheetDetent == .medium ? "Half" : "Expanded")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: sheetDetent = TripSheetDetent(rawValue: min(sheetDetent.rawValue + 1, 2)) ?? .large
                case .decrement: sheetDetent = TripSheetDetent(rawValue: max(sheetDetent.rawValue - 1, 0)) ?? .peek
                @unknown default: break
                }
            }

            HStack(spacing: 8) {
                Image(systemName: activity.kind.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 24, height: 24)
                    .background(Theme.leafGradient, in: Circle())
                Text(Format.dayTime(activity.start).uppercased())
                    .font(.system(size: Theme.scaled(11), weight: .heavy, design: .rounded)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isNew {
                    Button("Done") { try? context.save(); dismiss() }
                        .font(Theme.rounded(14, .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Theme.leafGradient, in: Capsule())
                }
            }

            TextField("", text: $activity.title, prompt: Text(activity.displayTitle).foregroundStyle(.white))
                .font(Theme.title(26))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityLabel("Title")

            if !activity.startPlace.isEmpty || !activity.endPlace.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Text(activity.startPlace.isEmpty ? "—" : activity.startPlace).lineLimit(1)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textDim)
                    Image(systemName: "flag.checkered").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
                    Text(activity.endPlace.isEmpty ? "—" : activity.endPlace).lineLimit(1)
                }
                .font(Theme.rounded(13, .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("From \(activity.startPlace) to \(activity.endPlace)")
            }

            let together = groups.log(for: activity.id)
            let trimmed = activity.trimmedSec >= 60 || activity.autoFinished
            if isNew || trimmed || together != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // "Drive saved · 12.4 mi": the seal pops and the distance rolls up (NightDrive.swift).
                        if isNew { DriveSavedBadge(distanceM: activity.distanceM) }
                        if let g = together {
                            Label(g.withLabel, systemImage: "person.2.fill")
                                .font(Theme.rounded(13, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.white.opacity(0.12), in: Capsule())
                                .accessibilityLabel("Go together \(g.withLabel)")
                        }
                        if trimmed { trimBadge }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.bottom, 12)
    }
}
#endif

enum GPX {
    static func write(_ a: Activity) -> URL? {
        build(points: a.route, title: a.displayTitle, kind: a.kind, start: a.start, appName: AppInfo.name)
    }

    /// Same file, built off the main thread (a long route is thousands of formatted points).
    static func file(points: [RoutePoint], title: String, kind: ActivityKind, start: Date) async -> URL? {
        guard points.count > 1 else { return nil }
        let app = AppInfo.name
        return await Task.detached(priority: .utility) {
            build(points: points, title: title, kind: kind, start: start, appName: app)
        }.value
    }

    private static func build(points pts: [RoutePoint], title: String, kind: ActivityKind, start: Date, appName: String) -> URL? {
        guard pts.count > 1 else { return nil }
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(appName)" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><time>\(iso.string(from: start))</time></metadata>
        <trk><name>\(escape(title))</name><type>\(kind.rawValue)</type><trkseg>

        """
        for p in pts {
            s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lng)\">"
            if p.alt.isFinite { s += "<ele>\(String(format: "%.1f", p.alt))</ele>" }
            s += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time></trkpt>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        let name = "\(appName)-\(kind.title)-\(Int(start.timeIntervalSince1970)).gpx"
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
    private let allCoords: [CLLocationCoordinate2D]
    /// Distance from the first point to each point, counted the way `Activity.stats` counts it, so the kept
    /// distance under the sliders is one subtraction instead of re-measuring the route on every drag frame.
    private let cumulative: [Double]

    init(activity: Activity, points: [RoutePoint]? = nil, onTrim: @escaping (Double, Double) -> Void) {
        self.activity = activity
        self.onTrim = onTrim
        let pts = points ?? activity.route
        self.pts = pts
        self.allCoords = pts.map(\.coordinate)
        self.cumulative = TrimSheet.cumulativeDistance(pts)
    }

    /// cum[i] = Activity.stats(pts[0...i]).distance, for every i.
    static func cumulativeDistance(_ pts: [RoutePoint]) -> [Double] {
        guard !pts.isEmpty else { return [] }
        var out = [0.0]
        out.reserveCapacity(pts.count)
        var d = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dt = b.t - a.t
            if dt > 0 {
                let step = CLLocation(latitude: a.lat, longitude: a.lng).distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
                if step / dt <= 95 { d += step }
            }
            out.append(d)
        }
        return out
    }

    private var lo: Double { pts.first?.t ?? 0 }
    private var hi: Double { pts.last?.t ?? 1 }
    /// Indices of the points between the two handles (empty when none).
    private var keptRange: ClosedRange<Int>? {
        guard let a = pts.firstIndex(where: { $0.t >= startT }), let b = pts.lastIndex(where: { $0.t <= endT }), a <= b else { return nil }
        return a...b
    }
    private var keptCount: Int { keptRange?.count ?? 0 }
    private var keptCoords: [CLLocationCoordinate2D] { keptRange.map { Array(allCoords[$0]) } ?? [] }
    private var keptDistance: Double { keptRange.map { cumulative[$0.upperBound] - cumulative[$0.lowerBound] } ?? 0 }
    private var cut: Double { max(0, (startT - lo) + (hi - endT)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: allCoords)
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
                    stat(Format.distance(keptDistance), "Distance")
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
                .disabled(cut < 1 || keptCount < 2)
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


/// A trip's decoded route and the map geometry built from it (speed-colored segments, over-the-limit stretches,
/// lane changes), made once per route instead of on every redraw of the trip page.
@MainActor
final class TripRouteCache {
    private var key: String?
    private(set) var points: [RoutePoint] = []
    private(set) var coords: [CLLocationCoordinate2D] = []
    private(set) var segments: [SpeedSegment] = []
    private(set) var overZones: [OverZone] = []
    private(set) var laneChanges: [LaneChange] = []
    /// North-south size of the route in degrees (at least 0.002).
    private(set) var latSpan: Double = 0.01
    /// Goes up whenever the route is rebuilt (after a trim or a type change).
    private(set) var version = 0

    /// Rebuilds only when the stored route, lane changes, end time or type changed.
    @discardableResult
    func load(_ a: Activity) -> TripRouteCache {
        let k = "\(a.routeData?.count ?? -1)|\(a.laneChangesData?.count ?? -1)|\(a.end.timeIntervalSince1970)|\(a.kindRaw)"
        guard k != key else { return self }
        key = k
        version += 1
        points = a.route
        coords = points.map(\.coordinate)
        let drive = a.kind == .drive
        segments = drive ? SpeedZones.segments(points) : []
        overZones = drive ? SpeedZones.overZones(points) : []
        laneChanges = a.laneChanges
        let lats = coords.map(\.latitude)
        if let lo = lats.min(), let hi = lats.max() { latSpan = max(hi - lo, 0.002) } else { latSpan = 0.01 }
        return self
    }
}
