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

    private static let prompt = """
    You are a nutrition estimator. Look at this meal photo and list every distinct food item you can see \
    (e.g. steak, roasted potatoes, asparagus as separate items). Estimate the visible portion of each and its \
    nutrition for that portion, using typical USDA values and accounting for cooking oil you can see. \
    Reply with ONLY this JSON, no other text:
    {"items":[{"name":"Sirloin steak","portion":"about 6 oz","grams":170,"kcal":340,"protein":50,"carbs":0,"fat":14,"confidence":0.8}]}
    Use short everyday names. If it isn't food, reply {"items":[]}.
    """

    /// Asks Claude what's on the plate. Throws on any failure so the caller can fall back to on-device.
    static func readPlate(_ image: UIImage) async throws -> [FoodGuess] {
        guard let key else { throw AIError.noKey }
        let small = FoodVision.prepared(image, maxSide: 1024)
        guard let jpeg = small.jpegData(compressionQuality: 0.6) else { throw AIError.badResponse }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 700,
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
        return try parse(text)
    }

    /// Pulls the JSON object out of the reply (tolerates ```json fences or extra words around it).
    static func parse(_ text: String) throws -> [FoodGuess] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { throw AIError.badResponse }
        func num(_ v: Any?) -> Double {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return Double(s.filter { "0123456789.".contains($0) }) ?? 0 }
            return 0
        }
        return items.compactMap { i in
            guard let name = (i["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            let kcal = num(i["kcal"])
            guard kcal > 0, kcal < 4000 else { return nil }
            var portion = (i["portion"] as? String) ?? ""
            let grams = num(i["grams"])
            if portion.isEmpty { portion = grams > 0 ? "\(Int(grams)) g" : "1 serving" }
            return FoodGuess(name: name.prefix(1).uppercased() + name.dropFirst(), serving: portion,
                             cal: kcal.rounded(), p: (num(i["protein"]) * 10).rounded() / 10,
                             c: (num(i["carbs"]) * 10).rounded() / 10, f: (num(i["fat"]) * 10).rounded() / 10,
                             source: .photo)
        }
    }
}
