import SwiftUI
import MapKit

struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RouteThumbnail(points: activity.route.map(\.coordinate))
                    .frame(width: 58, height: 58)
                    .background(Theme.forest, in: RoundedRectangle(cornerRadius: 14))
                Image(systemName: activity.kind.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .padding(5)
                    .background(Theme.glow, in: Circle())
                    .offset(x: 24, y: 24)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.displayTitle).font(Theme.rounded(16, .bold)).foregroundStyle(.white).lineLimit(1)
                Text(Format.dayTime(activity.start)).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                HStack(spacing: 10) {
                    Text(Format.distance(activity.distanceM))
                    Text(Format.duration(activity.elapsedSec))
                    if activity.kind.isOnFoot && activity.elevGainM > 5 { Text("↑ " + Format.elevation(activity.elevGainM)) }
                }
                .font(Theme.rounded(13, .bold))
                .foregroundStyle(Theme.glow)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardStroke))
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
