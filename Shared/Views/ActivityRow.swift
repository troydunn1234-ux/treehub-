import SwiftUI
import MapKit

struct ActivityRow: View {
    let activity: Activity
    /// "with Alex, Sam" for a Go together trip.
    var together: String? = nil
    /// The route outline, decoded in the background (RouteThumbCache.load) instead of while the row is drawn.
    @State private var outline: [CLLocationCoordinate2D]?

    var body: some View {
        HStack(spacing: 14) {
            RouteThumbnail(points: RouteThumbCache.cached(for: activity) ?? outline ?? [])
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [Theme.moss.opacity(0.9), Theme.forest], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: activity.kind.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(width: 24, height: 24)
                        .background(Theme.leafGradient, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.forestDeep, lineWidth: 2))
                        .offset(x: 6, y: 6)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayTitle).font(Theme.rounded(16, .bold)).foregroundStyle(.white).lineLimit(1)
                Text(Format.dayTime(activity.start)).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                if let together {
                    Label(together, systemImage: "person.2.fill")
                        .labelStyle(CompactLabelStyle())
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.sky)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label(Format.distance(activity.distanceM), systemImage: "arrow.triangle.swap")
                    Label(Format.duration(activity.elapsedSec), systemImage: "clock")
                    if activity.kind.isOnFoot && activity.elevGainM > 5 {
                        Label(Format.elevation(activity.elevGainM), systemImage: "arrow.up.right")
                    }
                    if activity.trimmedSec >= 60 || activity.autoFinished {
                        Label(activity.autoFinished ? "Auto" : "Trimmed", systemImage: "scissors")
                            .foregroundStyle(Theme.gold)
                    }
                }
                .labelStyle(CompactLabelStyle())
                .font(Theme.rounded(12, .bold))
                .foregroundStyle(Theme.glow)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(.ultraThinMaterial).opacity(0.5)
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Color.white.opacity(0.05))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: "\(activity.id.uuidString)|\(RouteThumbCache.key(for: activity))") {
            outline = await RouteThumbCache.load(for: activity)
        }
    }

    private var accessibilityText: String {
        var parts = [activity.displayTitle, Format.dayTime(activity.start), Format.distance(activity.distanceM), Format.duration(activity.elapsedSec)]
        if let together { parts.append(together) }
        return parts.joined(separator: ", ")
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .heavy)).opacity(0.8)
            configuration.title
        }
    }
}

/// Tiny route drawing (no map tiles) for lists.
struct RouteThumbnail: View {
    let points: [CLLocationCoordinate2D]

    var body: some View {
        Canvas { gc, size in
            guard points.count > 1 else { return }
            let lats = points.map(\.latitude), lngs = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return }
            let midLat = (minLat + maxLat) / 2 * .pi / 180
            let w = max((maxLng - minLng) * cos(midLat), 1e-6), h = max(maxLat - minLat, 1e-6)
            let pad: CGFloat = 8
            let scale = min((size.width - pad * 2) / w, (size.height - pad * 2) / h)
            let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: ox + (c.longitude - minLng) * cos(midLat) * scale, y: oy + (maxLat - c.latitude) * scale)
            }
            var path = Path()
            let step = max(1, points.count / 300)
            path.move(to: pt(points[0]))
            for i in stride(from: step, to: points.count, by: step) { path.addLine(to: pt(points[i])) }
            path.addLine(to: pt(points[points.count - 1]))
            gc.stroke(path, with: .color(Theme.glow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            let s = pt(points[0]), e = pt(points[points.count - 1])
            gc.fill(Path(ellipseIn: CGRect(x: s.x - 3, y: s.y - 3, width: 6, height: 6)), with: .color(.white))
            gc.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)), with: .color(Theme.gold))
        }
    }
}


/// Thinned route outlines for list thumbnails, kept per trip (by id + end time + distance, so a trim redraws it):
/// a list row used to decode the whole stored route every time it was drawn.
@MainActor
enum RouteThumbCache {
    private static var store: [UUID: (key: String, coords: [CLLocationCoordinate2D])] = [:]

    /// Changes when a trim or edit changes the route (its end time and distance change with it).
    static func key(for a: Activity) -> String { "\(a.end.timeIntervalSince1970)|\(a.distanceM)" }

    /// The outline when it was worked out already: drawn on a row's first frame without reading anything.
    static func cached(for a: Activity) -> [CLLocationCoordinate2D]? {
        guard let hit = store[a.id], hit.key == key(for: a) else { return nil }
        return hit.coords
    }

    /// Decodes on the calling thread when it isn't cached. Views use `load(for:)`.
    static func coords(for a: Activity) -> [CLLocationCoordinate2D] {
        if let hit = cached(for: a) { return hit }
        let thin = thinned(a.route.map(\.coordinate))
        remember(thin, id: a.id, key: key(for: a))
        return thin
    }

    /// The outline for a list row. Only the stored bytes are taken here (main actor, SwiftData object); decoding and
    /// thinning run in the background, so a long list, or the first screen on a big history, never waits on it.
    static func load(for a: Activity) async -> [CLLocationCoordinate2D] {
        if let hit = cached(for: a) { return hit }
        let id = a.id, k = key(for: a)
        guard let data = a.routeData else { return [] }
        let thin = await Task.detached(priority: .userInitiated) { () -> [CLLocationCoordinate2D] in
            guard let pts = try? JSONDecoder().decode([RoutePoint].self, from: data) else { return [] }
            return RouteThumbCache.thinned(pts.map(\.coordinate))
        }.value
        remember(thin, id: id, key: k)
        return thin
    }

    private static func remember(_ coords: [CLLocationCoordinate2D], id: UUID, key: String) {
        if store.count >= 600 { store.removeAll(keepingCapacity: true) }
        store[id] = (key, coords)
    }

    /// At most ~300 points, always keeping the first and last (what RouteThumbnail draws anyway).
    nonisolated static func thinned(_ all: [CLLocationCoordinate2D], max: Int = 300) -> [CLLocationCoordinate2D] {
        guard all.count > max, max > 1 else { return all }
        let step = all.count / max + 1
        var out = stride(from: 0, to: all.count, by: step).map { all[$0] }
        if let last = all.last, out.count < all.count, step > 1, (all.count - 1) % step != 0 { out.append(last) }
        return out
    }
}
