import SwiftUI
import Photos
import Vision
import CoreLocation

/// Nature Roll: finds the nature in your camera roll, on this iPhone, with Apple's built-in image recognition.
/// Nothing is uploaded. To rename the feature, change `title` below (album names follow it).
enum NatureRoll {
    static let title = "Nature Roll"
    static let symbol = "photo.stack.fill"
    /// Album name in the Photos app for one category, e.g. "Nature Roll · Trees".
    static func albumName(_ c: NatureCategory) -> String { "\(title) · \(c.short)" }
}

// MARK: - Categories

enum NatureCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case trees, flowers, mountains, water, sky, animals, trails

    var id: String { rawValue }

    var name: String {
        switch self {
        case .trees: return "Trees & Forests"
        case .flowers: return "Flowers & Plants"
        case .mountains: return "Mountains & Hills"
        case .water: return "Water"
        case .sky: return "Sky & Sunsets"
        case .animals: return "Animals & Birds"
        case .trails: return "Trails & Parks"
        }
    }

    var short: String {
        switch self {
        case .trees: return "Trees"
        case .flowers: return "Flowers"
        case .mountains: return "Mountains"
        case .water: return "Water"
        case .sky: return "Sky"
        case .animals: return "Animals"
        case .trails: return "Trails"
        }
    }

    var symbol: String {
        switch self {
        case .trees: return "tree.fill"
        case .flowers: return "camera.macro"
        case .mountains: return "mountain.2.fill"
        case .water: return "water.waves"
        case .sky: return "sun.horizon.fill"
        case .animals: return "bird.fill"
        case .trails: return "figure.hiking"
        }
    }

    var tint: Color {
        switch self {
        case .trees: return Theme.leaf
        case .flowers: return Color(red: 1, green: 0.55, blue: 0.75)
        case .mountains: return Color(red: 0.75, green: 0.7, blue: 0.62)
        case .water: return Theme.sky
        case .sky: return Theme.gold
        case .animals: return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .trails: return Theme.glow
        }
    }

    /// Words in Vision's classification labels (e.g. "sunset_sunrise", "waterfall") that point to this category.
    var keywords: Set<String> {
        switch self {
        case .trees: return ["tree", "forest", "woodland", "jungle", "redwood", "palm", "conifer", "evergreen", "trunk", "bark"]
        case .flowers: return ["flower", "plant", "blossom", "foliage", "leaf", "garden", "rose", "tulip", "sunflower", "daisy",
                               "cactus", "succulent", "fern", "moss", "mushroom", "orchid", "lily", "bouquet", "grass", "meadow"]
        case .mountains: return ["mountain", "hill", "cliff", "canyon", "volcano", "rock", "valley", "peak", "glacier", "desert", "dune"]
        case .water: return ["ocean", "sea", "lake", "river", "waterfall", "beach", "shore", "coast", "waterways", "creek", "stream",
                             "pond", "wave", "surf", "bay", "lagoon", "water"]
        case .sky: return ["sky", "sunset", "sunrise", "cloud", "clouds", "rainbow", "aurora", "dusk", "dawn", "moon", "night_sky", "star"]
        case .animals: return ["animal", "bird", "wildlife", "deer", "squirrel", "butterfly", "insect", "bee", "owl", "hawk", "eagle",
                               "duck", "goose", "heron", "seagull", "pelican", "rabbit", "fox", "bear", "elk", "moose", "lizard",
                               "reptile", "frog", "turtle", "seal", "whale", "dolphin", "horse", "cow", "sheep", "goat", "hummingbird"]
        case .trails: return ["trail", "path", "park", "hiking", "hike", "campground", "camping", "tent", "outdoor", "countryside",
                              "national_park", "footpath", "grassland", "field", "prairie"]
        }
    }

    /// Labels that mean "pet or indoors", so a dog photo isn't filed under wildlife.
    static let petLabels: Set<String> = ["dog", "cat", "puppy", "kitten", "pet"]
    static let minConfidence: Float = 0.3

    /// Maps Vision observations to nature categories with the best confidence seen for each.
    static func classify(_ observations: [(String, Float)]) -> [NatureCategory: Float] {
        var out: [NatureCategory: Float] = [:]
        let confident = observations.filter { $0.1 >= minConfidence }
        let isPet = confident.contains { petLabels.contains($0.0) }
        for (label, conf) in confident {
            let words = Set(label.lowercased().split(separator: "_").map(String.init))
            for c in NatureCategory.allCases {
                if c == .animals && isPet { continue }
                if c.keywords.contains(label.lowercased()) || !c.keywords.isDisjoint(with: words) {
                    out[c] = max(out[c] ?? 0, conf)
                }
            }
        }
        // "water" alone (a glass, a pool) is weak: keep it only when it's strong.
        if let w = out[.water], w < 0.5, !confident.contains(where: { ["ocean", "lake", "river", "waterfall", "beach", "shore", "sea"].contains($0.0) }) {
            out[.water] = nil
        }
        return out
    }
}

