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

// Categories, strictness and the scoring itself live in NatureScore.swift (pure Swift, unit-tested).

// MARK: - What's stored (on this iPhone only)

struct NatureRecord: Codable, Identifiable, Hashable {
    /// PHAsset localIdentifier.
    let id: String
    /// What the scan measured (labels, faces, text, aesthetics, sun, distance from home).
    var signals: NatureSignals
    var date: Date?
    var lat: Double?
    var lng: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// The person's own fixes: "Not nature" and "Move to…", by photo id. Kept across rescans and resets.
struct NatureCorrections: Codable, Equatable {
    var notNature: Set<String> = []
    /// Photo id → category raw values chosen by the person (replaces what the scan decided).
    var moved: [String: [String]] = [:]
}

private struct NatureIndex: Codable {
    /// Bumped whenever the scan measures something new, so old indexes are rebuilt.
    var version: Int?
    var records: [String: NatureRecord] = [:]
    /// Every photo already looked at (nature or not), so a later scan only does new photos.
    var scanned: Set<String> = []
    var lastScan: Date?
}

// MARK: - Scanner + local index

@MainActor
final class NatureRollStore: ObservableObject {
    static let shared = NatureRollStore()
    /// 2: nature score (scene + context + faces + text + aesthetics + sun + home distance) replaced keyword matching.
    static let indexVersion = 2

    /// Every candidate the scan kept (it passed the loosest level); what's shown depends on `strictness`.
    @Published private(set) var records: [String: NatureRecord] = [:]
    /// What's shown right now, newest first.
    @Published private(set) var shown: [NatureRecord] = []
    /// What's shown, best first (nature score × how good it looks).
    @Published private(set) var best: [NatureRecord] = []
    @Published private(set) var scanning = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var lastScan: Date?
    @Published private(set) var auth: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var corrections = NatureCorrections()
    @Published var strictness: NatureStrictness = .strict {
        didSet {
            guard strictness != oldValue else { return }
            UserDefaults.standard.set(strictness.rawValue, forKey: Self.strictKey)
            rebuild()
        }
    }

    private var verdicts: [String: NatureVerdict] = [:]
    private var counts: [NatureCategory: Int] = [:]
    private var scanned: Set<String> = []
    private var task: Task<Void, Never>?
    private static let started = "natureRoll.started"
    private static let strictKey = "natureRoll.strictness"
    private static let correctionsKey = "natureRoll.corrections"

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
        if let raw = UserDefaults.standard.object(forKey: Self.strictKey) as? Int, let s = NatureStrictness(rawValue: raw) {
            strictness = s
        }
        if let data = UserDefaults.standard.data(forKey: Self.correctionsKey),
           let c = try? JSONDecoder().decode(NatureCorrections.self, from: data) {
            corrections = c
        }
        if let data = try? Data(contentsOf: Self.fileURL), let idx = try? JSONDecoder().decode(NatureIndex.self, from: data),
           idx.version == Self.indexVersion {
            records = idx.records; scanned = idx.scanned; lastScan = idx.lastScan
        } else {
            // An index from an older model (or none): start over, the next scan redoes every photo.
            try? FileManager.default.removeItem(at: Self.fileURL)
        }
        rebuild()
    }

    // MARK: Queries

    /// Newest first (a category), or best first ("Best of", `nil`).
    func records(in c: NatureCategory?) -> [NatureRecord] {
        guard let c else { return best }
        return shown.filter { categories(of: $0.id).contains(c) }
    }

    func count(_ c: NatureCategory) -> Int { counts[c] ?? 0 }

    /// The photo's categories, strongest first (the person's own choice wins).
    func categories(of id: String) -> [NatureCategory] {
        if let mine = corrections.moved[id] { return mine.compactMap(NatureCategory.init(rawValue:)) }
        guard let v = verdicts[id] else { return [] }
        return v.categories.sorted { $0.value > $1.value }.map(\.key)
    }

    func verdict(_ id: String) -> NatureVerdict? { verdicts[id] }

