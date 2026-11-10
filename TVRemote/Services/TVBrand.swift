import Foundation

/// Every TV brand Couch Remote can drive. Each brand has its own controller
/// (VizioController, RokuController, SamsungController, LGController, GoogleTVController)
/// that speaks that TV's local-network protocol. Nothing goes through a server.
enum TVBrand: String, Codable, CaseIterable, Identifiable {
    case vizio, roku, samsung, lg, googleTV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vizio: return "VIZIO SmartCast"
        case .roku: return "Roku"
        case .samsung: return "Samsung"
        case .lg: return "LG webOS"
        case .googleTV: return "Google TV / Android TV"
        }
    }

    /// How the user approves the phone the first time.
    var pairing: TVPairingStyle {
        switch self {
        case .vizio, .googleTV: return .pinOnTV
        case .samsung, .lg: return .allowPromptOnTV
        case .roku: return .none
        }
    }
}

enum TVPairingStyle { case none, pinOnTV, allowPromptOnTV }

/// Brand-neutral remote keys. Controllers map these to their own codes and ignore
/// keys their TV doesn't have (return without throwing).
enum RemoteKey: String, CaseIterable, Codable {
    case up, down, left, right, ok, back, home, menu, info, exit
    case play, pause, playPause, seekForward, seekBack
    case volumeUp, volumeDown, muteToggle, powerToggle, powerOn, powerOff, inputNext, ccToggle
}

/// A TV found on the network or saved after pairing.
struct DiscoveredTV: Codable, Hashable, Identifiable {
    var brand: TVBrand
    var host: String
    var port: Int
    var name: String
    var model: String
    /// Stable hardware id when the TV reports one (serial, MAC, UDN). Used to re-find a TV after its IP changes.
    var serial: String?
    var id: String { "\(brand.rawValue).\(serial ?? host)" }
}

/// What a controller can say about the TV right now.
struct TVNowPlaying: Equatable { var appName: String?; var appID: String? }

/// One brand's protocol. Implementations must be safe to call from any task and must time out
/// quickly (≤ 2 s) when the TV is unreachable. Credentials (tokens, client keys, certificates)
/// are stored by the controller itself in the Keychain under keys prefixed "tv.<brand>.<serial or host>".
protocol TVController: AnyObject, Sendable {
    var brand: TVBrand { get }

    /// Find this brand's TVs on the local network (SSDP, mDNS or a subnet probe), streaming results.
    /// Should finish within ~8 s.
    func discover() -> AsyncStream<DiscoveredTV>

    /// Probe one IP the user typed. Returns nil if it isn't this brand.
    func probe(host: String) async -> DiscoveredTV?

    /// Begin pairing. For .pinOnTV the TV now shows a code; for .allowPromptOnTV the TV shows
    /// "Allow?" and this call may wait (up to ~30 s) until the user accepts, then completes pairing.
    /// For .none it just verifies reachability.
    func beginPairing(_ tv: DiscoveredTV, phoneName: String) async throws
    /// Only for .pinOnTV brands.
    func finishPairing(_ tv: DiscoveredTV, pin: String) async throws
    func cancelPairing(_ tv: DiscoveredTV) async
    func isPaired(_ tv: DiscoveredTV) -> Bool
    func forget(_ tv: DiscoveredTV)

    func press(_ tv: DiscoveredTV, _ key: RemoteKey) async throws
    /// Launch a streaming app by its catalog name (e.g. "Netflix"). Controllers keep their own
    /// name → app-id table and throw TVControlError.appUnavailable if unknown on this TV.
    func launch(_ tv: DiscoveredTV, appName: String) async throws
    /// App names this TV can launch (installed list when the TV reports it, else the controller's known table).
    func availableApps(_ tv: DiscoveredTV) async -> [String]
    func nowPlaying(_ tv: DiscoveredTV) async -> TVNowPlaying?
    /// Optional: type text into the focused field (search boxes). Throw .unsupported if not possible.
    /// In `.append` mode this inserts `text` at the cursor; in `.replace` mode `text` is the whole field.
    func sendText(_ tv: DiscoveredTV, _ text: String) async throws

    // Phone keyboard ("Type on TV"). All have defaults below, so brands opt in.
    /// How this TV takes typing from the phone.
    var textMode: TVTextMode { get }
    /// Delete `count` characters before the cursor (only used in `.append` mode).
    func backspace(_ tv: DiscoveredTV, count: Int) async throws
    /// Submit the text field (the keyboard's Return key).
    func submitText(_ tv: DiscoveredTV) async throws
    /// Open the TV's own search screen. Throws .unsupported where there's no reliable way.
    func openSearch(_ tv: DiscoveredTV) async throws
    /// true when a text field on the TV gets focus (its on-screen keyboard opens), false when it closes.
    /// Brands that can't tell return a stream that finishes immediately.
    func keyboardEvents(_ tv: DiscoveredTV) -> AsyncStream<Bool>
}

/// How a TV accepts typed text.
enum TVTextMode {
    /// Send only what's new (sendText inserts), deletions via backspace.
    case append
    /// Send the whole field every time (sendText replaces what's there).
    case replace
    /// The TV can't take typing from a phone.
    case none
}

extension TVController {
    var textMode: TVTextMode { .append }
    /// The TV was found again at a new address. Carry pairing credentials over so the
    /// user does not have to pair twice. Default: nothing to move.
    func didMove(from old: DiscoveredTV, to new: DiscoveredTV) async {}
    func backspace(_ tv: DiscoveredTV, count: Int) async throws { throw TVControlError.unsupported }
    func submitText(_ tv: DiscoveredTV) async throws { try await press(tv, .ok) }
    func openSearch(_ tv: DiscoveredTV) async throws { throw TVControlError.unsupported }
    func keyboardEvents(_ tv: DiscoveredTV) -> AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

enum TVControlError: LocalizedError {
    case unreachable, notPaired, pairingRejected, pairingTimedOut, badPIN, appUnavailable, unsupported
    case other(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: return "Can't reach the TV. Is it on and on the same Wi-Fi?"
        case .notPaired: return "This TV needs to be paired again."
        case .pairingRejected: return "The TV said no. Try again and choose Allow on the TV."
        case .pairingTimedOut: return "No answer from the TV. Choose Allow on the TV screen when it asks."
        case .badPIN: return "That code didn't match. Try the new code on your TV."
        case .appUnavailable: return "That app isn't available on this TV."
        case .unsupported: return "This TV doesn't support that."
        case .other(let s): return s
        }
    }
}
