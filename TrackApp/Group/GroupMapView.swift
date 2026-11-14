import SwiftUI
import Combine
import UIKit
import MapKit
import CoreLocation
import SwiftData

/// The live "Go together" screen: everyone on one map with a speed bubble next to each person.
@MainActor
struct GroupMapView: View {
    @ObservedObject private var group = GroupSession.shared
    @Environment(RouteTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var userMovedMap = false
    @State private var lastFit = Date.distantPast
    @State private var now = Date()
    @State private var showLeave = false
    @State private var confirmEnd = false
    @State private var showSafety = false
    @State private var toastText: String?

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                if showSafety { safetyNote.transition(.move(edge: .top).combined(with: .opacity)) }
                if let note = group.connectionNote {
                    Label(note, systemImage: "icloud.slash")
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                if let t = toastText {
                    Text(t)
                        .font(Theme.rounded(14, .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.leafGradient, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if userMovedMap {
                    HStack {
                        Spacer()
                        Button { fitAll(animated: true, force: true) } label: {
                            Label("Fit all", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(Theme.rounded(13, .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                }
                bottomCard
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Theme.forestDeep)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toastText)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSafety)
        .animation(.snappy, value: userMovedMap)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if !group.safetyNoteSeen { showSafety = true }
            fitAll(animated: false, force: true)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(clock) { t in
            now = t
            if !userMovedMap, t.timeIntervalSince(lastFit) >= 4 { fitAll(animated: true, force: false) }
        }
        .onChange(of: group.toast) { _, t in
            guard let t else { return }
            toastText = t
            group.toast = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if toastText == t { toastText = nil }
            }
        }
        .onChange(of: group.riders.count) { _, _ in
            if !userMovedMap { fitAll(animated: true, force: true) }
        }
        .confirmationDialog("Leave the group?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Stop & save trip") { stopAndSave() }
            Button("Leave group, keep tracking") {
                group.leave()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your friends will stop seeing you on their map.")
        }
        .alert("End for everyone?", isPresented: $confirmEnd) {
            Button("End trip", role: .destructive) {
                Task {
                    await group.endForEveryone()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone in the group will see the trip has ended. Your own recording keeps going.")
        }
        .alert("Go together", isPresented: Binding(
            get: { group.lastError != nil },
            set: { if !$0 { group.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(group.lastError ?? "")
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            if let me = tracker.lastCoordinate {
                Annotation(group.myName, coordinate: me, anchor: .center) {
                    RiderBadge(name: group.myName, kind: tracker.isActive ? tracker.kind : group.kind,
                               color: Color(groupHex: group.myColorHex), speed: tracker.currentSpeed,
                               isMe: true, stale: false)
                }
                .annotationTitles(.hidden)
            }
            ForEach(group.riders) { r in
                Annotation(r.name, coordinate: r.coordinate, anchor: .center) {
                    RiderBadge(name: r.name, kind: r.kind, color: r.color, speed: r.speed,
                               isMe: false, stale: r.isStale(now))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in userMovedMap = true })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in userMovedMap = true })
    }

    private var allCoordinates: [CLLocationCoordinate2D] {
        var list = group.riders.filter { !$0.isStale(now) }.map(\.coordinate)
        if let me = tracker.lastCoordinate { list.append(me) }
        return list
    }

    /// Frames everyone. Without `force` it only re-fits on the timer.
    private func fitAll(animated: Bool, force: Bool) {
        lastFit = Date()
        if force { userMovedMap = false }
        let coords = allCoordinates
        let target: MapCameraPosition
        if coords.isEmpty {
            target = .userLocation(fallback: .automatic)
        } else if coords.count == 1 {
            target = .region(MKCoordinateRegion(center: coords[0], latitudinalMeters: 1200, longitudinalMeters: 1200))
        } else {
            let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
            // Extra room at the bottom for the card and on the sides for the speed bubbles.
            let span = MKCoordinateSpan(latitudeDelta: max(0.006, (maxLat - minLat) * 2.0),
                                        longitudeDelta: max(0.006, (maxLon - minLon) * 1.7))
            target = .region(MKCoordinateRegion(center: center, span: span))
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { camera = target }
        } else {
            camera = target
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize")

            VStack(alignment: .leading, spacing: 2) {
                Text(group.state == .hosting ? "Your group \(group.kind.title.lowercased())" : "\(group.hostName)'s group \(group.kind.title.lowercased())")
                    .font(Theme.rounded(14, .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Code \(group.code ?? "------") · \(group.riders.count + 1) here")
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(Theme.textDim)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            // Your own big speedometer.
            let parts = SpeedText.parts(tracker.currentSpeed)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(parts.value)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: parts.value)
                Text(parts.unit)
                    .font(Theme.rounded(13, .heavy))
                    .foregroundStyle(Theme.glow)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your speed \(parts.value) \(parts.unit)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.glow.opacity(0.35), lineWidth: 1))
        .padding(.top, 4)
    }

    private var safetyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
            Text("Passengers can tap; drivers keep eyes on the road.")
                .font(Theme.rounded(13, .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                group.safetyNoteSeen = true
                showSafety = false
            } label: {
                Text("Got it").font(Theme.rounded(12, .heavy)).foregroundStyle(Theme.forestDeep)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.goldGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
    }

    // MARK: Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if group.riders.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.glow)
                    Text("Waiting for friends… share the link or code \(group.code ?? "").")
                        .font(Theme.rounded(13, .semibold))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(group.riders) { r in riderRow(r) }
                    }
                }
                .frame(maxHeight: min(CGFloat(group.riders.count) * 58, 190))
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                ShareLink(item: group.shareMessage()) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .font(Theme.rounded(14, .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.leafGradient, in: Capsule())
                }
                Button { showLeave = true } label: {
                    Text("Leave")
                        .font(Theme.rounded(14, .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                if group.state == .hosting {
                    Button { confirmEnd = true } label: {
                        Text("End for everyone")
                            .font(Theme.rounded(13, .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private func riderRow(_ r: RiderState) -> some View {
        let stale = r.isStale(now)
        let parts = SpeedText.parts(r.speed)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(r.color).frame(width: 38, height: 38)
                Image(systemName: r.kind.symbol)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(Theme.rounded(15, .heavy)).foregroundStyle(.white).lineLimit(1)
                Text([group.relation(to: r), SpeedText.ago(r.age(now))].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.rounded(12, .semibold))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value).font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                Text(parts.unit).font(Theme.rounded(11, .heavy)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(stale ? 0.45 : 1)
        .saturation(stale ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            userMovedMap = true
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(MKCoordinateRegion(center: r.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
            }
        }
    }

    // MARK: Actions

    /// Leave the group and finish the recording into History, the same way the Track screen saves.
    private func stopAndSave() {
        group.leave()
        guard let a = tracker.finish() else { dismiss(); return }
        context.insert(a)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(name: .activitySaved, object: nil, userInfo: [
            "id": a.id.uuidString, "auto": false, "kind": a.kind.rawValue,
            "distanceM": a.distanceM, "seconds": a.elapsedSec,
        ])
        let pts = a.route
        let ctx = context
        Task { @MainActor in
            if let s = pts.first { a.startPlace = await Geo.placeName(for: s.coordinate) }
            if let e = pts.last { a.endPlace = await Geo.placeName(for: e.coordinate) }
            try? ctx.save()
        }
        dismiss()
    }
}

// MARK: - Badge

/// A person on the map: colored circle with the activity symbol, name under it, speed bubble beside it.
@MainActor
struct RiderBadge: View {
    let name: String
    let kind: ActivityKind
    let color: Color
    let speed: Double
    let isMe: Bool
    let stale: Bool

    var body: some View {
        let parts = SpeedText.parts(speed)
        HStack(alignment: .center, spacing: 6) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 44, height: 44)
                        .shadow(color: color.opacity(0.7), radius: isMe ? 10 : 6)
                    Circle().strokeBorder(.white, lineWidth: isMe ? 3.5 : 2.5).frame(width: 44, height: 44)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                }
                Text(isMe ? "\(name) (you)" : name)
                    .font(Theme.rounded(11, .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Text(parts.unit)
                    .font(Theme.rounded(10, .heavy))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color, lineWidth: 1.5))
            .offset(y: -10)
        }
        // Keep the circle (not the whole HStack) on the coordinate: shift right by half the bubble.
        .offset(x: 34)
        .opacity(stale ? 0.45 : 1)
        .saturation(stale ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMe ? "You" : name), \(parts.value) \(parts.unit)")
    }
}

// MARK: - Text helpers

enum SpeedText {
    /// ("47", "mph") or ("76", "km/h"), following the app's unit setting.
    static func parts(_ mps: Double) -> (value: String, unit: String) {
        let v = mps.isFinite ? max(0, mps) : 0
        if Units.metric { return (String(format: "%.0f", v * 3.6), "km/h") }
        return (String(format: "%.0f", v * 2.236936), "mph")
    }

    static func ago(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}
