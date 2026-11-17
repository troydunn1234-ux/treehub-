import SwiftUI
import UIKit
import SwiftData
import MapKit

@MainActor
struct TrackView: View {
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    #if !TRACK_APP
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    #endif
    /// Opens the hug logger (TreeHub only).
    var onHug: (() -> Void)? = nil

    @State private var chosenKind: ActivityKind = .walk
    @Namespace private var kindNS
    // Idle map: a still picture around your last known spot (see idleCamera). It never asks for live
    // location, so the location arrow stays off until you press Start.
    @State private var camera: MapCameraPosition = .automatic
    @State private var justFinished: Activity?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var healthWorkouts: [HealthService.WorkoutInfo] = []
    @State private var healthLoading = false
    @State private var healthLoaded = false
    @State private var chaseCam = true
    @State private var mapHeading: Double = 0
    @State private var mapPitch: Double = 0
    @State private var probe: RoutePoint?
    @State private var nav = Navigator.shared
    @State private var showDirections = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if tracker.isActive { liveView } else { idleView }
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
            .sheet(item: $justFinished) { a in
                NavigationStack { ActivityDetailView(activity: a, isNew: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("roamr.autoFinish"))) { _ in
                if tracker.isActive { finish(auto: true) }
            }
            .sheet(isPresented: $showDirections) {
                DirectionsSheet(nav: nav, origin: tracker.points.last?.coordinate, onGo: startNavigation)
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // Screenshots (-demo -nav): follow a fake route along the demo drive.
                if Navigator.demo, nav.phase == .idle {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        Task { await nav.plan(to: Navigator.demoPlace, from: nil); startNavigation() }
                    }
                }
            }
        }
    }

    // MARK: Idle

    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                mapHero
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    if tracker.denied { deniedCard }
                    kindPicker
                    startButton
                    Label("Keeps recording with your phone locked", systemImage: "lock.fill")
                        .font(Theme.rounded(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                    if !activities.isEmpty { recentList }
                    #if TRACK_APP
                    healthSection
                    #endif
                }
                .padding(.horizontal, Theme.pad)
            }
            .padding(.bottom, 130)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .onAppear {
            #if !TRACK_APP
            if tracker.authorization == .notDetermined { tracker.requestPermission() }
            #endif
            // Roamr asks for location in context (intro, or the first tap on Start).
            // Back from a recording: drop any follow-me camera so the map stops using location.
            camera = idleCamera
        }
    }

    /// A fixed, tilted view of where the phone last was (iOS's cached fix: reading it doesn't turn GPS on).
    private var idleCamera: MapCameraPosition {
        guard let c = tracker.lastKnownCoordinate else { return .automatic }
        return .camera(MapCamera(centerCoordinate: c, distance: 2200, heading: 0, pitch: 45))
    }

    /// Recording: follow the GPS dot. Paused: GPS is off, so hold still on the last point instead
    /// of asking the map for live location (which would keep the location arrow on).
    private var followCamera: MapCameraPosition {
        if tracker.state == .recording { return .userLocation(followsHeading: false, fallback: .automatic) }
        guard let c = tracker.lastKnownCoordinate else { return .automatic }
        return .camera(MapCamera(centerCoordinate: c, distance: tracker.kind == .drive ? 1400 : 700, heading: mapHeading, pitch: 45))
    }

    private var screenTitle: String {
        #if TRACK_APP
        return "Track"
        #else
        return "Stroll"
        #endif
    }

    private var screenSubtitle: String {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let week = activities.filter { $0.start > weekAgo }
        let dist = week.reduce(0.0) { $0 + $1.distanceM }
        #if TRACK_APP
        return week.isEmpty ? "Where to today?" : "This week: \(Format.distance(dist)) · \(week.count) trip\(week.count == 1 ? "" : "s")"
        #else
        return week.isEmpty ? "Wander to your trees. Hugs along the way get pinned on your route."
            : "This week: \(Format.distance(dist)) · \(week.count) stroll\(week.count == 1 ? "" : "s")"
        #endif
    }

    /// Full-bleed live map that fades into the page, with the title on top.
    private var mapHero: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $camera)
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .frame(height: 400)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: Theme.forestDeep.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.28),
                        .init(color: Theme.forestDeep.opacity(0.55), location: 0.7),
                        .init(color: Theme.forestDeep, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(screenTitle)
                    .font(Theme.title(44))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                Text(screenSubtitle)
                    .font(Theme.rounded(14, .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 8)
        }
        #if TRACK_APP
        .overlay(alignment: .topTrailing) {
            DirectionsButton { showDirections = true }
                .padding(.top, 58).padding(.trailing, 14)
        }
        #endif
    }

    /// Go from the directions sheet: start recording if needed, then follow the route.
    private func startNavigation() {
        if !tracker.isActive {
            chosenKind = nav.mode.activity
            tracker.start(kind: nav.mode.activity)
            camera = .userLocation(followsHeading: false, fallback: .automatic)
        } else if tracker.state == .paused {
            tracker.resume()   // directions need live location; a paused recording stops GPS
        }
        chaseCam = true
        withAnimation(.snappy) { nav.go() }
    }

    private var deniedCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location is off for \(AppInfo.name)", systemImage: "location.slash.fill").font(Theme.rounded(16, .bold))
                Text("Turn on Location (While Using) in Settings so \(AppInfo.name) can track your route.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(Theme.rounded(15, .bold))
            }
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 6) {
            ForEach(ActivityKind.available) { k in
                kindButton(k)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    private func kindButton(_ k: ActivityKind) -> some View {
        let active = chosenKind == k
        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { chosenKind = k }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: k.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolEffect(.bounce, value: active)
                Text(k.title).font(Theme.rounded(12, .bold))
            }
            .foregroundStyle(active ? Theme.forestDeep : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Theme.leafGradient)
                        .matchedGeometryEffect(id: "kind", in: kindNS)
                        .shadow(color: Theme.glow.opacity(0.4), radius: 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: active)
    }

    private var startButton: some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            tracker.start(kind: chosenKind)
            camera = .userLocation(followsHeading: false, fallback: .automatic)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 36, height: 36)
                    .background(Theme.forestDeep.opacity(0.18), in: Circle())
                Text("Start \(chosenKind.title)")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(tracker.denied)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if TRACK_APP
            SectionHeader(title: "Recent", symbol: "clock.arrow.circlepath")
            ForEach(activities.prefix(3)) { a in
                NavigationLink(value: a.id) { TripCard(activity: a, mapHeight: 104) }.pressable().cardAppear()
            }
            #else
            SectionHeader(title: "Your strolls", symbol: "clock.arrow.circlepath")
            ForEach(activities) { a in
                NavigationLink(value: a.id) { ActivityRow(activity: a) }.pressable().cardAppear()
            }
            #endif
        }
        .padding(.top, 6)
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "From Garmin, Strava & more", symbol: "heart.text.square.fill").padding(.top, 6)
            Text("Workouts your other apps save to Apple Health. Tap + to add one to your hub.")
                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            if !healthLoaded {
                Button {
                    Task { await loadHealth() }
                } label: {
                    Label(healthLoading ? "Loading…" : "Show last 30 days", systemImage: "arrow.down.circle.fill")
                        .font(Theme.rounded(15, .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(healthLoading)
            } else if healthWorkouts.isEmpty {
                Text("No workouts in Apple Health yet. In Garmin Connect, turn on Apple Health under Connected Apps.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
            } else {
                ForEach(healthWorkouts) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.kind?.symbol ?? "figure.mixed.cardio")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.glow)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(w.name) · \(w.source)").font(Theme.rounded(15, .bold)).lineLimit(1)
                            Text("\(Format.dayTime(w.start)) · \(Format.duration(w.end.timeIntervalSince(w.start)))"
                                 + (w.distanceM.map { " · " + Format.distance($0) } ?? ""))
                                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        if isImported(w) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.glow)
                                .accessibilityLabel("Imported")
                        } else {
                            Button { importWorkout(w) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.glow)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Import \(w.name)")
                        }
                    }
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func loadHealth() async {
        healthLoading = true
        defer { healthLoading = false }
        let hs = HealthService.shared
        guard await hs.requestAccess() else { healthLoaded = true; return }
        healthWorkouts = await hs.recentWorkouts(days: 30)
        healthLoaded = true
    }

    private func importTag(_ w: HealthService.WorkoutInfo) -> String { "health:\(w.id.uuidString)" }

    private func isImported(_ w: HealthService.WorkoutInfo) -> Bool {
        let tag = importTag(w)
        return activities.contains { $0.notes.contains(tag) }
    }

    private func importWorkout(_ w: HealthService.WorkoutInfo) {
        let a = Activity()
        a.kind = w.kind ?? .walk
        a.title = "\(w.name) (\(w.source))"
        a.start = w.start
        a.end = w.end
        a.distanceM = w.distanceM ?? 0
        a.movingSec = w.end.timeIntervalSince(w.start)
        a.notes = "Imported from Apple Health\n\(importTag(w))"
        context.insert(a)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Live

    private func showProbe(_ p: RoutePoint?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { probe = p }
        guard let p else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if probe?.t == p.t { withAnimation(.easeOut) { probe = nil } }
        }
    }

    /// Room the maneuver banner takes at the top while navigating.
    private let navBannerHeight: CGFloat = 132

    /// GTA-style chase camera: sits behind you, tilted, turned to your direction of travel,
    /// and pulls back the faster you go.
    private func followIfNeeded() {
        guard chaseCam, let here = tracker.points.last?.coordinate else { return }
        let v = max(0, tracker.currentSpeed)
        let distance: Double
        switch tracker.kind {
        case .drive: distance = min(2600, 650 + v * 40)
        case .bike: distance = 520 + v * 25
        default: distance = 360
        }
        let heading = tracker.course >= 0 ? tracker.course : mapHeading
        // Aim the camera a little behind you, so you sit in the open map above the stats card.
        let ahead = -distance * 0.22
        let rad = heading * .pi / 180
        let center = CLLocationCoordinate2D(
            latitude: here.latitude + ahead * cos(rad) / 111_320,
            longitude: here.longitude + ahead * sin(rad) / (111_320 * max(0.2, cos(here.latitude * .pi / 180))))
        withAnimation(.easeInOut(duration: 0.9)) {
            camera = .camera(MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: tracker.kind == .drive ? 62 : 50))
        }
    }


    private var liveView: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
            Map(position: $camera) {
                let coords = tracker.points.map(\.coordinate)
                if nav.isNavigating, let r = nav.active {
                    NavRouteContent(route: r, traveledIndex: nav.traveledIndex, destination: nav.destination)
                }
                if let p = probe {
                    Annotation("", coordinate: p.coordinate, anchor: .bottom) { SpeedCallout(point: p) }
                        .annotationTitles(.hidden)
                }
                if tracker.kind == .drive {
                    // Neon route colored by speed vs the limit, with a soft glow under it.
                    ForEach(SpeedZones.segments(tracker.points)) { seg in
                        MapPolyline(coordinates: seg.coords)
                            .stroke(seg.band.color.opacity(0.28), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: seg.coords)
                            .stroke(seg.band.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(SpeedZones.overZones(tracker.points)) { z in
                        Annotation("", coordinate: z.peak, anchor: .bottom) { OverZoneBadge(overMph: z.peakOverMph) }
                    }
                    ForEach(tracker.laneChanges, id: \.t) { c in
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)) { LaneMarker(change: c) }
                            .annotationTitles(.hidden)
                    }
                } else if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.glow.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.glow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                #if !TRACK_APP
                ForEach(hugs.filter { $0.strollID == tracker.sessionID && $0.coordinate != nil }) { h in
                    Annotation(h.treeName, coordinate: h.coordinate!) { TreePin(photo: h.treePhoto, size: 34) }
                }
                #endif
                if let first = coords.first {
                    Annotation("Start", coordinate: first) {
                        Circle().fill(.white).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.forestDeep, lineWidth: 3))
                    }
                }
                // You: a little truck, walker, runner, hiker or e-bike instead of the blue dot.
                if let here = coords.last, tracker.kind == .drive {
                    // Top-down truck, turned to match the road and laid flat on the tilted map.
                    Annotation("", coordinate: here, anchor: .center) {
                        TopDownTruck(bearing: tracker.course >= 0 ? tracker.course - mapHeading : 0,
                                     pitch: mapPitch,
                                     speed: tracker.state == .recording ? tracker.currentSpeed : 0,
                                     overLimit: tracker.isOverLimit)
                    }
                    .annotationTitles(.hidden)
                } else if let here = coords.last {
                    Annotation("", coordinate: here, anchor: UnitPoint(x: 0.5, y: 0.82)) {
                        LiveAvatar(kind: tracker.kind, speed: tracker.state == .recording ? tracker.currentSpeed : 0,
                                   course: tracker.course, mapHeading: mapHeading, overLimit: tracker.isOverLimit)
                    }
                    .annotationTitles(.hidden)
                } else if tracker.state == .recording {
                    // No fix yet: the system dot while GPS warms up (never while paused, GPS is off then).
                    UserAnnotation()
                }
            }
            .mapStyle(tracker.kind == .drive
                      ? .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: true)
                      : .standard(elevation: .realistic))
            .environment(\.colorScheme, .dark)
            .mapControls {
                MapCompass()
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                mapHeading = ctx.camera.heading
                mapPitch = ctx.camera.pitch
            }
            .onTapGesture { pt in showProbe(RouteProbe.nearest(tracker.points, tap: pt, proxy: proxy)) }
            }
            .onChange(of: tracker.points.count) { _, _ in
                followIfNeeded()
                if let here = tracker.points.last?.coordinate { nav.update(here, speed: tracker.currentSpeed) }
            }
            .onAppear { followIfNeeded() }
            // Paused (GPS off): stop asking the map for live location. Recording again: follow you.
            .onChange(of: tracker.state) { _, state in
                if state == .paused, camera.followsUserLocation { camera = followCamera }
                if state == .recording, !chaseCam { camera = followCamera }
            }
            .overlay { SpeedFX(speed: tracker.kind == .drive || tracker.kind == .bike ? tracker.currentSpeed : 0,
                               overLimit: tracker.isOverLimit).allowsHitTesting(false).ignoresSafeArea() }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        withAnimation(.snappy) { chaseCam.toggle() }
                        if chaseCam { followIfNeeded() } else { camera = followCamera }
                    } label: {
                        Image(systemName: chaseCam ? "video.fill" : "location.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(chaseCam ? Theme.forestDeep : .white)
                            .frame(width: 44, height: 44)
                            .background(chaseCam ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                    }
                    .accessibilityLabel(chaseCam ? "Chase camera on" : "Chase camera off")
                    #if TRACK_APP
                    if !nav.isNavigating { DirectionsButton { showDirections = true } }
                    #endif
                    if tracker.kind == .drive {
                        DriveHUD(speed: tracker.currentSpeed, limit: tracker.speedLimit, over: tracker.isOverLimit)
                            .transition(.scale.combined(with: .opacity))
                        if tracker.state != .idle { LaneChip(lanes: tracker.laneChanges.count, cuts: tracker.cutCount) }
                    }
                }
                .padding(.trailing, 14)
                .padding(.top, nav.isNavigating ? 58 + navBannerHeight : 58)
            }
            .overlay(alignment: .topLeading) {
                if tracker.kind == .drive && tracker.state != .idle {
                    LaneHUD(laneCount: tracker.laneCount, laneIndex: tracker.laneIndex, estimated: true,
                            shift: tracker.lastLaneShift, speed: tracker.state == .recording ? tracker.currentSpeed : 0,
                            bend: tracker.roadBend, curving: tracker.onCurve,
                            tint: tracker.speedLimit.map { SpeedBand.of(speed: tracker.currentSpeed, limit: $0.mps).color } ?? Theme.glow,
                            onSetLane: { tracker.setLane($0) })
                        .scaleEffect(nav.isNavigating ? 0.8 : 1, anchor: .topLeading)
                        .padding(.leading, 14).padding(.top, nav.isNavigating ? 58 + navBannerHeight : 58)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if nav.phase == .navigating {
                    NavBanner(nav: nav)
                        .padding(.top, 54)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if nav.phase == .arrived {
                    NavArrivalCard(nav: nav) { confirmFinish = true }
                }
            }
            .animation(.snappy, value: nav.phase)
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 14) {
                if tracker.recoveredFromCrash {
                    Label("Recovered your recording. Tap Resume to keep going.", systemImage: "arrow.clockwise.circle.fill")
                        .font(Theme.rounded(13, .bold))
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Theme.gold.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Menu {
                        ForEach(ActivityKind.available) { k in
                            Button { tracker.setKind(k) } label: { Label(k.title, systemImage: k.symbol) }
                        }
                    } label: {
                        Label(tracker.kind.title, systemImage: tracker.kind.symbol)
                            .font(Theme.rounded(15, .bold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    if tracker.autoPaused {
                        Label("Auto-paused", systemImage: "figure.stand")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.5)
                            .foregroundStyle(Theme.forestDeep)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.gold, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Auto-paused. Resumes when you move.")
                    } else {
                        let recording = tracker.state == .recording
                        HStack(spacing: 6) {
                            Image(systemName: recording ? "circle.fill" : "pause.circle.fill")
                                .font(.system(size: recording ? 8 : 12, weight: .bold))
                                .symbolEffect(.pulse, options: .repeating, isActive: recording && !reduceMotion)
                            Text(recording ? "RECORDING" : "PAUSED")
                                .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                        }
                        .foregroundStyle(recording ? Color.red : Theme.gold)
                        .accessibilityElement(children: .combine)
                    }
                }

                // Two big numbers you can read at arm's length (time and distance), then the details.
                HStack(alignment: .top, spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        LiveBigStat(value: Format.duration(tracker.elapsed), unit: nil, label: "Time",
                                    tint: tracker.state == .recording ? .white : Theme.gold)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Elapsed time \(Format.duration(tracker.elapsed))")
                    }
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
                    LiveBigStat(value: Format.distanceValue(tracker.distance), unit: Format.distanceUnit, label: "Distance", tint: .white)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Distance \(Format.distance(tracker.distance))")
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    LiveSmallStat(text: livePaceOrSpeed, label: tracker.kind.isOnFoot ? "Avg pace" : "Speed",
                                  symbol: tracker.kind.isOnFoot ? "stopwatch.fill" : "speedometer")
                    LiveSmallStat(text: Format.elevation(tracker.elevGain), label: "Climb", symbol: "mountain.2.fill")
                }
                if tracker.state == .paused && !tracker.autoPaused && !tracker.recoveredFromCrash {
                    // A paused recording really is off: no GPS, no location arrow, until Resume.
                    Label("GPS is off while paused", systemImage: "location.slash.fill")
                        .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                } else if tracker.points.isEmpty && tracker.state == .recording {
                    Text(tracker.accuracy > 35 ? "Weak GPS (±\(Int(tracker.accuracy)) m). Step outside for a better fix." : "Waiting for GPS…")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }

                if let onHug {
                    Button(action: onHug) {
                        Label(hugCountLabel, systemImage: "tree.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                HStack(spacing: 12) {
                    if tracker.state == .recording {
                        Button { tracker.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                            .buttonStyle(PrimaryButtonStyle(gradient: Theme.goldGradient))
                    } else {
                        Button { tracker.resume() } label: { Label("Resume", systemImage: "play.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    #if TRACK_APP
                    // Stop: always next to Pause/Resume, in red so it's never mistaken for Pause;
                    // asks Save / Discard / Keep going.
                    Button { confirmFinish = true } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(StopButtonStyle())
                        .accessibilityHint("Save or discard this recording")
                    #else
                    Button { confirmFinish = true } label: { Label("Finish", systemImage: "flag.checkered") }
                        .buttonStyle(PrimaryButtonStyle(gradient: LinearGradient(colors: [.white, Theme.cream], startPoint: .top, endPoint: .bottom)))
                    #endif
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: tracker.state == .recording)
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Theme.cardStroke))
            .padding(.horizontal, 12)
            .padding(.bottom, 96)
        }
        .confirmationDialog("Finish this \(tracker.kind.title.lowercased())?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Save it") { finish() }
            Button("Discard recording", role: .destructive) { confirmDiscard = true }
            Button("Keep going", role: .cancel) {}
        }
        .alert("Throw away this recording?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { tracker.discard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The route and stats will be gone for good.")
        }
    }

    /// Avg pace on foot, current speed on wheels; a calm dash (not "--") until there's enough to measure.
    private var livePaceOrSpeed: String {
        let raw = tracker.kind.isOnFoot
            ? Format.paceOrSpeed(distance: tracker.distance, seconds: max(tracker.movingSec, 1), kind: tracker.kind)
            : Format.speed(max(0, tracker.currentSpeed))
        return raw.trimmingCharacters(in: .whitespaces) == "--" ? "—" : raw
    }

    private var hugCountLabel: String {
        #if TRACK_APP
        return "Hug a tree"
        #else
        let n = hugs.filter { $0.strollID == tracker.sessionID }.count
        return n == 0 ? "Hug a tree here" : "Hug a tree here · \(n) so far"
        #endif
    }

    private func finish(auto: Bool = false) {
        let suggestion = tracker.suggestedKind
        let originalKind = tracker.kind
        guard let a = tracker.finish(auto: auto) else { return }
        // If the motion chip strongly disagrees (e.g. you picked Walk but drove), switch it; you can change it back.
        if suggestion != originalKind && (suggestion == .drive || originalKind == .drive)
            && ActivityKind.available.contains(suggestion) { a.kind = suggestion }
        context.insert(a)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        justFinished = a
        NotificationCenter.default.post(name: .activitySaved, object: nil, userInfo: [
            "id": a.id.uuidString, "auto": auto, "kind": a.kind.rawValue,
            "distanceM": a.distanceM, "seconds": a.elapsedSec,
        ])
        let pts = a.route
        Task {
            if let s = pts.first { a.startPlace = await Geo.placeName(for: s.coordinate) }
            if let e = pts.last { a.endPlace = await Geo.placeName(for: e.coordinate) }
            try? context.save()
        }
    }
}

// MARK: - Live stats

/// Big glanceable number for the live screen (time, distance), unit set smaller beside it.
private struct LiveBigStat: View {
    let value: String
    let unit: String?
    let label: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: Theme.scaled(46), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                if let unit {
                    Text(unit)
                        .font(.system(size: Theme.scaled(18), weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: Theme.scaled(11), weight: .heavy, design: .rounded)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Secondary live number (pace/speed, climb) in a slim row.
private struct LiveSmallStat: View {
    let text: String
    let label: String
    let symbol: String

    var body: some View {
        let parts = TrackingActivityAttributes.valueAndUnit(text)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.glow)
                .frame(width: 30, height: 30)
                .background(Theme.glow.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.value)
                        .font(.system(size: Theme.scaled(20), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: parts.value)
                    if !parts.unit.isEmpty {
                        Text(parts.unit)
                            .font(.system(size: Theme.scaled(12), weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(label.uppercased())
                    .font(.system(size: Theme.scaled(10), weight: .bold, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(text == "—" ? "not measured yet" : text)")
    }
}

/// Red Stop button next to Pause/Resume on the live screen.
private struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(17, .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LinearGradient(colors: [Color(red: 1, green: 0.36, blue: 0.33), Color(red: 0.86, green: 0.17, blue: 0.17)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.red.opacity(0.3), radius: configuration.isPressed ? 4 : 12, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
