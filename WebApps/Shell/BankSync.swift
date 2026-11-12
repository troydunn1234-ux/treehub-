import Foundation
import Security
import UIKit

/// SimpleFIN Bridge bank sync, done on the phone (no server). Only turned on for apps whose
/// Info.plist sets WebShellBankSync = YES (Ride Quest). The Access URL holds the credentials,
/// so it lives in the Keychain and is never logged or handed to the page.
enum BankSync {
    static var enabled: Bool { ShellConfig.info["WebShellBankSync"] as? Bool ?? false }
    private static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    private static let service = "simplefin"
    private static let lastSyncKey = "simplefin.lastSync"
    private static let accountsKey = "simplefin.accounts"

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // MARK: Keychain

    private static func saveAccessURL(_ s: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "access"]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(s.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func accessURL() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "access", kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func disconnect() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "access"]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        UserDefaults.standard.removeObject(forKey: accountsKey)
    }

    // MARK: Actions

    static func claim(setupToken raw: String) async throws {
        if demo { _ = saveAccessURL("https://demo:demo@demo.invalid/simplefin"); return }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var b64 = token
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64), let s = String(data: d, encoding: .utf8),
              let claimURL = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), claimURL.scheme == "https" else {
            throw Failure.message("That doesn't look like a SimpleFIN setup token. Copy it again from SimpleFIN Bridge.")
        }
        var req = URLRequest(url: claimURL)
        req.httpMethod = "POST"
        req.httpBody = Data()
        req.setValue("0", forHTTPHeaderField: "Content-Length")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let access = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              access.hasPrefix("https://") else {
            throw Failure.message(code == 403 ? "This setup token was already used. Make a new one in SimpleFIN Bridge."
                                              : "SimpleFIN didn't accept the token (error \(code)).")
        }
        guard saveAccessURL(access) else { throw Failure.message("Couldn't save the connection on this phone.") }
    }

    static func status() -> [String: Any] {
        if demo && accessURL() == nil { _ = saveAccessURL("https://demo:demo@demo.invalid/simplefin") }
        let last = UserDefaults.standard.double(forKey: lastSyncKey)
        let accounts = (UserDefaults.standard.array(forKey: accountsKey) as? [[String: Any]]) ?? []
        return ["connected": accessURL() != nil, "lastSync": last > 0 ? last : NSNull(), "accounts": accounts]
    }

    /// Returns {accounts:[{id,name,org,balance,currency,transactions:[...]}], errors:[String]}
    static func sync(since: Double) async throws -> [String: Any] {
        guard let access = accessURL() else { throw Failure.message("Bank sync isn't connected.") }
        let result: [String: Any]
        if demo {
            result = demoData(since: since)
        } else {
            guard var comps = URLComponents(string: access) else { throw Failure.message("Saved connection is broken. Disconnect and connect again.") }
            let user = comps.percentEncodedUser.flatMap { $0.removingPercentEncoding } ?? ""
            let pass = comps.percentEncodedPassword.flatMap { $0.removingPercentEncoding } ?? ""
            comps.user = nil; comps.password = nil
            comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/accounts"
            let base = comps
            let start = String(Int(max(0, since)))
            let attempts: [[URLQueryItem]] = [
                [URLQueryItem(name: "start-date", value: start), URLQueryItem(name: "pending", value: "1")],
                [URLQueryItem(name: "start-date", value: start)],
                [URLQueryItem(name: "start-date", value: start), URLQueryItem(name: "end-date", value: String(Int(Date().timeIntervalSince1970)))],
                []
            ]
            var lastCode = 0, lastBody = ""
            var got: [String: Any]? = nil
            for q in attempts {
                var c = base
                c.queryItems = q.isEmpty ? nil : q
                guard let url = c.url else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 60
                req.setValue("Basic " + Data("\(user):\(pass)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                lastCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if lastCode == 403 { throw Failure.message("SimpleFIN says access was revoked. Disconnect and connect again.") }
                if lastCode == 402 { throw Failure.message("Your SimpleFIN Bridge subscription needs attention.") }
                if lastCode == 200, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { got = o; break }
                lastBody = String(decoding: data.prefix(160), as: UTF8.self)
                if lastCode != 400 { break }   // only 400s are worth retrying with simpler queries
            }
            guard let obj = got else {
                let why = lastBody.trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure.message("SimpleFIN error \(lastCode)" + (why.isEmpty ? ". Try again later." : ": \(why)"))
            }
            result = clean(obj)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        let summary = (result["accounts"] as? [[String: Any]] ?? []).map { a -> [String: Any] in
            ["id": a["id"] ?? "", "name": a["name"] ?? "", "org": a["org"] ?? "", "balance": a["balance"] ?? 0]
        }
        UserDefaults.standard.set(summary, forKey: accountsKey)
        return result
    }

    /// Keep only what the page needs, with numbers as numbers.
    private static func clean(_ obj: [String: Any]) -> [String: Any] {
        func num(_ v: Any?) -> Double { if let d = v as? Double { return d }; if let s = v as? String { return Double(s) ?? 0 }; if let i = v as? Int { return Double(i) }; return 0 }
        let accounts = (obj["accounts"] as? [[String: Any]] ?? []).map { a -> [String: Any] in
            let org = a["org"] as? [String: Any]
            let txs = (a["transactions"] as? [[String: Any]] ?? []).map { t -> [String: Any] in
                ["id": t["id"] as? String ?? "", "posted": num(t["posted"]), "transacted": num(t["transacted_at"]),
                 "amount": num(t["amount"]), "description": t["description"] as? String ?? "",
                 "payee": t["payee"] as? String ?? "", "memo": t["memo"] as? String ?? "",
                 "pending": (t["pending"] as? Bool) ?? (num(t["posted"]) == 0)]
            }
            return ["id": a["id"] as? String ?? "", "name": a["name"] as? String ?? "",
                    "org": (org?["name"] as? String) ?? (org?["domain"] as? String) ?? "",
                    "balance": num(a["balance"]), "available": (a["available-balance"] == nil ? NSNull() as Any : num(a["available-balance"]) as Any), "currency": a["currency"] as? String ?? "USD",
                    "balanceDate": num(a["balance-date"]), "transactions": txs]
        }
        let errors = (obj["errors"] as? [Any] ?? []).map { "\($0)" }
        return ["accounts": accounts, "errors": errors]
    }

    private static func demoData(since: Double) -> [String: Any] {
        let now = Date().timeIntervalSince1970, day = 86_400.0
        func tx(_ id: String, _ daysAgo: Double, _ amt: Double, _ desc: String) -> [String: Any] {
            ["id": id, "posted": now - daysAgo * day, "transacted": now - daysAgo * day, "amount": amt,
             "description": desc, "payee": desc, "memo": "", "pending": false]
        }
        return ["errors": [], "accounts": [
            ["id": "demo-chk", "name": "SoFi Checking", "org": "SoFi", "balance": 1842.17, "currency": "USD", "transactions": [
                tx("d1", 1, -54.12, "CHEVRON 0098"), tx("d2", 2, -18.40, "CHIPOTLE 1123"), tx("d3", 3, 1450.00, "PAYROLL DEPOSIT"),
                tx("d4", 4, -39.99, "AUTOZONE #3321"), tx("d5", 6, -82.31, "SAFEWAY 1460")]],
            ["id": "demo-sav", "name": "SoFi Savings", "org": "SoFi", "balance": 8120.55, "currency": "USD", "transactions": []],
            ["id": "demo-dsc", "name": "Discover it Card", "org": "Discover", "balance": -212.40, "currency": "USD", "transactions": [
                tx("d6", 2, -15.99, "SPOTIFY USA"), tx("d7", 5, -156.00, "GEICO AUTO INSURANCE")]]]]
    }

    static func pasteboardText() -> String { UIPasteboard.general.string ?? "" }
}

extension Bridge {
    /// Handles {op:'simplefin', action:...} and {op:'pasteboard'} from the page.
    func handleBank(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        guard BankSync.enabled else { reply(nil, "not available"); return }
        if body["op"] as? String == "pasteboard" { reply(BankSync.pasteboardText(), nil); return }
        let action = body["action"] as? String ?? ""
        Task {
            do {
                switch action {
                case "claim":
                    try await BankSync.claim(setupToken: body["token"] as? String ?? "")
                    await MainActor.run { reply(BankSync.status(), nil) }
                case "status":
                    let s = BankSync.status()
                    await MainActor.run { reply(s, nil) }
                case "sync":
                    let since = (body["since"] as? Double) ?? Double(body["since"] as? Int ?? 0)
                    let r = try await BankSync.sync(since: since)
                    await MainActor.run { reply(r, nil) }
                case "disconnect":
                    BankSync.disconnect()
                    await MainActor.run { reply(true, nil) }
                default:
                    await MainActor.run { reply(nil, "unknown action") }
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "Network problem. Try again."
                await MainActor.run { reply(nil, msg) }
            }
        }
    }
}
