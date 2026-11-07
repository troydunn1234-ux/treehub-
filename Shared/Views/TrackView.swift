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
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var justFinished: Activity?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var healthWorkouts: [HealthService.WorkoutInfo] = []
    @State private var healthLoading = false
    @State private var healthLoaded = false

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
        }
    }

    // MARK: Idle

    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if TRACK_APP
                Text("Track").font(Theme.title(36)).foregroundStyle(.white).padding(.top, 8)
                #else
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stroll").font(Theme.title(36)).foregroundStyle(.white)
                    Text("Wander to your trees. Every hug along the way gets pinned on your route.")
                        .font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim)
                }
                .padding(.top, 8)
                #endif

                ZStack(alignment: .bottom) {
                    Map(position: $camera) { UserAnnotation() }
                        .mapStyle(.standard(elevation: .realistic))
                        .mapControls { MapUserLocationButton() }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.cardStroke))
                }

                if tracker.denied {
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("What are you doing?").font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 8) {
                        ForEach(ActivityKind.available) { k in
                            Button {
                                withAnimation(.snappy) { chosenKind = k }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.symbol).font(.system(size: 22, weight: .semibold))
                                    Text(k.title).font(Theme.rounded(12, .bold))
                                }
                                .foregroundStyle(chosenKind == k ? Theme.forestDeep : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(chosenKind == k ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.07)),
                                            in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .haptic()
                        }
                    }
                }

                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    tracker.start(kind: chosenKind)
                    camera = .userLocation(followsHeading: false, fallback: .automatic)
                } label: {
                    Label("Start \(chosenKind.title)", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(tracker.denied)

                Text("Keeps recording with your phone locked. Look for the blue location pill at the top of the screen.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)

                if !activities.isEmpty {
                    #if TRACK_APP
                    SectionHeader(title: "Recent", symbol: "clock.arrow.circlepath").padding(.top, 6)
                    ForEach(activities.prefix(3)) { a in
                        NavigationLink(value: a.id) { ActivityRow(activity: a) }.pressable().cardAppear()
                    }
                    #else
                    SectionHeader(title: "Your strolls", symbol: "clock.arrow.circlepath").padding(.top, 6)
                    ForEach(activities) { a in
                        NavigationLink(value: a.id) { ActivityRow(activity: a) }.pressable().cardAppear()
                    }
                    #endif
                }

                #if TRACK_APP
                healthSection
                #endif
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 120)
        }
        .onAppear {
            if tracker.authorization == .notDetermined { tracker.requestPermission() }
        }
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
                        } else {
                            Button { importWorkout(w) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.glow)
                            }
                            .buttonStyle(.plain)
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

    private var liveView: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                UserAnnotation()
                let coords = tracker.points.map(\.coordinate)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.glow, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
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
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
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
                    HStack(spacing: 6) {
                        Circle().fill(tracker.state == .recording ? Color.red : Theme.gold).frame(width: 8, height: 8)
                        Text(tracker.state == .recording ? "RECORDING" : "PAUSED")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                    }
                    .foregroundStyle(tracker.state == .recording ? Color.red : Theme.gold)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 2) {
                        Text(Format.duration(tracker.elapsed))
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("TIME").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.2).foregroundStyle(Theme.textDim)
                    }
                }
                HStack(spacing: 10) {
                    StatTile(value: Format.distance(tracker.distance), label: "Distance")
                    StatTile(value: tracker.kind.isOnFoot
                             ? Format.paceOrSpeed(distance: tracker.distance, seconds: max(tracker.movingSec, 1), kind: tracker.kind)
                             : Format.speed(tracker.currentSpeed),
                             label: tracker.kind.isOnFoot ? "Avg pace" : "Speed")
                    StatTile(value: Format.elevation(tracker.elevGain), label: "Climb")
                }
                if tracker.points.isEmpty {
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
                    Button { confirmFinish = true } label: { Label("Finish", systemImage: "flag.checkered") }
                        .buttonStyle(PrimaryButtonStyle(gradient: LinearGradient(colors: [.white, Theme.cream], startPoint: .top, endPoint: .bottom)))
                }
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

    private var hugCountLabel: String {
        #if TRACK_APP
        return "Hug a tree"
        #else
        let n = hugs.filter { $0.strollID == tracker.sessionID }.count
        return n == 0 ? "Hug a tree here" : "Hug a tree here · \(n) so far"
        #endif
    }

    private func finish() {
        let suggestion = tracker.suggestedKind
        let originalKind = tracker.kind
        guard let a = tracker.finish() else { return }
        // If the motion chip strongly disagrees (e.g. you picked Walk but drove), switch it; you can change it back.
        if suggestion != originalKind && (suggestion == .drive || originalKind == .drive)
            && ActivityKind.available.contains(suggestion) { a.kind = suggestion }
        context.insert(a)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        justFinished = a
        let pts = a.route
        Task {
            if let s = pts.first { a.startPlace = await Geo.placeName(for: s.coordinate) }
            if let e = pts.last { a.endPlace = await Geo.placeName(for: e.coordinate) }
            try? context.save()
        }
    }
}
