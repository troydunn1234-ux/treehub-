import SwiftUI
import MapKit
import UIKit
import CoreLocation

// Shareable recap card: a map snapshot of the route with the trip's numbers, rendered to a
// 1080x1920 story image or a 1080x1080 square, ready for the share sheet.

enum RecapFormat: String, CaseIterable, Identifiable {
    case story, square
    var id: String { rawValue }
    var title: String { self == .story ? "Story" : "Square" }
    /// Final image size in pixels (rendered at scale 1).
    var size: CGSize { self == .story ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1080) }
    /// Size of the map part, in pixels.
    var mapSize: CGSize { self == .story ? CGSize(width: 1080, height: 1200) : CGSize(width: 1080, height: 1080) }
}

/// Everything the card shows, copied out of the Activity.
struct RecapData {
    var kind: ActivityKind
    var title: String
    var date: Date
    var distanceM: Double
    var elapsedSec: Double
    var movingSec: Double
    var maxSpeed: Double
    var elevGainM: Double
    var friends: String?

    init(_ a: Activity, friends: String? = nil) {
        kind = a.kind
        title = a.displayTitle
        date = a.start
        distanceM = a.distanceM
        elapsedSec = a.elapsedSec
        movingSec = a.movingSec
        maxSpeed = a.maxSpeed
        elevGainM = a.elevGainM
        self.friends = friends
    }

    var avgLabel: String { kind.isOnFoot ? "Avg pace" : "Avg speed" }
    var avgValue: String { Format.paceOrSpeed(distance: distanceM, seconds: max(movingSec > 0 ? movingSec : elapsedSec, 1), kind: kind).replacingOccurrences(of: "--", with: "—") }
    var topValue: String { maxSpeed > 0 ? Format.speed(maxSpeed) : "—" }
}

// MARK: - Route helpers

enum RecapRoute {
    /// Drops the first and last `meters` of the route so the card doesn't show where you live.
    /// Very short routes come back empty (nothing safe to draw).
    static func privacyTrim(_ c: [CLLocationCoordinate2D], meters: Double = 200) -> [CLLocationCoordinate2D] {
        guard c.count > 1 else { return [] }
        func cutIndex(_ list: [CLLocationCoordinate2D]) -> Int {
            var d = 0.0
            for i in 1..<list.count {
                d += Geo.distance(list[i - 1], list[i])
                if d >= meters { return i }
            }
            return list.count
        }
        let head = cutIndex(c)
        let tail = cutIndex(Array(c.reversed()))
        let lo = head, hi = c.count - 1 - tail
        guard hi - lo >= 1 else { return [] }
        return Array(c[lo...hi])
    }

    /// Keeps at most `maxCount` points, always including both ends.
    static func thin(_ c: [CLLocationCoordinate2D], maxCount: Int = 1500) -> [CLLocationCoordinate2D] {
        guard c.count > maxCount, maxCount > 2 else { return c }
        let step = Double(c.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { c[min(c.count - 1, Int((Double($0) * step).rounded()))] }
    }
}

// MARK: - Map snapshot

enum RecapMap {
    /// Dark, muted map of the route with the route drawn on it. `pixels` is the output size.
    /// `bottomFade` leaves room at the bottom (fraction of height) where the card fades out.
    @MainActor
    static func snapshot(route: [CLLocationCoordinate2D], pixels: CGSize, bottomFade: CGFloat) async -> UIImage? {
        guard route.count > 1 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: pixels.width / scale, height: pixels.height / scale)

