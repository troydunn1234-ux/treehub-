import SwiftUI
import MapKit

struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 14) {
            RouteThumbnail(points: activity.route.map(\.coordinate))
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [Theme.moss.opacity(0.9), Theme.forest], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial).opacity(0.5)
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
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
