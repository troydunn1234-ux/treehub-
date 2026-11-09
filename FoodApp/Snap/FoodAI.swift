import Foundation
import Security
import UIKit

/// Optional "Smart photo": sends a small copy of the meal photo to Claude (with the user's own
/// Anthropic API key) and gets back every item on the plate with estimated portions and macros.
/// The key lives only in this phone's Keychain. Without a key, Food Book guesses on-device.
enum FoodAI {
    /// Change this to use a different Claude model.
    static let model = "claude-sonnet-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: Key storage (Keychain, this device only)

    private static let service = "foodbook.anthropic"
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

    /// Saves a key that looks like an Anthropic key. Returns false if it doesn't.
    @discardableResult
    static func save(key raw: String) -> Bool {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.hasPrefix("sk-ant-"), k.count > 20, !k.contains(" ") else { return false }
        removeKey()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(k.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func removeKey() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: Reading a plate

    enum AIError: Error { case noKey, badResponse, http(Int) }

    /// One item as Claude described it: identity, cooking, estimated weight (with range and the size
    /// reference it used), a USDA-friendly search phrase, and its own nutrition guess as a fallback.
    struct Item: Hashable {
        var name: String
        var search: String
        var grams: Double
        var gramsLow: Double
        var gramsHigh: Double
        var cooking: String
        var reference: String
        var confidence: Double
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    private static let prompt = """
    You are a careful nutrition estimator looking at one meal photo. Work in three steps, then answer with JSON only.
    1. IDENTIFY every distinct food as specifically as you can see it, as separate items (e.g. "grilled sirloin steak, sliced", "roasted baby potatoes with skin", "roasted asparagus"). Note the cooking method and any visible oil, butter, cheese, sauce or dressing.
    2. SIZE each item in grams. Use whatever reference is in the picture and say which one you used: a standard glass meal-prep container is about 950 ml (about 18 x 13 cm); a dinner plate is about 26 cm across; a fork is about 19 cm long; an adult palm is about 8-9 cm wide and a hand about 18-19 cm long; a 12 oz can is 12 cm tall; a takeout clamshell is about 23 x 23 cm. Account for depth and items hidden underneath. Give your best estimate plus a realistic low/high range.
    3. For each item give a short search phrase that would find it in the USDA FoodData Central database (e.g. "beef top sirloin steak cooked grilled", "potatoes roasted with oil", "asparagus cooked"), your confidence 0-1, and your own estimate of kcal, protein, carbs and fat for the estimated grams (cooking fat included).
    Reply with ONLY this JSON, no other text:
    {"items":[{"name":"Grilled sirloin steak","search":"beef top sirloin steak cooked grilled","grams":170,"grams_low":140,"grams_high":210, "cooking":"grilled, no visible sauce","reference":"meal-prep container","confidence":0.75,"kcal":350,"protein":50,"carbs":0,"fat":15}], "notes":"one short sentence"}
    Use short everyday names (2-4 words) in "name". If the photo isn't food, reply {"items":[],"notes":"no food"}.
    """

    /// Asks Claude what's on the plate and how much. Throws on any failure so the caller can fall back.
    static func readPlateDetailed(_ image: UIImage) async throws -> (items: [Item], notes: String?) {
        guard let key else { throw AIError.noKey }
        let small = FoodVision.prepared(image, maxSide: 1024)
        guard let jpeg = small.jpegData(compressionQuality: 0.6) else { throw AIError.badResponse }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]
        var req = URLRequest(url: endpoint, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AIError.http(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { throw AIError.badResponse }
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return try parseDetailed(text)
    }

    /// Old simple shape, kept for callers that only want guesses with Claude's own numbers.
    static func readPlate(_ image: UIImage) async throws -> [FoodGuess] {
        try await readPlateDetailed(image).items.map(guess(from:))
    }

    static func guess(from i: Item) -> FoodGuess {
        let ref = i.reference.isEmpty ? nil : "sized from \(i.reference.lowercased().hasPrefix("your") ? "" : "the ")\(i.reference)"
        return FoodGuess(name: i.name, serving: "\(Int(i.grams.rounded())) g", cal: i.kcal.rounded(),
                         p: (i.protein * 10).rounded() / 10, c: (i.carbs * 10).rounded() / 10, f: (i.fat * 10).rounded() / 10,
                         source: .photo, grams: i.grams, gramsLow: i.gramsLow, gramsHigh: i.gramsHigh,
                         sourceNote: "Claude estimate", sizedFrom: ref)
    }

    static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.filter { "0123456789.".contains($0) }) ?? 0 }
        return 0
    }

    /// Pulls the JSON object out of the reply (tolerates ```json fences or extra words around it).
    static func parseDetailed(_ text: String) throws -> (items: [Item], notes: String?) {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { throw AIError.badResponse }
        let out: [Item] = items.compactMap { i in
            guard let raw = (i["name"] as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            let name = raw.prefix(1).uppercased() + raw.dropFirst()
            var grams = num(i["grams"])
            let kcal = num(i["kcal"])
            guard grams > 0 || kcal > 0, grams < 3000, kcal < 4000 else { return nil }
            if grams <= 0 { grams = 150 }
            var lo = num(i["grams_low"]), hi = num(i["grams_high"])
            if lo <= 0 || lo > grams { lo = grams * 0.7 }
            if hi < grams { hi = grams * 1.35 }
            let search = ((i["search"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            return Item(name: name, search: search.isEmpty ? raw : search, grams: grams.rounded(),
                        gramsLow: lo.rounded(), gramsHigh: hi.rounded(),
                        cooking: (i["cooking"] as? String) ?? "", reference: (i["reference"] as? String) ?? "",
                        confidence: min(1, max(0, num(i["confidence"]))),
                        kcal: kcal, protein: num(i["protein"]), carbs: num(i["carbs"]), fat: num(i["fat"]))
        }
        return (out, json["notes"] as? String)
    }

    /// Older single-shape parser (kept so anything calling it still works).
    static func parse(_ text: String) throws -> [FoodGuess] {
        try parseDetailed(text).items.map(guess(from:))
    }
}
