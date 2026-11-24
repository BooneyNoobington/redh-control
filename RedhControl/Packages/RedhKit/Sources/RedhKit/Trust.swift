import CryptoKit
import Foundation
import Security

/// The SHA-256 of a certificate: the fingerprint that `openssl x509 -fingerprint -sha256` and
/// browsers show.
public struct CertificatePin: Hashable, Sendable, CustomStringConvertible {
    public let sha256: Data

    /// The pin of a certificate in DER.
    public init(certificate: Data) {
        sha256 = Data(SHA256.hash(data: certificate))
    }

    /// Reads a fingerprint: 64 hex digits, with or without colons and spaces, also with
    /// openssl's `sha256 Fingerprint=` in front.
    public init?(_ text: String) {
        let value = text.split(separator: "=").last.map(String.init) ?? text
        guard let bytes = hexBytes(value.filter { $0 != ":" && !$0.isWhitespace }), bytes.count == 32 else { return nil }
        sha256 = Data(bytes)
    }

    /// `E9:41:B0:…`, in capitals, as openssl writes it.
    public var description: String {
        sha256.map { hex($0) }.joined(separator: ":")
    }
}

extension CertificatePin: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let pin = CertificatePin(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(text)' is not a SHA-256 fingerprint")
        }
        self = pin
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// What `redh-api token` prints where RedhAPI has its own certificate: the certificate's SHA-256
/// and the token in one line, `redh1:<64 hex digits>:<token>`. Pasted into a server's editor, it
/// pins the certificate, so nobody has to compare fingerprints, and nothing is trusted on first
/// sight.
public struct PairingCode: Hashable, Sendable {
    public var pin: CertificatePin
    public var token: String

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 2,
                                                                                omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "redh1", parts[1].count == 64, let pin = CertificatePin(String(parts[1])),
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        self.pin = pin
        token = String(parts[2])
    }
}

/// How a server's certificate is judged. There is no policy that accepts any certificate.
public enum TrustPolicy: Hashable, Sendable {
    /// Issued, through any intermediates, by this root and no other, for the host asked for:
    /// RedhAPI behind Caddy. The root is in DER.
    case root(Data)
    /// Exactly this certificate, whatever its names, issuer or dates: a FRITZ!Box's self-signed
    /// one, or RedhAPI's own. Nil pins nothing yet, so every certificate is refused, and the
    /// refusal says which one it was.
    case pinned(CertificatePin?)

    /// Judges the certificates a server presented for the host.
    public func evaluate(_ trust: SecTrust, host: String) -> TrustVerdict {
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        let presented = chain.first.map { CertificatePin(certificate: SecCertificateCopyData($0) as Data) }
        switch self {
        case .pinned(let pin):
            guard let presented else { return .refused(reason: "The server presented no certificate.", presented: nil) }
            guard let pin else {
                return .refused(reason: "No certificate is pinned for it yet.", presented: presented)
            }
            return presented == pin
                ? .trusted
                : .refused(reason: "It presented another certificate than the pinned one.", presented: presented)
        case .root(let der):
            guard let root = SecCertificateCreateWithData(nil, der as CFData) else {
                return .refused(reason: "The root certificate in the setup can't be read.", presented: presented)
            }
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
            SecTrustSetAnchorCertificates(trust, [root] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                return .trusted
            }
            let reason = error.map { ($0 as Error).localizedDescription } ?? "The certificate isn't trusted."
            return .refused(reason: reason, presented: presented)
        }
    }
}

public enum TrustVerdict: Hashable, Sendable {
    case trusted
    /// Refused, with the certificate the server presented, if there was one.
    case refused(reason: String, presented: CertificatePin?)
}