        // Fit the route with some padding, matched to the image's shape.
        let pts = route.map { MKMapPoint($0) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        var rect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let minSide = 600 * MKMapPointsPerMeterAtLatitude(route[0].latitude)
        if rect.size.width < minSide { rect = rect.insetBy(dx: -(minSide - rect.size.width) / 2, dy: 0) }
        if rect.size.height < minSide { rect = rect.insetBy(dx: 0, dy: -(minSide - rect.size.height) / 2) }
        rect = rect.insetBy(dx: -rect.size.width * 0.18, dy: -rect.size.height * 0.18)
        // Extra room at the bottom for the fade, then match the aspect ratio.
        let fadeExtra = rect.size.height * Double(bottomFade) / Double(max(0.2, 1 - bottomFade))
        rect = MKMapRect(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height + fadeExtra)
        let want = Double(size.width / size.height)
        let have = rect.size.width / rect.size.height
        if have < want {
            let w = rect.size.height * want
            rect = rect.insetBy(dx: -(w - rect.size.width) / 2, dy: 0)
        } else {
            let h = rect.size.width / want
            let grow = h - rect.size.height
            rect = MKMapRect(x: rect.origin.x, y: rect.origin.y - grow * 0.4, width: rect.size.width, height: h)
        }

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.traitCollection = UITraitCollection { t in
            t.userInterfaceStyle = .dark
            t.displayScale = scale
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
        let glow = UIColor(Theme.glow), leaf = UIColor(Theme.leaf), gold = UIColor(Theme.gold)
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
            // Soft glow under the line, then the line itself.
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 14, color: leaf.withAlphaComponent(0.9).cgColor)
            leaf.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 11
            path.stroke()
            cg.restoreGState()
            glow.setStroke()
            path.lineWidth = 5
            path.stroke()

            func dot(_ c: CLLocationCoordinate2D, _ fill: UIColor) {
                let p = snap.point(for: c)
                let r: CGFloat = 7
                let o = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                fill.setFill(); o.fill()
                UIColor(Theme.forestDeep).setStroke(); o.lineWidth = 3; o.stroke()
            }
            dot(route[0], .white)
            dot(route[route.count - 1], gold)
        }
    }
}

// MARK: - The card

/// Fixed-size card drawn in pixels (render with scale 1).
struct RecapCardView: View {
    let data: RecapData
    let map: UIImage?
    let format: RecapFormat

    var body: some View {
        Group {
            switch format {
            case .story: story
            case .square: square
            }
        }
        .frame(width: format.size.width, height: format.size.height)
        .background(Theme.forestDeep)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    // Story: map on top fading into the stats.
    private var story: some View {
        ZStack(alignment: .top) {
            Theme.background
            RadialGradient(colors: [Theme.leaf.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 900)
            mapLayer
                .frame(width: format.mapSize.width, height: format.mapSize.height)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: Theme.forestDeep.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .clear, location: 0.6),
                        .init(color: Theme.forestDeep, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 90)
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text(Format.dayTime(data.date).uppercased())
                        .font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(3)
                        .foregroundStyle(Theme.glow)
                    Text(data.title)
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    if let f = data.friends {
                        Label(f, systemImage: "person.2.fill")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Format.distanceValue(data.distanceM))
                        .font(.system(size: 210, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.leafGradient)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(Format.distanceUnit)
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 18)
                Grid(horizontalSpacing: 24, verticalSpacing: 24) {
                    GridRow {
                        tile(Format.duration(data.elapsedSec), "Time", "clock.fill")
                        tile(data.avgValue, data.avgLabel, "speedometer")
                    }
                    GridRow {
                        tile(data.topValue, "Top speed", "gauge.with.dots.needle.67percent")
                        tile(Format.elevation(data.elevGainM), "Climb", "mountain.2.fill")
                    }
                }
                .padding(.top, 26)
                footer.padding(.top, 50).padding(.bottom, 90)
            }
            .padding(.horizontal, 80)
        }
    }

