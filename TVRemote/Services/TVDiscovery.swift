import Foundation
import Network

/// Finds Vizio TVs on your Wi-Fi: first by asking the network who advertises the
/// SmartCast service, then by checking every address on your Wi-Fi for a TV.
@MainActor
@Observable
final class TVDiscovery {
    private(set) var found: [VizioClient.TVInfo] = []
    private(set) var searching = false
    private(set) var progress: Double = 0

    private let client: VizioClient
    private var browser: NWBrowser?

    init(client: VizioClient) { self.client = client }

    func start() {
        guard !searching else { return }
        searching = true
        progress = 0
        found = []
        startBonjour()
        Task { await scanSubnet() }
    }

    func stop() {
        browser?.cancel(); browser = nil
        searching = false
    }

    private func add(_ tv: VizioClient.TVInfo) {
        guard !found.contains(where: { $0.host == tv.host }) else { return }
        found.append(tv)
    }

    // MARK: Bonjour

    private func startBonjour() {
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: "_viziocast._tcp", domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                Task { @MainActor in self?.resolve(r.endpoint) }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    private func resolve(_ endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                    var h = "\(host)"
                    if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
                    let p = Int(port.rawValue)
                    conn.cancel()
                    Task { @MainActor in
                        guard let self else { return }
                        if let tv = await self.client.probe(host: h, port: p == 0 ? 7345 : p, timeout: 3) { self.add(tv) }
                    }
                } else { conn.cancel() }
            case .failed, .cancelled: break
            default: break
            }
        }
        conn.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { conn.cancel() }
    }

    // MARK: Subnet scan

    private func scanSubnet() async {
        defer { searching = false; progress = 1 }
        guard let prefix = Self.wifiPrefix() else { return }
        let hosts = (1...254).map { "\(prefix).\($0)" }
        let client = self.client
        var done = 0
        await withTaskGroup(of: VizioClient.TVInfo?.self) { group in
            var it = hosts.makeIterator()
            func next() -> Bool {
                guard let h = it.next() else { return false }
                group.addTask {
                    if let tv = await client.probe(host: h, port: 7345) { return tv }
                    return await client.probe(host: h, port: 9000, timeout: 1.0)
                }
                return true
            }
            for _ in 0..<40 { if !next() { break } }
            while let r = await group.next() {
                done += 1
                progress = Double(done) / Double(hosts.count)
                if let r { add(r) }
                _ = next()
            }
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
