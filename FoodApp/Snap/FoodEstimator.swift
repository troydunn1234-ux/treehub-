import Foundation
import Security
import UIKit

/// The meal "agent": Claude looks at the plate and sizes each item (FoodAI), then each item is
/// looked up in USDA FoodData Central and its nutrition recomputed from the estimated grams.
/// Lookups are cached on the phone so a food seen once works offline.
enum FoodEstimator {
    enum Stage: Int, CaseIterable {
        case looking, sizing, usda
        var title: String {
            switch self {
            case .looking: return "Looking at your plate"
            case .sizing: return "Sizing portions"
            case .usda: return "Checking USDA"
            }
        }
    }

    /// Nutrition per 100 g, as USDA reports it.
    struct Per100: Codable, Hashable {
        var kcal: Double, protein: Double, carbs: Double, fat: Double
        var description: String
        var dataType: String
    }

    // MARK: Pipeline

    /// Full AI path. Throws if Claude can't read the plate (caller falls back to on-device).
    static func estimate(_ image: UIImage, stage: @escaping @MainActor (Stage) -> Void) async throws -> (plate: [FoodGuess], notes: String?) {
        await stage(.looking)
        // Claude identifies and sizes in one call; flip the label partway so it reads as two steps.
        let sizingFlip = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { stage(.sizing) }
        }
        let read: (items: [FoodAI.Item], notes: String?)
        do { read = try await FoodAI.readPlateDetailed(image) } catch { sizingFlip.cancel(); throw error }
        sizingFlip.cancel()
        await stage(.sizing)
        guard !read.items.isEmpty else { return ([], read.notes) }
        await stage(.usda)
        let plate = await withTaskGroup(of: (Int, FoodGuess).self, returning: [FoodGuess].self) { group in
            for (i, item) in read.items.enumerated() {
                group.addTask { (i, await refine(item)) }
            }
            var out = [(Int, FoodGuess)]()
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return (plate, read.notes)
    }

    /// One Claude item → USDA-backed guess (or Claude's own numbers if USDA can't help).
    static func refine(_ item: FoodAI.Item) async -> FoodGuess {
        var g = FoodAI.guess(from: item)
        guard let hit = await lookup(item.search, cooking: item.cooking + " " + item.name) else { return g }
        let oil = oilAdd(for: item, matched: hit.description)
        let factor = item.grams / 100
        g.cal = (hit.kcal * factor + oil.kcal).rounded()
        g.p = (hit.protein * factor * 10).rounded() / 10
        g.c = (hit.carbs * factor * 10).rounded() / 10
        g.f = ((hit.fat * factor + oil.fat) * 10).rounded() / 10
        g.sourceNote = "USDA: \(hit.description)" + (oil.kcal > 0 ? " + ~\(oil.label) oil" : "")
        // If USDA and Claude disagree wildly (bad match), trust Claude's own numbers.
        if item.kcal > 0, g.cal > 0, max(g.cal, item.kcal) / min(g.cal, item.kcal) > 2.6 {
            return FoodAI.guess(from: item)
        }
        return g
    }

