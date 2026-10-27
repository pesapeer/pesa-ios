import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security) && !os(Linux)
import Security
#endif

/// SPKI pinning: the SHA-256 of the server certificate's
/// SubjectPublicKeyInfo, base64 — the same value Android's network security
/// config, the Flutter plugin and HPKP use
/// (`openssl x509 -pubkey -noout | openssl pkey -pubin -outform der |
/// openssl dgst -sha256 -binary | base64`).
///
/// The pin is checked while the TLS handshake is being evaluated, before a
/// request byte is written, so a card number is never sent to a host that
/// does not hold Pesa's key. Chain validation against the system roots
/// still happens first; pinning narrows it, never replaces it.
public enum SpkiPin {
    /// The pin of a DER-encoded certificate.
    public static func of(certificateDER der: Data) throws -> String {
        let spki = try subjectPublicKeyInfo(der)
        return Data(SHA256.hash(spki)).base64EncodedString()
    }

    /// Whether the certificate's key is one of `pins`.
    public static func matches(certificateDER der: Data, pins: [String]) -> Bool {
        guard let pin = try? of(certificateDER: der) else { return false }
        return pins.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == pin }
    }

    /// Lifts the DER-encoded SubjectPublicKeyInfo out of a DER certificate.
    ///
    /// Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version?,
    /// serialNumber, signature, issuer, validity, subject,
    /// subjectPublicKeyInfo, … }, … }.
    public static func subjectPublicKeyInfo(_ der: Data) throws -> [UInt8] {
        var cert = DER(Array(der))
        var tbs = DER(try cert.sequence())
        var r = DER(try tbs.sequence())
        if r.peekTag() == 0xa0 { try r.skip() }
        try r.skip() // serialNumber
        try r.skip() // signature
        try r.skip() // issuer
        try r.skip() // validity
        try r.skip() // subject
        return try r.element()
    }

    public struct FormatError: Error, Equatable { public let reason: String }
}

/// The smallest DER reader that can walk a certificate: tag, length, value.
struct DER {
    private let bytes: [UInt8]
    private var pos = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func peekTag() -> UInt8 { pos < bytes.count ? bytes[pos] : 0 }

    mutating func sequence() throws -> [UInt8] {
        guard peekTag() == 0x30 else { throw SpkiPin.FormatError(reason: "expected SEQUENCE") }
        return try contents()
    }

    /// The next whole element, header included.
    mutating func element() throws -> [UInt8] {
        let start = pos
        _ = try contents()
        return Array(bytes[start..<pos])
    }

    mutating func skip() throws { _ = try contents() }

    mutating func contents() throws -> [UInt8] {
        guard pos + 2 <= bytes.count else { throw SpkiPin.FormatError(reason: "truncated") }
        pos += 1
        var len = Int(bytes[pos]); pos += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n > 0, n <= 4, pos + n <= bytes.count else { throw SpkiPin.FormatError(reason: "bad DER length") }
            len = 0
            for _ in 0..<n { len = len << 8 | Int(bytes[pos]); pos += 1 }
        }
        guard pos + len <= bytes.count else { throw SpkiPin.FormatError(reason: "truncated") }
        let out = Array(bytes[pos..<pos + len])
        pos += len
        return out
    }
}

/// SHA-256 in plain Swift, so the pin computation is the same on Linux (tests)
/// and on device, with no CryptoKit dependency in the core.
enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var m = message
        let bitLength = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in (0..<8).reversed() { m.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xff)) }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: m.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(m[j]) << 24 | UInt32(m[j + 1]) << 16 | UInt32(m[j + 2]) << 8 | UInt32(m[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        var out = [UInt8]()
        out.reserveCapacity(32)
        for v in h { out += [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] }
        return out
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}

#if canImport(Security) && !os(Linux)
/// Answers the server-trust challenge: the system evaluates the chain, then
/// the leaf's SPKI must be one of the pins. Anything else cancels the
/// connection before a byte is sent.
final class PinningDelegate: NSObject, URLSessionDelegate {
    private let pins: [String]
    private let host: String

    init(pins: [String], host: String) {
        self.pins = pins
        self.host = host
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.host == host else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        guard SpkiPin.matches(certificateDER: der, pins: pins) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#endif