    /// Nature photos taken on today's date in earlier years, newest year first.
    func onThisDay(_ today: Date = Date()) -> [(year: Int, items: [NatureRecord])] {
        let cal = Calendar.current
        let m = cal.component(.month, from: today), d = cal.component(.day, from: today), y = cal.component(.year, from: today)
        let hits = shown.filter {
            guard let date = $0.date else { return false }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return c.month == m && c.day == d && (c.year ?? y) < y
        }
        return Dictionary(grouping: hits) { cal.component(.year, from: $0.date!) }
            .map { (year: $0.key, items: $0.value.sorted { (verdicts[$0.id]?.rank ?? 0) > (verdicts[$1.id]?.rank ?? 0) }) }
            .sorted { $0.year > $1.year }
    }

    // MARK: Corrections

    /// Never show this photo again (also skipped by later scans).
    func markNotNature(_ id: String) {
        corrections.notNature.insert(id)
        corrections.moved[id] = nil
        saveCorrections(); rebuild()
    }

    /// File the photo under exactly this category.
    func move(_ id: String, to c: NatureCategory) {
        corrections.moved[id] = [c.rawValue]
        corrections.notNature.remove(id)
        saveCorrections(); rebuild()
    }

    /// Also show it under this category (keeps the others).
    func add(_ id: String, to c: NatureCategory) {
        var cats = categories(of: id).map(\.rawValue)
        if !cats.contains(c.rawValue) { cats.append(c.rawValue) }
        corrections.moved[id] = cats
        saveCorrections(); rebuild()
    }

    func isCorrected(_ id: String) -> Bool { corrections.moved[id] != nil }

    /// Back to what the scan decided for this photo.
    func undoCorrection(_ id: String) {
        corrections.moved[id] = nil
        corrections.notNature.remove(id)
        saveCorrections(); rebuild()
    }

    /// Forget every "Not nature" / "Move to" fix.
    func clearCorrections() {
        corrections = NatureCorrections()
        saveCorrections(); rebuild()
    }

    private func saveCorrections() {
        if let data = try? JSONEncoder().encode(corrections) { UserDefaults.standard.set(data, forKey: Self.correctionsKey) }
    }