    /// On-device plate (no Claude key): look each item up in USDA too when its serving has a weight.
    static func enrich(_ plate: [FoodGuess]) async -> [FoodGuess] {
        await withTaskGroup(of: (Int, FoodGuess).self, returning: [FoodGuess].self) { group in
            for (i, g) in plate.enumerated() {
                group.addTask {
                    guard let grams = gramsFromServing(g.serving),
                          let hit = await lookup(g.name, cooking: g.name, timeout: 6) else { return (i, g) }
                    var out = g
                    let f = grams / 100
                    let cal = (hit.kcal * f).rounded()
                    // Only replace when USDA lands in the same ballpark as the built-in table.
                    guard g.cal <= 0 || (cal > 0 && max(cal, g.cal) / min(cal, g.cal) < 1.8) else { return (i, g) }
                    out.cal = cal
                    out.p = (hit.protein * f * 10).rounded() / 10
                    out.c = (hit.carbs * f * 10).rounded() / 10
                    out.f = (hit.fat * f * 10).rounded() / 10
                    out.grams = grams; out.gramsLow = (grams * 0.6).rounded(); out.gramsHigh = (grams * 1.6).rounded()
                    out.sourceNote = "USDA: \(hit.description)"
                    return (i, out)
                }
            }
            var out = [(Int, FoodGuess)]()
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// "6 oz", "170 g", "1 cup (150 g)" → grams. Nil when the serving has no weight.
    static func gramsFromServing(_ s: String) -> Double? {
        let low = s.lowercased()
        func number(before unit: String) -> Double? {
            guard let r = low.range(of: unit) else { return nil }
            let head = low[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let digits = head.reversed().prefix { "0123456789.".contains($0) }
            return Double(String(digits.reversed()))
        }
        if let g = number(before: " g") ?? number(before: "g)") ?? (low.hasSuffix("g") ? number(before: "g") : nil), g > 0 { return g }
        if let oz = number(before: " oz") ?? number(before: "oz"), oz > 0 { return (oz * 28.35).rounded() }
        return nil
    }

    // MARK: Cooking oil

    /// Roasted/fried/sautéed veg and potatoes soak up oil that plain USDA "cooked" entries leave out.
    /// Roughly 1 tsp (4.5 g fat, 40 kcal) per 150 g, unless the USDA match already includes fat.
    static func oilAdd(for item: FoodAI.Item, matched: String) -> (kcal: Double, fat: Double, label: String) {
        let how = (item.cooking + " " + item.name).lowercased()
        let m = matched.lowercased()
        let oily = ["roast", "fried", "fry", "sauté", "saute", "oil", "butter", "pan-seared", "pan seared"].contains { how.contains($0) }
        let alreadyIn = ["fat added", "with oil", "with butter", "fried", "oil", "margarine", "with fat"].contains { m.contains($0) }
        let meat = ["steak", "beef", "chicken", "pork", "salmon", "fish", "shrimp", "turkey", "lamb"].contains { how.contains($0) }
        guard oily, !alreadyIn, !meat, item.grams > 20 else { return (0, 0, "") }
        let tsp = max(0.5, (item.grams / 150 * 2).rounded() / 2)   // nearest ½ tsp
        let label = tsp == 1 ? "1 tsp" : "\(tsp.formatted()) tsp"
        return (40 * tsp, 4.5 * tsp, label)
    }

    // MARK: USDA FoodData Central

    private static let base = "https://api.nal.usda.gov/fdc/v1/foods/search"
    private static let cookedWords = ["cooked", "grilled", "roasted", "baked", "broiled", "fried", "boiled", "steamed",
                                      "sauteed", "sautéed", "braised", "stewed", "scrambled", "poached", "pan", "seared", "toasted", "mashed"]

    /// Best USDA match per 100 g for a search phrase. Cached forever on the phone.
    static func lookup(_ search: String, cooking: String, timeout: TimeInterval = 10) async -> Per100? {
        let phrase = search.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return nil }
        if let hit = Cache.shared.get(phrase) { return hit }

        var comps = URLComponents(string: base)!
        comps.queryItems = [
            URLQueryItem(name: "query", value: phrase),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)"),
            URLQueryItem(name: "pageSize", value: "8"),
            URLQueryItem(name: "api_key", value: USDAKey.key ?? "DEMO_KEY"),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = obj["foods"] as? [[String: Any]], !foods.isEmpty else { return nil }

        let wantsCooked = cookedWords.contains { cooking.lowercased().contains($0) || phrase.contains($0) }
        let queryWords = Set(phrase.split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
        var best: (score: Double, per: Per100)?
        for f in foods {
            guard let desc = f["description"] as? String, let per = per100(f, description: desc) else { continue }
            let d = desc.lowercased()
            let type = (f["dataType"] as? String) ?? ""
            let words = Set(d.split { !$0.isLetter }.map(String.init))
            var score = Double(queryWords.intersection(words).count) * 2
            if wantsCooked {
                if type.contains("Survey") { score += 2 }
                if cookedWords.contains(where: { d.contains($0) }) { score += 2 }
                if d.contains("raw") { score -= 4 }
            } else if type == "Foundation" || type == "SR Legacy" { score += 1.5 }
            for w in cookedWords where cooking.lowercased().contains(w) && d.contains(w) { score += 1.5 }
            if d.contains("baby food") || d.contains("infant") { score -= 6 }
            score -= Double(words.subtracting(queryWords).count) * 0.15   // prefer tighter descriptions
            if best == nil || score > best!.score { best = (score, per) }
        }
        guard let pick = best?.per else { return nil }
        Cache.shared.set(phrase, pick)
        return pick
    }

    private static func per100(_ f: [String: Any], description: String) -> Per100? {
        guard let ns = f["foodNutrients"] as? [[String: Any]] else { return nil }
        var kcal: Double?, kcalAlt: Double?, p = 0.0, c = 0.0, fat = 0.0
        for n in ns {
            let id = Int(FoodAI.num(n["nutrientId"]))
            let v = FoodAI.num(n["value"])
            switch id {
            case 1008: kcal = v
            case 2047, 2048: if kcalAlt == nil { kcalAlt = v }
            case 1003: p = v
            case 1005: c = v
            case 1004: fat = v
            default: break
            }
        }
        // Energy sometimes only comes in kJ (1062); convert if that's all there is.
        if kcal == nil && kcalAlt == nil,
           let kj = ns.first(where: { Int(FoodAI.num($0["nutrientId"])) == 1062 }).map({ FoodAI.num($0["value"]) }) {
            kcal = kj / 4.184
        }
        guard let energy = kcal ?? kcalAlt, energy > 0, energy < 950 else { return nil }
        let clean = description.prefix(1).uppercased() + description.dropFirst()
        return Per100(kcal: energy, protein: p, carbs: c, fat: fat, description: String(clean.prefix(70)),
                      dataType: (f["dataType"] as? String) ?? "")
    }

    /// search phrase → USDA per-100 g, saved in Application Support.
    final class Cache: @unchecked Sendable {
        static let shared = Cache()
        private let lock = NSLock()
        private var map: [String: Per100] = [:]
        private let url: URL? = {
            guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("usda-cache.json")
        }()

        init() {
            if let url, let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: Per100].self, from: d) { map = m }
        }

        func get(_ k: String) -> Per100? { lock.lock(); defer { lock.unlock() }; return map[k] }

        func set(_ k: String, _ v: Per100) {
            lock.lock()
            map[k] = v
            let snapshot = map
            lock.unlock()
            guard let url, let d = try? JSONEncoder().encode(snapshot) else { return }
            try? d.write(to: url, options: .atomic)
        }
    }
}

/// Optional personal USDA FoodData Central key (free at fdc.nal.usda.gov). Without one, the shared
/// DEMO_KEY is used, which is fine for light use. Stored only in this phone's Keychain.
enum USDAKey {
    private static let service = "foodbook.usda"
    private static let account = "apiKey"

    static var hasKey: Bool { key != nil }

    static var key: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    @discardableResult
    static func save(key raw: String) -> Bool {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count >= 20, k.count <= 80, k.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        remove()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(k.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
