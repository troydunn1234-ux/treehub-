import Foundation
import Network
import Security
import CryptoKit

/// One TLS connection to a Google TV (pairing port 6467 or remote port 6466), carrying
/// varint-length-prefixed protobuf messages. All mutable state lives on `queue`.
final class GTVLink: @unchecked Sendable {
    let queue: DispatchQueue
    private let conn: NWConnection
    private var framer = PBFramer()
    private var inbox: [[UInt8]] = []
    private var waiter: (id: Int, cont: CheckedContinuation<[UInt8], Error>)?
    private var waiterSeq = 0
    private var closedError: Error?
    private var started = false

    /// When set, every incoming message goes here (on `queue`) instead of the inbox.
    var onMessage: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?

    /// Certificate the TV presented (set during the TLS handshake).
    private(set) var peerCertificate: SecCertificate?

    var isOpen: Bool { queue.sync { started && closedError == nil } }

    /// - Parameter pinnedFingerprint: SHA-256 hex of the TV certificate seen at pairing. When set,
    ///   any other certificate is refused. When nil, any certificate is accepted (pairing).
    init(host: String, port: Int, identity: SecIdentity, pinnedFingerprint: String?, label: String) {
        let q = DispatchQueue(label: "gtv.link.\(label)")
        queue = q
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        if let sid = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, sid)
        }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        let holder = CertHolder()
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                  let leaf = chain.first else { complete(false); return }
            holder.cert = leaf
            if let pin = pinnedFingerprint, GTVIdentity.fingerprint(leaf) != pin {
                complete(false)
                return
            }
            complete(true)
        }, q)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 15
        tcp.connectionTimeout = 3
        tcp.noDelay = true
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = false
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 6466, using: params)
        certHolder = holder
    }

    private let certHolder: CertHolder
    private final class CertHolder: @unchecked Sendable { var cert: SecCertificate? }

    /// Connects and waits for the TLS handshake.
    func start(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            func finish(_ error: Error?) {
                guard !resumed else { return }
                resumed = true
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.started = true
                    self.peerCertificate = self.certHolder.cert
                    self.receive()
                    finish(nil)
                case .failed(let e):
                    self.fail(e)
                    finish(TVControlError.unreachable)
                case .waiting:
                    // No route / refused: treat as unreachable rather than waiting forever.
                    self.conn.cancel()
                    finish(TVControlError.unreachable)
                case .cancelled:
                    self.fail(nil)
                    finish(TVControlError.unreachable)
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard !resumed else { return }
                self?.conn.cancel()
                finish(TVControlError.unreachable)
            }
        }
    }

    func close() {
        conn.cancel()
    }

    // MARK: Sending

    func send(_ message: PBWriter) async throws {
        let bytes = Data(message.framed)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: bytes, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    // MARK: Receiving

    /// Next message from the inbox (only used while `onMessage` is nil).
    func next(timeout: TimeInterval) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            queue.async { [self] in
                if !inbox.isEmpty { cont.resume(returning: inbox.removeFirst()); return }
                if closedError != nil {
                    cont.resume(throwing: TVControlError.unreachable); return
                }
                waiterSeq += 1
                let id = waiterSeq
                waiter = (id, cont)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self, let w = self.waiter, w.id == id else { return }
                    self.waiter = nil
                    w.cont.resume(throwing: TVControlError.pairingTimedOut)
                }
            }
        }
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.framer.append(data)
                while let msg = self.framer.next() { self.deliver(msg) }
            }
            if let error { self.fail(error); self.conn.cancel(); return }
            if isComplete { self.fail(nil); self.conn.cancel(); return }
            self.receive()
        }
    }

    private func deliver(_ msg: [UInt8]) {
        if let handler = onMessage { handler(msg); return }
        if let w = waiter {
            waiter = nil
            w.cont.resume(returning: msg)
        } else {
            inbox.append(msg)
        }
    }

    private func fail(_ error: Error?) {
        guard closedError == nil else { return }
        closedError = error ?? TVControlError.unreachable
        if let w = waiter {
            waiter = nil
            w.cont.resume(throwing: TVControlError.unreachable)
        }
        onClose?()
    }
}
