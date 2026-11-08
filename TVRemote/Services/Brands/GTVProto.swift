import Foundation

// Small hand-written encoders/decoders for the Google TV remote protocol:
// protobuf (only what the polo / remotemessage protos need) and DER (just enough
// to build a self-signed X.509 certificate and read RSA public keys).

// MARK: - Protobuf

struct PBWriter {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    private mutating func key(_ field: Int, _ wire: Int) { varint(UInt64(field << 3 | wire)) }

    mutating func int(_ field: Int, _ value: Int) {
        key(field, 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func bool(_ field: Int, _ value: Bool) { int(field, value ? 1 : 0) }

    mutating func data(_ field: Int, _ value: [UInt8]) {
        key(field, 2)
        varint(UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ value: String) { data(field, Array(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout PBWriter) -> Void) {
        var sub = PBWriter()
        build(&sub)
        data(field, sub.bytes)
    }

    /// The message with its varint length prefix, ready for the wire.
    var framed: [UInt8] {
        var w = PBWriter()
        w.varint(UInt64(bytes.count))
        return w.bytes + bytes
    }
}

struct PBField {
    let number: Int
    let wire: Int
    /// Value for varint / fixed fields.
    let int: UInt64
    /// Payload for length-delimited fields.
    let data: [UInt8]

    var string: String { String(decoding: data, as: UTF8.self) }
    var message: PBMessage? { PBMessage(data) }
}

struct PBMessage {
    let fields: [PBField]

    init?(_ bytes: [UInt8]) {
        var out: [PBField] = []
        var i = 0
        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < bytes.count && shift < 64 {
                let b = bytes[i]; i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }
        while i < bytes.count {
            guard let k = readVarint() else { return nil }
            let number = Int(k >> 3), wire = Int(k & 7)
            switch wire {
            case 0:
                guard let v = readVarint() else { return nil }
                out.append(PBField(number: number, wire: 0, int: v, data: []))
            case 1:
                guard i + 8 <= bytes.count else { return nil }
                var v: UInt64 = 0
                for j in 0..<8 { v |= UInt64(bytes[i + j]) << (8 * UInt64(j)) }
                i += 8
                out.append(PBField(number: number, wire: 1, int: v, data: []))
            case 2:
                guard let len = readVarint(), len <= UInt64(bytes.count - i) else { return nil }
                let end = i + Int(len)
                out.append(PBField(number: number, wire: 2, int: 0, data: Array(bytes[i..<end])))
                i = end
            case 5:
                guard i + 4 <= bytes.count else { return nil }
                var v: UInt64 = 0
                for j in 0..<4 { v |= UInt64(bytes[i + j]) << (8 * UInt64(j)) }
                i += 4
                out.append(PBField(number: number, wire: 5, int: v, data: []))
            default:
                return nil
            }
        }
        fields = out
    }

    func field(_ n: Int) -> PBField? { fields.first { $0.number == n } }
    func message(_ n: Int) -> PBMessage? { field(n)?.message }
    func int(_ n: Int) -> Int? { field(n).map { Int(truncatingIfNeeded: $0.int) } }
    func string(_ n: Int) -> String? { field(n)?.string }
}

/// Splits a byte stream into varint-length-prefixed messages.
struct PBFramer {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) { buffer += data }

    /// Next complete message, or nil if more bytes are needed.
    mutating func next() -> [UInt8]? {
        var len: UInt64 = 0
        var shift: UInt64 = 0
        var i = 0
        while true {
            guard i < buffer.count, shift < 35 else { return nil }
            let b = buffer[i]; i += 1
            len |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
        }
        let total = i + Int(len)
        guard buffer.count >= total else { return nil }
        let msg = Array(buffer[i..<total])
        buffer.removeFirst(total)
        return msg
    }
}

// MARK: - DER

enum DER {
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var b: [UInt8] = []
        var v = n
        while v > 0 { b.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(b.count)] + b
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + length(content.count) + content }
    static func sequence(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func set(_ parts: [UInt8]...) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }
    static func explicit(_ n: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xA0 | n, content) }
    static let null: [UInt8] = [0x05, 0x00]

    /// Unsigned big-endian integer (adds a 0x00 pad when the top bit is set).
    static func integer(_ magnitude: [UInt8]) -> [UInt8] {
        var b = magnitude
        while b.count > 1 && b[0] == 0 { b.removeFirst() }
        if b.isEmpty { b = [0] }
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, b)
    }

    static func integer(_ v: Int) -> [UInt8] {
        var b: [UInt8] = []
        var x = v
        repeat { b.insert(UInt8(x & 0xFF), at: 0); x >>= 8 } while x > 0
        return integer(b)
    }

    static func oid(_ comps: [UInt]) -> [UInt8] {
        var out: [UInt8] = [UInt8(comps[0] * 40 + comps[1])]
        for c in comps.dropFirst(2) {
            var part: [UInt8] = [UInt8(c & 0x7F)]
            var v = c >> 7
            while v > 0 { part.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            out += part
        }
        return tlv(0x06, out)
    }

    static func bitString(_ content: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + content) }
    static func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }

    static func utcTime(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss"
        return tlv(0x17, Array((f.string(from: date) + "Z").utf8))
    }

    // MARK: Reading

    /// Reads one TLV at `offset`; returns the tag, content range and the offset after it.
    static func read(_ b: [UInt8], at offset: Int) -> (tag: UInt8, content: Range<Int>, next: Int)? {
        var i = offset
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]; i += 1
        var len = Int(b[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, i + n <= b.count else { return nil }
            len = 0
            for _ in 0..<n { len = len << 8 | Int(b[i]); i += 1 }
        }
        guard i + len <= b.count else { return nil }
        return (tag, i..<(i + len), i + len)
    }

    /// Modulus and exponent (minimal big-endian, no sign padding) from a PKCS#1 RSAPublicKey.
    static func rsaPublicKey(_ pkcs1: [UInt8]) -> (modulus: [UInt8], exponent: [UInt8])? {
        guard let seq = read(pkcs1, at: 0), seq.tag == 0x30,
              let n = read(pkcs1, at: seq.content.lowerBound), n.tag == 0x02,
              let e = read(pkcs1, at: n.next), e.tag == 0x02 else { return nil }
        func strip(_ r: Range<Int>) -> [UInt8] {
            var x = Array(pkcs1[r])
            while x.count > 1 && x[0] == 0 { x.removeFirst() }
            return x
        }
        return (strip(n.content), strip(e.content))
    }
}