    /// Re-scores every stored photo for the current strictness and corrections.
    private func rebuild() {
        var v: [String: NatureVerdict] = [:]
        for (id, r) in records where !corrections.notNature.contains(id) {
            var verdict = NatureScore.evaluate(r.signals, strictness: strictness)
            if corrections.moved[id] != nil {
                // The person said it's nature: always shown, ranked on the score it would have had.
                if !verdict.included {
                    let loose = NatureScore.evaluate(r.signals, strictness: .everything)
                    verdict = NatureVerdict(score: loose.score, categories: loose.categories, excluded: nil, rank: max(loose.rank, 0.3))
                }
            } else if !verdict.included { continue }
            v[id] = verdict
        }
        verdicts = v
        let list = v.keys.compactMap { records[$0] }
        shown = list.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        best = list.sorted { (v[$0.id]?.rank ?? 0, $0.date ?? .distantPast) > (v[$1.id]?.rank ?? 0, $1.date ?? .distantPast) }
        var n: [NatureCategory: Int] = [:]
        for r in list { for c in categories(of: r.id) { n[c, default: 0] += 1 } }
        counts = n
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

    /// Forget everything Nature Roll found (the photos themselves are untouched; "Not nature" fixes are kept).
    func reset() {
        cancel()
        records = [:]; scanned = []; lastScan = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
        UserDefaults.standard.set(false, forKey: Self.started)
        rebuild()
    }

    private func start() {
        scanning = true
        done = 0; total = 0
        let alreadyScanned = scanned
        let notNature = corrections.notNature
        task = Task.detached(priority: .utility) { [weak self] in
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Screenshots aren't nature.
            opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            let result = PHAsset.fetchAssets(with: .image, options: opts)

            var present = Set<String>()
            var todo: [PHAsset] = []
            var points: [(Double, Double)] = []
            result.enumerateObjects { a, _, _ in
                present.insert(a.localIdentifier)
                if let c = a.location?.coordinate { points.append((c.latitude, c.longitude)) }
                if !alreadyScanned.contains(a.localIdentifier) { todo.append(a) }
            }
            // Where most photos are taken (home, work): nature far from there gets a small boost.
            let frequent = FrequentPlaces.find(points)
            points = []
            await self?.begin(total: todo.count, present: present)

            let manager = PHImageManager.default()
            let req = PHImageRequestOptions()
            req.isSynchronous = true
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = false   // only what's already on the phone; iCloud-only photos are picked up later
            let size = CGSize(width: 360, height: 360)

            var batch: [(String, NatureRecord?)] = []
            for asset in todo {
                if Task.isCancelled { break }
                if notNature.contains(asset.localIdentifier) { batch.append((asset.localIdentifier, nil)); continue }
                autoreleasepool {
                    var image: CGImage?
                    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: req) { img, _ in
                        image = img?.cgImage
                    }
                    guard let image else { batch.append((asset.localIdentifier + "\u{0}skip", nil)); return }
                    let coord = asset.location?.coordinate
                    let sun = coord.flatMap { c in asset.creationDate.map { SunPosition.elevation(latitude: c.latitude, longitude: c.longitude, date: $0) } }
                    let km = coord.flatMap { FrequentPlaces.kmToNearest($0.latitude, $0.longitude, places: frequent) }
                    let signals = NatureRollScanner.signals(for: image, sunElevation: sun, kmFromHome: km)
                    let rec: NatureRecord? = signals.map {
                        NatureRecord(id: asset.localIdentifier, signals: $0, date: asset.creationDate,
                                     lat: coord?.latitude, lng: coord?.longitude)
                    }
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
        if !gone.isEmpty { rebuild() }
    }

    private func merge(_ batch: [(String, NatureRecord?)]) {
        guard !batch.isEmpty else { return }
        var added = false
        for (id, rec) in batch {
            done += 1
            // A photo that isn't on the phone yet (iCloud only) is tried again next scan.
            if id.hasSuffix("\u{0}skip") { continue }
            scanned.insert(id)
            if let rec { records[id] = rec; added = true }
        }
        if added { rebuild() }
        save()
    }

    private func finish() {
        scanning = false
        lastScan = Date()
        task = nil
        save()
    }

    private func save() {
        let idx = NatureIndex(version: Self.indexVersion, records: records, scanned: scanned, lastScan: lastScan)
        let url = Self.fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(idx) { try? data.write(to: url, options: .atomic) }
        }
    }
}

// MARK: - Vision (on-device)

enum NatureRollScanner {
    /// Measures one photo. Returns nil when it can't be nature even at the loosest level (most photos),
    /// so the slower face / text / aesthetics checks only run on real candidates.
    static func signals(for image: CGImage, sunElevation: Double?, kmFromHome: Double?) -> NatureSignals? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let classify = VNClassifyImageRequest()
        guard (try? handler.perform([classify])) != nil else { return nil }
        var labels: [String: Float] = [:]
        var precise = Set<String>()
        let top = (classify.results ?? []).filter { $0.confidence >= 0.1 }.sorted { $0.confidence > $1.confidence }.prefix(32)
        for o in top {
            labels[o.identifier] = o.confidence
            // Vision's calibrated cutoff: this label is right ~90% of the time at this confidence.
            if o.hasPrecisionRecallCurve && o.hasMinimumRecall(0.01, forPrecision: 0.9) { precise.insert(o.identifier) }
        }
        var s = NatureSignals(labels: labels, precise: precise, sunElevation: sunElevation, kmFromHome: kmFromHome)
        guard NatureScore.evaluate(s, strictness: .everything).included else { return nil }

        // Faces: a selfie or portrait isn't a nature shot; a hiker small in the frame is fine.
        let faces = VNDetectFaceRectanglesRequest()
        if (try? handler.perform([faces])) != nil {
            s.faceFraction = (faces.results ?? []).map { Float($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
        }
        // Text: signs, menus, documents.
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        if (try? handler.perform([text])) != nil {
            s.textFraction = min((text.results ?? []).reduce(Float(0)) { $0 + Float($1.boundingBox.width * $1.boundingBox.height) }, 1)
        }
        // Aesthetics (iOS 18+): blurry, accidental and utility shots.
        if #available(iOS 18.0, *) {
            let aes = VNCalculateImageAestheticsScoresRequest()
            if (try? handler.perform([aes])) != nil, let r = aes.results?.first {
                s.aesthetic = r.overallScore
                s.isUtility = r.isUtility
            }
        }
        return NatureScore.evaluate(s, strictness: .everything).included ? s : nil
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
