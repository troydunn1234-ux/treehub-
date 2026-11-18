import SwiftUI
import UIKit
import ImageIO

/// Rootbound's photos, decoded once at the size they're shown and kept in memory.
///
/// Hug photos are stored as JPEGs up to 1800 px. Decoding one with `UIImage(data:)` inside a view's body ran on
/// the main thread on every redraw: the Home hero (redrawn on every scroll frame), the tree grid and the map
/// rows all stuttered with it. Here a photo is downsampled off the main thread with ImageIO, at the pixel size
/// the screen needs, and cached; views show a calm placeholder for the few milliseconds it takes the first time.
/// Read-only: nothing here changes the stored photos.
final class RBPhotoCache: @unchecked Sendable {
    static let shared = RBPhotoCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    /// A key for `data` at `maxPixel`: its length plus three short slices (header, middle, tail). JPEG headers
    /// repeat from photo to photo, the coded image data doesn't. Cheap enough to compute in a view's body.
    static func key(_ data: Data, maxPixel: Int) -> NSString {
        var h = Hasher()
        h.combine(data.count)
        h.combine(maxPixel)
        let n = data.count
        let slice = 256
        for offset in [0, n / 2, max(0, n - slice)] {
            let lo = data.startIndex + min(offset, n)
            let hi = data.startIndex + min(offset + slice, n)
            if lo < hi { h.combine(data[lo..<hi]) }
        }
        return NSString(string: String(h.finalize()))
    }

    func image(_ key: NSString) -> UIImage? { cache.object(forKey: key) }

    func store(_ image: UIImage, _ key: NSString) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }

    /// The photo scaled so its longer side is at most `maxPixel` pixels (EXIF orientation applied). Any thread.
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
    }

    /// Cached image for `data`, decoding it off the main thread the first time.
    func load(_ data: Data, maxPixel: Int) async -> UIImage? {
        let key = Self.key(data, maxPixel: maxPixel)
        if let hit = image(key) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) {
            RBPhotoCache.downsample(data, maxPixel: maxPixel)
        }.value
        if let decoded { store(decoded, key) }
        return decoded
    }
}

/// A stored photo filling its frame, decoded at `points` (its longer side on screen) through `RBPhotoCache`.
/// `placeholder` shows while it decodes and when there's no photo or it can't be read.
struct RBCachedPhoto<Placeholder: View>: View {
    let data: Data?
    /// Longest side the photo is shown at, in points (pixels = points × screen scale).
    var points: CGFloat = 400
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (key: NSString, image: UIImage)?

    private var maxPixel: Int { Int((points * max(displayScale, 1)).rounded(.up)) }

    var body: some View {
        let key = data.map { RBPhotoCache.key($0, maxPixel: maxPixel) }
        let shown: UIImage? = key.flatMap { k in
            if let l = loaded, l.key == k { return l.image }
            return RBPhotoCache.shared.image(k)
        }
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            guard let data, let key else { loaded = nil; return }
            if let hit = RBPhotoCache.shared.image(key) { loaded = (key, hit); return }
            let max = maxPixel
            guard let img = await RBPhotoCache.shared.load(data, maxPixel: max), !Task.isCancelled else { return }
            loaded = (key, img)
        }
    }
}

/// Rootbound's version of the shared `PhotoView`: same forest placeholder, but decoded once at the shown size.
struct RBPhotoView: View {
    let data: Data?
    var placeholder: String = "tree.fill"
    /// Longest side on screen, in points.
    var points: CGFloat = 200

    var body: some View {
        RBCachedPhoto(data: data, points: points) {
            ZStack {
                LinearGradient(colors: [Theme.moss, Theme.forest], startPoint: .top, endPoint: .bottom)
                Image(systemName: placeholder).font(.system(size: 30)).foregroundStyle(Theme.glow.opacity(0.6))
            }
        }
    }
}