// MARK: - What's stored (on this iPhone only)

struct NatureRecord: Codable, Identifiable, Hashable {
    /// PHAsset localIdentifier.
    let id: String
    /// Category raw value → Vision confidence (0…1).
    var cats: [String: Float]
    var date: Date?
    var lat: Double?
    var lng: Double?

    var categories: [NatureCategory] {
        cats.sorted { $0.value > $1.value }.compactMap { NatureCategory(rawValue: $0.key) }
    }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private struct NatureIndex: Codable {
    var records: [String: NatureRecord] = [:]
    /// Every photo already looked at (nature or not), so a later scan only does new photos.
    var scanned: Set<String> = []
    var lastScan: Date?
}

// MARK: - Scanner + local index

@MainActor
final class NatureRollStore: ObservableObject {
    static let shared = NatureRollStore()

    @Published private(set) var records: [String: NatureRecord] = [:]
    @Published private(set) var scanning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var lastScan: Date?
    @Published private(set) var auth: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var scanned: Set<String> = []
    private var task: Task<Void, Never>?
    private static let started = "natureRoll.started"

    /// The person asked for a scan at least once (so a scan never starts on its own before that).
    var hasStarted: Bool { UserDefaults.standard.bool(forKey: Self.started) }
    var canRead: Bool { auth == .authorized || auth == .limited }

    private static var fileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("NatureRoll", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent("index.json")
        // A local index of your own photos: not backed up to iCloud (it's rebuilt from the library).
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let idx = try? JSONDecoder().decode(NatureIndex.self, from: data) {
            records = idx.records; scanned = idx.scanned; lastScan = idx.lastScan
        }
    }

    // MARK: Queries

    var all: [NatureRecord] { records.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }

    func records(in c: NatureCategory?) -> [NatureRecord] {
        guard let c else { return all }
        return all.filter { $0.cats[c.rawValue] != nil }
    }

    func count(_ c: NatureCategory) -> Int { records.values.reduce(0) { $0 + ($1.cats[c.rawValue] != nil ? 1 : 0) } }

    /// Nature photos taken on today's date in earlier years, newest year first.
    func onThisDay(_ today: Date = Date()) -> [(year: Int, items: [NatureRecord])] {
        let cal = Calendar.current
        let m = cal.component(.month, from: today), d = cal.component(.day, from: today), y = cal.component(.year, from: today)
        let hits = all.filter {
            guard let date = $0.date else { return false }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return c.month == m && c.day == d && (c.year ?? y) < y
        }
        return Dictionary(grouping: hits) { cal.component(.year, from: $0.date!) }
            .map { (year: $0.key, items: $0.value) }
            .sorted { $0.year > $1.year }
    }

    // MARK: Access

