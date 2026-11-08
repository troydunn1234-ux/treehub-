import Foundation
import Network

/// Looks for every supported TV brand on your Wi-Fi at once: each brand's controller
/// streams what it finds, and this merges them into one list.
@MainActor
@Observable
final class TVDiscovery {
    private(set) var found: [DiscoveredTV] = []
    private(set) var searching = false
    private(set) var progress: Double = 0

    private let controllers: [TVController]
    private var tasks: [Task<Void, Never>] = []
    private var ticker: Task<Void, Never>?
    private var remaining = 0

    /// About how long a full search takes; drives the progress bar.
    private static let expected: Double = 9

    init(controllers: [TVController]) { self.controllers = controllers }

    func start() {
        guard !searching else { return }
        searching = true
        progress = 0
        found = []
        remaining = controllers.count
        for c in controllers {
            let stream = c.discover()
            tasks.append(Task { [weak self] in
                for await tv in stream {
                    guard let self, self.searching else { break }
                    self.add(tv)
                }
                guard let self, self.searching else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.finish() }
            })
        }
        let started = Date()
        ticker = Task { [weak self] in
            while let self, self.searching, !Task.isCancelled {
                self.progress = min(0.97, Date().timeIntervalSince(started) / Self.expected)
                if Date().timeIntervalSince(started) > 20 { self.finish(); break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        ticker?.cancel(); ticker = nil
        searching = false
    }

    private func finish() {
        stop()
        progress = 1
    }

    private func add(_ tv: DiscoveredTV) {
        // One entry per physical TV: the same host can't be two brands, but a Roku TV made by
        // TCL may answer on more than one protocol; keep the first.
        guard !found.contains(where: { $0.host == tv.host || ($0.brand == tv.brand && $0.serial != nil && $0.serial == tv.serial) }) else { return }
        found.append(tv)
    }

    /// Try one address the user typed against every brand; first match wins.
    func probe(host: String) async -> DiscoveredTV? {
        await withTaskGroup(of: DiscoveredTV?.self) { group in
            for c in controllers { group.addTask { await c.probe(host: host) } }
            for await r in group { if let r { group.cancelAll(); return r } }
            return nil
        }
    }

    /// "192.168.1" for a phone at 192.168.1.23 on Wi-Fi.
    nonisolated static func wifiPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var result: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" || (result == nil && name.hasPrefix("en")) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                let parts = ip.split(separator: ".")
                if parts.count == 4 && VizioClient.isPrivate(ip) {
                    result = parts.prefix(3).joined(separator: ".")
                    if name == "en0" { break }
                }
            }
        }
        return result
    }
}
