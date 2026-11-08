import Foundation
import Security

/// Talks to a Vizio SmartCast TV on your Wi-Fi (HTTPS on port 7345, or 9000 on older sets).
/// The TV uses a self-signed certificate, so we trust exactly the certificate it showed
/// the first time (stored per TV) and nothing else.
final class VizioClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    struct TVInfo: Codable, Equatable, Hashable {
        var host: String
        var port: Int
        var name: String
        var model: String
    }

    struct AppConfig: Codable, Hashable {
        var APP_ID: String
        var NAME_SPACE: Int
        var MESSAGE: String?
    }

    enum Key: CaseIterable {
        case up, down, left, right, ok, back, home, menu, info, exit
        case play, pause, seekForward, seekBack
        case volumeUp, volumeDown, muteToggle, powerToggle, powerOn, powerOff, inputNext, ccToggle

        var codes: (Int, Int) {
            switch self {
            case .up: return (3, 8)
            case .down: return (3, 0)
            case .left: return (3, 1)
            case .right: return (3, 7)
            case .ok: return (3, 2)
            case .back: return (4, 0)
            case .home: return (4, 15)
            case .menu: return (4, 8)
            case .info: return (4, 6)
            case .exit: return (9, 0)
            case .play: return (2, 3)
            case .pause: return (2, 2)
            case .seekForward: return (2, 0)
            case .seekBack: return (2, 1)
            case .volumeUp: return (5, 1)
            case .volumeDown: return (5, 0)
            case .muteToggle: return (5, 4)
            case .powerToggle: return (11, 2)
            case .powerOn: return (11, 1)
            case .powerOff: return (11, 0)
            case .inputNext: return (7, 1)
            case .ccToggle: return (4, 4)
            }
        }
    }

    enum VizioError: LocalizedError {
        case unreachable, notPaired, rejected(String), badResponse
        var errorDescription: String? {
            switch self {
            case .unreachable: return "Can't reach the TV. Make sure it's on and on the same Wi-Fi."
            case .notPaired: return "The TV doesn't recognize this phone anymore. Pair again."
            case .rejected(let r): return "The TV said: \(r.replacingOccurrences(of: "_", with: " ").lowercased())."
            case .badResponse: return "The TV sent back something unexpected."
            }
        }
    }

    static let deviceID = "clicker-ios"

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    // MARK: Trust on first use

    private static func pinKey(_ host: String) -> String { "vizioCertPin.\(host)" }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let host = challenge.protectionSpace.host
        // Only ever relax checks for private-network addresses.
        guard Self.isPrivate(host) else { completionHandler(.performDefaultHandling, nil); return }
        let der = SecCertificateCopyData(leaf) as Data
        let key = Self.pinKey(host)
        if let pinned = UserDefaults.standard.data(forKey: key), pinned != der {
            // A different certificate than before at this address: refuse.
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func pinCertificate(for host: String, port: Int) async {
        // Called after a successful pairing: remember the certificate this TV presented.
        guard UserDefaults.standard.data(forKey: Self.pinKey(host)) == nil else { return }
        let grabber = CertGrabber()
        if let der = await grabber.fetch(host: host, port: port) {
            UserDefaults.standard.set(der, forKey: Self.pinKey(host))
        }
    }

    static func forgetPin(host: String) { UserDefaults.standard.removeObject(forKey: pinKey(host)) }

    static func isPrivate(_ host: String) -> Bool {
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return host.hasSuffix(".local") }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254)
    }

    // MARK: Requests

    private func request(_ method: String, host: String, port: Int, path: String,
                         body: [String: Any]? = nil, auth: String? = nil, timeout: TimeInterval = 4) async throws -> [String: Any] {
        guard let url = URL(string: "https://\(host):\(port)\(path)") else { throw VizioError.badResponse }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth { req.setValue(auth, forHTTPHeaderField: "AUTH") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw VizioError.unreachable }
        if (resp as? HTTPURLResponse)?.statusCode == 403 { throw VizioError.notPaired }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw VizioError.badResponse }
        if let status = obj["STATUS"] as? [String: Any], let result = status["RESULT"] as? String {
            switch result.uppercased() {
            case "SUCCESS": break
            case "URI_NOT_FOUND", "UNAUTHORIZED", "INVALID_AUTH", "NOT_AUTHORIZED": throw VizioError.notPaired
            default: throw VizioError.rejected(result)
            }
        }
        return obj
    }

    /// Unauthenticated: is there a Vizio TV here? Returns its name and model.
    func probe(host: String, port: Int, timeout: TimeInterval = 1.6) async -> TVInfo? {
        guard let obj = try? await request("GET", host: host, port: port, path: "/state/device/deviceinfo", timeout: timeout) else { return nil }
        let items = obj["ITEMS"] as? [[String: Any]]
        let value = items?.first?["VALUE"] as? [String: Any]
        let model = value?["MODEL_NAME"] as? String ?? "Vizio TV"
        var name = (value?["SETTINGS"] as? [String: Any])?["NAME"] as? String
            ?? value?["NAME"] as? String ?? ""
        if name.isEmpty { name = model }
        return TVInfo(host: host, port: port, name: name, model: model)
    }

    /// Step 1: the TV shows a 4-digit code.
    func startPairing(_ tv: TVInfo, deviceName: String) async throws -> (token: Int, challenge: Int) {
        let obj = try await request("PUT", host: tv.host, port: tv.port, path: "/pairing/start",
                                    body: ["DEVICE_ID": Self.deviceID, "DEVICE_NAME": deviceName], timeout: 8)
        guard let item = obj["ITEM"] as? [String: Any],
              let token = item["PAIRING_REQ_TOKEN"] as? Int else { throw VizioError.badResponse }
        return (token, item["CHALLENGE_TYPE"] as? Int ?? 1)
    }

    /// Step 2: send the code back; get a long-lived auth token.
    func finishPairing(_ tv: TVInfo, pin: String, token: Int, challenge: Int) async throws -> String {
        let obj = try await request("PUT", host: tv.host, port: tv.port, path: "/pairing/pair",
                                    body: ["DEVICE_ID": Self.deviceID, "CHALLENGE_TYPE": challenge,
                                           "RESPONSE_VALUE": pin, "PAIRING_REQ_TOKEN": token], timeout: 8)
        guard let item = obj["ITEM"] as? [String: Any], let auth = item["AUTH_TOKEN"] as? String else { throw VizioError.badResponse }
        return auth
    }

    func cancelPairing(_ tv: TVInfo, token: Int, challenge: Int) async {
        _ = try? await request("PUT", host: tv.host, port: tv.port, path: "/pairing/cancel",
                               body: ["DEVICE_ID": Self.deviceID, "CHALLENGE_TYPE": challenge,
                                      "RESPONSE_VALUE": "1111", "PAIRING_REQ_TOKEN": token])
    }

    func launch(_ tv: TVInfo, auth: String, app: AppConfig) async throws {
        var value: [String: Any] = ["NAME_SPACE": app.NAME_SPACE, "APP_ID": app.APP_ID]
        value["MESSAGE"] = app.MESSAGE ?? NSNull()
        _ = try await request("PUT", host: tv.host, port: tv.port, path: "/app/launch", body: ["VALUE": value], auth: auth, timeout: 8)
    }

    func press(_ tv: TVInfo, auth: String, _ key: Key) async throws {
        let (set, code) = key.codes
        _ = try await request("PUT", host: tv.host, port: tv.port, path: "/key_command/",
                              body: ["KEYLIST": [["CODESET": set, "CODE": code, "ACTION": "KEYPRESS"]]], auth: auth)
    }

    /// The app on screen right now, or nil for the home screen / a TV input.
    func currentApp(_ tv: TVInfo, auth: String) async throws -> AppConfig? {
        let obj = try await request("GET", host: tv.host, port: tv.port, path: "/app/current", auth: auth)
        guard let item = obj["ITEM"] as? [String: Any], let v = item["VALUE"] as? [String: Any] else { return nil }
        let ns = v["NAME_SPACE"] as? Int ?? -1
        let id: String
        if let s = v["APP_ID"] as? String { id = s } else if let n = v["APP_ID"] as? Int { id = String(n) } else { return nil }
        if ns < 0 || id.isEmpty { return nil }
        return AppConfig(APP_ID: id, NAME_SPACE: ns, MESSAGE: v["MESSAGE"] as? String)
    }

    /// Is the screen on? (The API answers in standby too when Quick Start is enabled.)
    func powerState(_ tv: TVInfo, auth: String) async -> Bool? {
        guard let obj = try? await request("GET", host: tv.host, port: tv.port, path: "/state/device/power_mode", auth: auth),
              let items = obj["ITEMS"] as? [[String: Any]], let v = items.first?["VALUE"] as? Int else { return nil }
        return v == 1
    }
}

/// Grabs the TV's certificate once, accepting it, so it can be pinned.
private final class CertGrabber: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var der: Data?
    func fetch(host: String, port: Int) async -> Data? {
        guard VizioClient.isPrivate(host), let url = URL(string: "https://\(host):\(port)/state/device/deviceinfo") else { return nil }
        let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { s.finishTasksAndInvalidate() }
        _ = try? await s.data(from: url)
        return der
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first {
            der = SecCertificateCopyData(leaf) as Data
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