    func refreshAuth() { auth = PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    /// Reading the library needs .readWrite (PhotoKit's read level); "Limited" access works fine too.
    func requestAccess() async -> Bool {
        var s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined { s = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        auth = s
        return canRead
    }

    // MARK: Scanning

    /// On app open: only new photos, and only if the person already turned Nature Roll on.
    func scanIfAllowed() {
        refreshAuth()
        guard hasStarted, canRead, !scanning else { return }
        start()
    }

    func scanNow() async {
        UserDefaults.standard.set(true, forKey: Self.started)
        guard await requestAccess(), !scanning else { return }
        start()
    }

    func cancel() {
        task?.cancel()
    }

    /// Forget everything Nature Roll found (the photos themselves are untouched).
    func reset() {
        cancel()
        records = [:]; scanned = []; lastScan = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
        UserDefaults.standard.set(false, forKey: Self.started)
    }

    private func start() {
        scanning = true
        done = 0; total = 0
        let alreadyScanned = scanned
        task = Task.detached(priority: .utility) { [weak self] in
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Screenshots aren't nature.
            opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let result = PHAsset.fetchAssets(with: .image, options: opts)

            var present = Set<String>()
            var todo: [PHAsset] = []
            result.enumerateObjects { a, _, _ in
                present.insert(a.localIdentifier)
                if !alreadyScanned.contains(a.localIdentifier) { todo.append(a) }
            }
            await self?.begin(total: todo.count, present: present)

            let manager = PHImageManager.default()
            let req = PHImageRequestOptions()
            req.isSynchronous = true
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = false   // only what's already on the phone; iCloud-only photos are picked up later
            let size = CGSize(width: 300, height: 300)

            var batch: [(String, NatureRecord?)] = []
            for asset in todo {
                if Task.isCancelled { break }
                autoreleasepool {
                    var image: CGImage?
                    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: req) { img, _ in
                        image = img?.cgImage
                    }
                    guard let image else { batch.append((asset.localIdentifier + "\u{0}skip", nil)); return }
                    let request = VNClassifyImageRequest()
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try? handler.perform([request])
                    let obs = (request.results ?? []).map { ($0.identifier, $0.confidence) }
                    let cats = NatureCategory.classify(obs)
                    let rec: NatureRecord? = cats.isEmpty ? nil : NatureRecord(
                        id: asset.localIdentifier,
                        cats: Dictionary(uniqueKeysWithValues: cats.map { ($0.key.rawValue, $0.value) }),
                        date: asset.creationDate,
                        lat: asset.location?.coordinate.latitude, lng: asset.location?.coordinate.longitude)
                    batch.append((asset.localIdentifier, rec))
                }
                if batch.count >= 40 {
                    let b = batch; batch = []
                    await self?.merge(b)
                }
            }
            let b = batch
            await self?.merge(b)
            await self?.finish()
        }
    }

    private func begin(total: Int, present: Set<String>) {
        self.total = total
        // Photos deleted from the library drop out of Nature Roll.
        let gone = records.keys.filter { !present.contains($0) }
        for k in gone { records[k] = nil }
        scanned = scanned.intersection(present)
    }

    private func merge(_ batch: [(String, NatureRecord?)]) {
        guard !batch.isEmpty else { return }
        for (id, rec) in batch {
            done += 1
            // A photo that isn't on the phone yet (iCloud only) is tried again next scan.
            if id.hasSuffix("\u{0}skip") { continue }
            scanned.insert(id)
            if let rec { records[id] = rec }
        }
        save()
    }

    private func finish() {
        scanning = false
        lastScan = Date()
        task = nil
        save()
    }

    private func save() {
        let idx = NatureIndex(records: records, scanned: scanned, lastScan: lastScan)
        let url = Self.fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(idx) { try? data.write(to: url, options: .atomic) }
        }
    }
}

// MARK: - Photos helpers

enum NatureRollPhotos {
    static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// A display-size image (one callback; may fetch from your own iCloud Photos).
    static func image(_ id: String, side: CGFloat) async -> UIImage? {
        guard let a = asset(id) else { return nil }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        let scale = await MainActor.run { UIScreen.main.scale }
        let target = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: a, targetSize: target, contentMode: .aspectFill, options: opts) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    /// The original file (with its EXIF date and GPS), for "Make this a hug".
    static func original(_ id: String) async -> (data: Data, info: PhotoAssetInfo)? {
        guard let a = asset(id) else { return nil }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.version = .current
        let data: Data? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: opts) { d, _, _, _ in
                cont.resume(returning: d)
            }
        }
        guard let data else { return nil }
        return (data, PhotoAssetInfo(date: a.creationDate, coordinate: a.location?.coordinate))
    }

    /// Adds photos to "Nature Roll · <category>" in the Photos app, creating the album if needed.
    /// Only ever runs when the person taps a button. Returns how many photos were newly added.
    @discardableResult
    static func addToAlbum(_ ids: [String], category: NatureCategory) async throws -> Int {
        let name = NatureRoll.albumName(category)
        let album = try await albumNamed(name)
        let existing = PHAsset.fetchAssets(in: album, options: nil)
        var have = Set<String>()
        existing.enumerateObjects { a, _, _ in have.insert(a.localIdentifier) }
        let fresh = ids.filter { !have.contains($0) }
        guard !fresh.isEmpty else { return 0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: fresh, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
        }
        return assets.count
    }

    private static func albumNamed(_ name: String) async throws -> PHAssetCollection {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title == %@", name)
        if let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts).firstObject {
            return found
        }
        final class Box: @unchecked Sendable { var id: String? }
        let box = Box()
        try await PHPhotoLibrary.shared().performChanges {
            box.id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let placeholder = box.id,
              let made = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder], options: nil).firstObject
        else { throw CocoaError(.fileWriteUnknown) }
        return made
    }
}
