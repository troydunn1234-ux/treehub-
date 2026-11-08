import Foundation
import Security
import CryptoKit

/// The phone's client certificate for Google TV / Android TV. Generated once (RSA-2048,
/// self-signed, like the official remote apps do) and kept in the Keychain on this device only.
enum GTVIdentity {
    private static let keyTag = Data("com.troydunn.couchremote.gtv.key".utf8)
    private static let certLabel = "Couch Remote Google TV"
    private static let lock = NSLock()

    enum Failure: Error { case keyGeneration, signing, certificate, identity }

    /// The identity used for TLS on both the pairing (6467) and remote (6466) ports.
    static func identity() throws -> SecIdentity {
        lock.lock(); defer { lock.unlock() }
        let key = try privateKey()
        let cert = try certificate(for: key)
        if let id = findIdentity(matching: cert) { return id }
        // The cert may have been stored for an older key; replace it.
        deleteCertificate()
        let fresh = try makeCertificate(key: key)
        try store(fresh)
        guard let id = findIdentity(matching: fresh) else { throw Failure.identity }
        return id
    }

    /// Our certificate's RSA public key (minimal big-endian modulus / exponent).
    static func publicKeyComponents() throws -> (modulus: [UInt8], exponent: [UInt8]) {
        lock.lock()
        let keyResult = Result { try privateKey() }
        lock.unlock()
        let key = try keyResult.get()
        guard let pub = SecKeyCopyPublicKey(key) else { throw Failure.keyGeneration }
        return try components(of: pub)
    }

    static func components(of publicKey: SecKey) throws -> (modulus: [UInt8], exponent: [UInt8]) {
        var err: Unmanaged<CFError>?
        guard let ext = SecKeyCopyExternalRepresentation(publicKey, &err) as Data?,
              let parts = DER.rsaPublicKey(Array(ext)) else { throw Failure.keyGeneration }
        return parts
    }

    /// RSA public key of a certificate the TV presented.
    static func components(of certificate: SecCertificate) throws -> (modulus: [UInt8], exponent: [UInt8]) {
        guard let key = SecCertificateCopyKey(certificate) else { throw Failure.certificate }
        return try components(of: key)
    }

    // MARK: Key

    private static func privateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true,
        ]
        var ref: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let r = ref {
            return r as! SecKey  // swiftlint:disable:this force_cast
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: certLabel,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [String: Any],
        ]
        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else { throw Failure.keyGeneration }
        return key
    }

    // MARK: Certificate

    private static func certificate(for key: SecKey) throws -> SecCertificate {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel,
            kSecReturnRef as String: true,
        ]
        var ref: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let r = ref {
            return r as! SecCertificate  // swiftlint:disable:this force_cast
        }
        let cert = try makeCertificate(key: key)
        try store(cert)
        return cert
    }

    private static func store(_ cert: SecCertificate) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: certLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.certificate }
    }

    private static func deleteCertificate() {
        let q: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: certLabel]
        SecItemDelete(q as CFDictionary)
    }

    private static func findIdentity(matching cert: SecCertificate) -> SecIdentity? {
        let want = SecCertificateCopyData(cert) as Data
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let list = ref as? [SecIdentity] else { return nil }
        for id in list {
            var c: SecCertificate?
            if SecIdentityCopyCertificate(id, &c) == errSecSuccess, let c,
               SecCertificateCopyData(c) as Data == want { return id }
        }
        return nil
    }

    /// Self-signed X.509 v3 certificate, sha256WithRSAEncryption, CN=atvremote.
    private static func makeCertificate(key: SecKey) throws -> SecCertificate {
        guard let pub = SecKeyCopyPublicKey(key) else { throw Failure.keyGeneration }
        var err: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(pub, &err) as Data? else { throw Failure.keyGeneration }

        let rsaEncryption = DER.sequence(DER.oid([1, 2, 840, 113549, 1, 1, 1]), DER.null)
        let sha256WithRSA = DER.sequence(DER.oid([1, 2, 840, 113549, 1, 1, 11]), DER.null)
        let spki = DER.sequence(rsaEncryption, DER.bitString(Array(pkcs1)))
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([2, 5, 4, 3]), DER.utf8("atvremote"))))

        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F
        if serial[0] == 0 { serial[0] = 1 }

        let now = Date()
        let notBefore = now.addingTimeInterval(-86_400)
        // UTCTime only goes to 2049; stay well inside it.
        let notAfter = min(now.addingTimeInterval(20 * 365 * 86_400),
                           Date(timeIntervalSince1970: 2_524_000_000))  // ~2049-12
        let validity = DER.sequence(DER.utcTime(notBefore), DER.utcTime(notAfter))

        let tbs = DER.sequence(
            DER.explicit(0, DER.integer(2)),
            DER.integer(serial),
            sha256WithRSA,
            name,
            validity,
            name,
            spki
        )
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(tbs) as CFData, &err) as Data? else {
            throw Failure.signing
        }
        let der = DER.sequence(tbs, sha256WithRSA, DER.bitString(Array(sig)))
        guard let cert = SecCertificateCreateWithData(nil, Data(der) as CFData) else { throw Failure.certificate }
        return cert
    }

    static func fingerprint(_ cert: SecCertificate) -> String {
        SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
    }
}