    // Square: map fills the frame, numbers along the bottom.
    private var square: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.background
            mapLayer
                .frame(width: format.size.width, height: format.size.height)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: Theme.forestDeep.opacity(0.6), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.4),
                        .init(color: Theme.forestDeep.opacity(0.92), location: 0.72),
                        .init(color: Theme.forestDeep, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 60)
                Spacer()
                Text(Format.dayTime(data.date).uppercased())
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).tracking(2.5)
                    .foregroundStyle(Theme.glow)
                Text(data.title)
                    .font(.system(size: 62, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)
                if let f = data.friends {
                    Label(f, systemImage: "person.2.fill")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                HStack(spacing: 0) {
                    inline("\(Format.distanceValue(data.distanceM)) \(Format.distanceUnit)", "Distance")
                    inline(Format.duration(data.elapsedSec), "Time")
                    inline(data.avgValue, data.avgLabel)
                    inline(data.kind.isOnFoot ? Format.elevation(data.elevGainM) : data.topValue,
                           data.kind.isOnFoot ? "Climb" : "Top speed")
                }
                .padding(.top, 30)
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 60)
        }
    }

    @ViewBuilder private var mapLayer: some View {
        if let map {
            Image(uiImage: map).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Theme.moss, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
                Image(systemName: data.kind.symbol)
                    .font(.system(size: 320, weight: .bold))
                    .foregroundStyle(Theme.leafGradient)
                    .opacity(0.25)
            }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 14) {
                Image(systemName: data.kind.symbol)
                    .font(.system(size: format == .story ? 34 : 28, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: format == .story ? 76 : 62, height: format == .story ? 76 : 62)
                    .background(Theme.leafGradient, in: Circle())
                Text(data.kind.title.uppercased())
                    .font(.system(size: format == .story ? 34 : 28, weight: .black, design: .rounded)).tracking(3)
                    .foregroundStyle(.white)
            }
            .padding(.leading, 8).padding(.trailing, 28).padding(.vertical, 8)
            .background(.black.opacity(0.35), in: Capsule())
            Spacer()
            wordmark
        }
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: format == .story ? 40 : 32, weight: .bold))
                .foregroundStyle(Theme.leafGradient)
            Text(AppInfo.name)
                .font(.system(size: format == .story ? 40 : 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
    }

    private var footer: some View {
        HStack {
            Rectangle().fill(Theme.glow.opacity(0.5)).frame(width: 60, height: 4)
            Text("Tracked with \(AppInfo.name)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.glow)
            Text(value)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: 24, weight: .bold, design: .rounded)).tracking(2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 2))
    }

    private func inline(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label.uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Share sheet

/// Preview of the recap card with Story / Square, the privacy trim, and Share.
@MainActor
struct RecapShareView: View {
    let activity: Activity
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recap.hideEnds") private var hideEnds = true
    @AppStorage("recap.format") private var formatRaw = RecapFormat.story.rawValue
    @AppStorage("useMetric") private var useMetric = false
    @ObservedObject private var groups = GroupHistory.shared
    @State private var maps: [String: UIImage] = [:]
    @State private var rendered: UIImage?
    @State private var loading = false

    private var format: RecapFormat { RecapFormat(rawValue: formatRaw) ?? .story }
    private var key: String { "\(format.rawValue)-\(hideEnds)-\(useMetric)" }
    private var friends: String? { groups.log(for: activity.id).map(\.withLabel) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Picker("Format", selection: $formatRaw) {
                    ForEach(RecapFormat.allCases) { f in Text(f.title).tag(f.rawValue) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: formatRaw)

                Toggle(isOn: $hideEnds) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide start & end").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        Text("Leaves the first and last 200 m off the map, so your home stays private.")
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.leaf)
                .sensoryFeedback(.selection, trigger: hideEnds)

                if let img = rendered {
                    ShareLink(item: Image(uiImage: img),
                              preview: SharePreview(activity.displayTitle, image: Image(uiImage: img))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .haptic(.medium)
                } else {
                    Label("Making your card…", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                        .font(Theme.rounded(17, .bold))
                        .foregroundStyle(Theme.textDim)
                        .padding(.vertical, 15)
                }
            }
            .padding(Theme.pad)
            .forestScreen()
            .navigationTitle("Share recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: key) { await build() }
        }
    }

    @ViewBuilder private var preview: some View {
        if let img = rendered {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .opacity(loading ? 0.6 : 1)
                .overlay { if loading { ProgressView().tint(.white) } }
                .accessibilityElement()
                .accessibilityLabel("Recap card preview")
                .accessibilityValue("\(activity.displayTitle), \(Format.distance(activity.distanceM)), \(Format.duration(activity.elapsedSec))")
                .animation(.easeInOut(duration: 0.2), value: loading)
        } else {
            ProgressView().tint(.white)
                .accessibilityLabel("Making your recap card")
        }
    }

    private func build() async {
        loading = true
        defer { loading = false }
        let f = format
        let mapKey = "\(f.rawValue)-\(hideEnds)"
        var map = maps[mapKey]
        if map == nil {
            let all = activity.route.map(\.coordinate)
            let coords = RecapRoute.thin(hideEnds ? RecapRoute.privacyTrim(all) : all)
            map = await RecapMap.snapshot(route: coords, pixels: f.mapSize, bottomFade: f == .story ? 0.28 : 0.45)
            if Task.isCancelled { return }
            if let map { maps[mapKey] = map }
        }
        let card = RecapCardView(data: RecapData(activity, friends: friends), map: map, format: f)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(f.size)
        if let img = renderer.uiImage { rendered = img }
    }
}
