// INTEGRATOR NOTE: the app's Info.plist needs a URL scheme so WHOOP can send the user back:
//   CFBundleURLTypes: [{ CFBundleURLName: com.troydunn.pulselab.whoop, CFBundleURLSchemes: [pulselab] }]
// The user registers their own (free) WHOOP developer app at developer-dashboard.whoop.com and adds
// the redirect URI below. Pulse Lab never talks to any server except WHOOP's.

import Foundation
import AuthenticationServices
import Security
import UIKit

/// OAuth 2.0 (authorization code) for the WHOOP Developer API.
/// Client ID/secret and tokens live only in this iPhone's Keychain and are never logged.
@MainActor
final class WhoopAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopAuth()

    static let redirectURI = "pulselab://whoop"
    static let callbackScheme = "pulselab"
    static let dashboardURL = URL(string: "https://developer-dashboard.whoop.com")!
    static let scopes = "offline read:recovery read:cycles read:sleep read:workout read:profile read:body_measurement"

    private static let authorizeURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!

    enum AuthError: LocalizedError {
        case missingCredentials, cancelled, stateMismatch, noCode, tokenFailed(String), notConnected

        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Paste your WHOOP Client ID and Client Secret first."
            case .cancelled: return "Sign-in was cancelled."
            case .stateMismatch: return "WHOOP sign-in check failed. Try again."
            case .noCode: return "WHOOP didn't send back a sign-in code. Check the redirect URI is pulselab://whoop."
            case .tokenFailed(let why): return "WHOOP sign-in failed: \(why)"
            case .notConnected: return "WHOOP isn't connected."
            }
        }
    }

    // MARK: credentials

    var clientID: String? {
        get { WhoopKeychain.get("clientID") }
        set { WhoopKeychain.set(newValue, for: "clientID") }
    }
    var clientSecret: String? {
        get { WhoopKeychain.get("clientSecret") }
        set { WhoopKeychain.set(newValue, for: "clientSecret") }
    }
    var hasCredentials: Bool { !(clientID ?? "").isEmpty && !(clientSecret ?? "").isEmpty }
    var isConnected: Bool { WhoopKeychain.get("refreshToken") != nil || WhoopKeychain.get("accessToken") != nil }

    private var session: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?

    // MARK: sign in

    func connect() async throws {
        guard let id = clientID, let secret = clientSecret, !id.isEmpty, !secret.isEmpty else { throw AuthError.missingCredentials }
        let state = Self.randomState()
        var comps = URLComponents(string: Self.authorizeURL)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = comps.url else { throw AuthError.missingCredentials }

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { cont.resume(returning: url); return }
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: AuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthError.noCode)
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start() { cont.resume(throwing: AuthError.cancelled) }
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value ?? err
            throw AuthError.tokenFailed(desc)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw AuthError.noCode }

        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": id,
            "client_secret": secret,
            "redirect_uri": Self.redirectURI,
        ])
    }

    func disconnect() {
        refreshTask?.cancel(); refreshTask = nil
        for k in ["accessToken", "refreshToken", "expiresAt"] { WhoopKeychain.set(nil, for: k) }
    }

    /// Forget everything, including the pasted Client ID / Secret.
    func forgetCredentials() {
        disconnect()
        clientID = nil
        clientSecret = nil
    }

    // MARK: tokens

    /// A valid access token, refreshing first if it expires within 2 minutes.
    func validAccessToken() async throws -> String {
        if let t = WhoopKeychain.get("accessToken"),
           let exp = WhoopKeychain.get("expiresAt").flatMap(Double.init),
           Date().timeIntervalSince1970 < exp - 120 {
            return t
        }
        return try await refresh()
    }

    /// Refresh (shared, so parallel requests don't each refresh).
    @discardableResult
    func refresh() async throws -> String {
        if let running = refreshTask { return try await running.value }
        let task = Task<String, Error> { @MainActor in
            defer { self.refreshTask = nil }
            guard let rt = WhoopKeychain.get("refreshToken") else { throw AuthError.notConnected }
            guard let id = self.clientID, let secret = self.clientSecret else { throw AuthError.missingCredentials }
            try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": rt,
                "client_id": id,
                "client_secret": secret,
                "scope": "offline",
            ])
            guard let t = WhoopKeychain.get("accessToken") else { throw AuthError.notConnected }
            return t
        }
        refreshTask = task
        return try await task.value
    }

    private func requestToken(_ form: [String: String]) async throws {
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            if code == 400 || code == 401, form["grant_type"] == "refresh_token" { disconnect() }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error_description"] as? String) ?? ($0["error"] as? String) } ?? "HTTP \(code)"
            throw AuthError.tokenFailed(msg)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        WhoopKeychain.set(t.access_token, for: "accessToken")
        if let r = t.refresh_token { WhoopKeychain.set(r, for: "refreshToken") }
        let exp = Date().timeIntervalSince1970 + (t.expires_in ?? 3600)
        WhoopKeychain.set(String(exp), for: "expiresAt")
    }

    // MARK: helpers

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
        }
    }
}

/// Keychain storage for WHOOP secrets (this device only, after first unlock).
enum WhoopKeychain {
    private static let service = "com.troydunn.pulselab.whoop"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
