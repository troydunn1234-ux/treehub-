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
    @State private var gpxURL: URL?

    private var coords: [CLLocationCoordinate2D] { activity.route.map(\.coordinate) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isNew {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(Theme.glow)
                        VStack(alignment: .leading) {
                            Text("Saved!").font(Theme.title(26))
                            Text("+\(GameEngine.xp(for: activity)) XP").font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.gold)
                        }
                    }
                    .padding(.top, 8)
                }

                if coords.count > 1 {
                    Map(initialPosition: .automatic) {
                        MapPolyline(coordinates: coords)
                            .stroke(Theme.glow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        if let s = coords.first {
                            Annotation("Start", coordinate: s) {
                                Circle().fill(.white).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.forestDeep, lineWidth: 3))
                            }
                        }
                        if let e = coords.last {
                            Annotation("Finish", coordinate: e) {
                                Image(systemName: "flag.checkered.circle.fill").font(.system(size: 22))
                                    .foregroundStyle(Theme.forestDeep, Theme.gold)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    GlassCard {
                        Label("No route map for this one (imported or too short).", systemImage: "map")
                            .font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: $activity.title, prompt: Text(activity.displayTitle).foregroundStyle(.white))
                        .font(Theme.title(26))
                    Text(Format.dayTime(activity.start)).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                }

                if !activity.startPlace.isEmpty || !activity.endPlace.isEmpty {
                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            placeRow("Started", activity.startPlace, "circle.fill", .white)
                            placeRow("Ended", activity.endPlace, "flag.checkered", Theme.gold)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(value: Format.distance(activity.distanceM), label: "Distance", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(value: Format.duration(activity.elapsedSec), label: "Total time", symbol: "clock")
                    StatTile(value: Format.paceOrSpeed(distance: activity.distanceM, seconds: max(activity.movingSec, 1), kind: activity.kind),
                             label: activity.kind.isOnFoot ? "Avg pace" : "Avg speed", symbol: "speedometer")
                    StatTile(value: activity.kind.isOnFoot ? Format.elevation(activity.elevGainM) : Format.speed(activity.maxSpeed),
                             label: activity.kind.isOnFoot ? "Climb" : "Top speed",
                             symbol: activity.kind.isOnFoot ? "mountain.2.fill" : "gauge.with.dots.needle.67percent")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 8) {
                        ForEach(ActivityKind.allCases) { k in
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
            .padding(16)
            .padding(.bottom, 110)
        }
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
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
        <gpx version="1.1" creator="TreeHub" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escape(a.displayTitle))</name><type>\(a.kind.rawValue)</type><trkseg>

        """
        for p in pts {
            s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lng)\">"
            if p.alt.isFinite { s += "<ele>\(String(format: "%.1f", p.alt))</ele>" }
            s += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time></trkpt>\n"
        }
        s += "</trkseg></trk></gpx>\n"
        let name = "TreeHub-\(a.kind.title)-\(Int(a.start.timeIntervalSince1970)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try s.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
