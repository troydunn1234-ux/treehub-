import SwiftUI
import MapKit
import UIKit
import CoreLocation

// History / Recent trip card: a real map snapshot of the route on top, then title, date and
// distance / time / average. Snapshots are made once with MKMapSnapshotter and cached in memory
// and in Caches/ (keyed by trip id + distance + end time, so a trim or edit redraws it).

// MARK: - Snapshot cache

@MainActor
final class TripMapCache {
    static let shared = TripMapCache()

    /// Snapshot size in points (rendered at 3x); the card crops it to fit its width.
    static let size = CGSize(width: 420, height: 150)

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let dir: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let d = caches.appendingPathComponent("RoamrTripMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() { memory.countLimit = 80 }

    static func key(for a: Activity) -> String {
        "\(a.id.uuidString)-\(Int(a.distanceM.rounded()))-\(Int(a.end.timeIntervalSince1970))-v1"
    }

    /// Already in memory (no disk, no work): lets a card draw its map on the first frame.
    func cached(_ key: String) -> UIImage? { memory.object(forKey: key as NSString) }

    /// Memory, then disk, then a fresh snapshot. Returns nil for trips without a route.
    func image(for a: Activity) async -> UIImage? {
        let key = Self.key(for: a)
        if let img = memory.object(forKey: key as NSString) { return img }
        if let running = inflight[key] { return await running.value }
        let file = dir?.appendingPathComponent(key + ".jpg")
        // Decode the route here (main actor, SwiftData object) before going async.
        let coords = Self.thin(a.route.map(\.coordinate))
        let task = Task<UIImage?, Never> { @MainActor in
            if let file, let data = await Self.read(file), let img = UIImage(data: data, scale: 3) {
                return img
            }
            guard coords.count > 1, let img = await Self.snapshot(coords) else { return nil }
            if let file, let jpg = img.jpegData(compressionQuality: 0.82) {
                Task.detached(priority: .utility) { try? jpg.write(to: file, options: .atomic) }
            }
            return img
        }
        inflight[key] = task
        let img = await task.value
        inflight[key] = nil
        if let img { memory.setObject(img, forKey: key as NSString) }
        return img
    }

    /// Throws away every cached map (e.g. after a big edit); they redraw as cards appear.
    func clear() {
        memory.removeAllObjects()
        if let dir { try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    private nonisolated static func read(_ file: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { try? Data(contentsOf: file) }.value
    }

    private static func thin(_ c: [CLLocationCoordinate2D], maxCount: Int = 600) -> [CLLocationCoordinate2D] {
        guard c.count > maxCount else { return c }
        let step = Double(c.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { c[min(c.count - 1, Int((Double($0) * step).rounded()))] }
    }

    private static func snapshot(_ route: [CLLocationCoordinate2D]) async -> UIImage? {
        let size = Self.size
        let pts = route.map { MKMapPoint($0) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        var rect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let minSide = 400 * MKMapPointsPerMeterAtLatitude(route[0].latitude)
        if rect.size.width < minSide { rect = rect.insetBy(dx: -(minSide - rect.size.width) / 2, dy: 0) }
        if rect.size.height < minSide { rect = rect.insetBy(dx: 0, dy: -(minSide - rect.size.height) / 2) }
        rect = rect.insetBy(dx: -rect.size.width * 0.16, dy: -rect.size.height * 0.22)
        // Match the image's shape so the route stays centered.
        let want = Double(size.width / size.height), have = rect.size.width / rect.size.height
        if have < want {
            let w = rect.size.height * want
            rect = rect.insetBy(dx: -(w - rect.size.width) / 2, dy: 0)
        } else {
            let h = rect.size.width / want
            rect = rect.insetBy(dx: 0, dy: -(h - rect.size.height) / 2)
        }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.traitCollection = UITraitCollection { t in
            t.userInterfaceStyle = .dark
            t.displayScale = 3
        }
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config

        let snapshotter = MKMapSnapshotter(options: options)
        let snap: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { cont in
            snapshotter.start(with: .main) { s, _ in cont.resume(returning: s) }
        }
        guard let snap else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = snap.image.scale
        let line = UIColor(Theme.glow), halo = UIColor(Theme.leaf), gold = UIColor(Theme.gold), dark = UIColor(Theme.forestDeep)
        return UIGraphicsImageRenderer(size: snap.image.size, format: format).image { ctx in
            snap.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in route.enumerated() {
                let p = snap.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let cg = ctx.cgContext
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 8, color: halo.withAlphaComponent(0.8).cgColor)
            halo.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 7
            path.stroke()
            cg.restoreGState()
            line.setStroke()
            path.lineWidth = 3.5
            path.stroke()
            func dot(_ c: CLLocationCoordinate2D, _ fill: UIColor) {
                let p = snap.point(for: c)
                let r: CGFloat = 5
                let o = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                fill.setFill(); o.fill()
                dark.setStroke(); o.lineWidth = 2; o.stroke()
            }
            dot(route[0], .white)
            dot(route[route.count - 1], gold)
        }
    }
}

// MARK: - Card

struct TripCard: View {
    let activity: Activity
    /// "with Alex, Sam" for a Go together trip.
    var together: String? = nil
    /// Height of the map strip.
    var mapHeight: CGFloat = 120

    @State private var map: UIImage?
    @State private var loaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var avgText: String {
        let secs = activity.movingSec > 0 ? activity.movingSec : activity.elapsedSec
        let v = Format.paceOrSpeed(distance: activity.distanceM, seconds: max(secs, 1), kind: activity.kind)
        return v == "--" ? "—" : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mapStrip
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.displayTitle)
                            .font(Theme.rounded(17, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(Format.dayTime(activity.start))
                            .font(Theme.rounded(13, .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                if let together {
                    Label(together, systemImage: "person.2.fill")
                        .labelStyle(CompactLabelStyle())
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(Theme.sky)
                        .lineLimit(1)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { metrics }
                    VStack(alignment: .leading, spacing: 8) { metrics }
                }
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial).opacity(0.5)
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: TripMapCache.key(for: activity)) {
            if let hit = TripMapCache.shared.cached(TripMapCache.key(for: activity)) { map = hit; loaded = true; return }
            let img = await TripMapCache.shared.image(for: activity)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { map = img; loaded = true }
        }
    }

    @ViewBuilder private var metrics: some View {
        metric(Format.distance(activity.distanceM), "Distance", "point.topleft.down.to.point.bottomright.curvepath")
            .frame(maxWidth: .infinity, alignment: .leading)
        metric(Format.duration(activity.elapsedSec), "Time", "clock")
            .frame(maxWidth: .infinity, alignment: .leading)
        metric(avgText, activity.kind.isOnFoot ? "Avg pace" : "Avg speed", "speedometer")
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.rounded(16, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.glow)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(Theme.rounded(11, .semibold))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var mapStrip: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss.opacity(0.9), Theme.forest], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let map {
                Image(uiImage: map)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if loaded {
                // No route (imported workout or a GPS-less recording).
                VStack(spacing: 6) {
                    Image(systemName: activity.kind.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.leafGradient)
                    Text(activity.notes.contains("health:") ? "Imported from Apple Health" : "No route recorded")
                        .font(Theme.rounded(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            } else {
                // Placeholder while the snapshot renders: the plain route drawing.
                RouteThumbnail(points: activity.route.map(\.coordinate))
                    .opacity(0.5)
                    .redacted(reason: .placeholder)
            }
        }
        .frame(height: mapHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            HStack(spacing: 5) {
                Image(systemName: activity.kind.symbol).font(.system(size: 11, weight: .bold))
                Text(activity.kind.title).font(Theme.rounded(12, .bold))
            }
            .foregroundStyle(Theme.forestDeep)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.leafGradient, in: Capsule())
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if activity.trimmedSec >= 60 || activity.autoFinished {
                Label(activity.autoFinished ? "Auto-finished" : "Trimmed", systemImage: "scissors")
                    .labelStyle(CompactLabelStyle())
                    .font(Theme.rounded(11, .bold))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["\(activity.kind.title): \(activity.displayTitle)", Format.dayTime(activity.start),
                     Format.distance(activity.distanceM), Format.duration(activity.elapsedSec)]
        if avgText != "—" { parts.append("\(activity.kind.isOnFoot ? "average pace" : "average speed") \(avgText)") }
        if let together { parts.append(together) }
        return parts.joined(separator: ", ")
    }
}
