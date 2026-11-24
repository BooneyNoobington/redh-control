import Foundation
import Security

/// A root certificate as the user has it: PEM, as step-ca and Caddy write it, or DER.
public enum RootCertificate {
    /// The DER of the certificate, or of the first one in a PEM file; nil if there is none.
    public static func der(from data: Data) -> Data? {
        let begin = "-----BEGIN CERTIFICATE-----"
        let der: Data
        if let text = String(data: data, encoding: .utf8), let start = text.range(of: begin) {
            guard let end = text.range(of: "-----END CERTIFICATE-----", range: start.upperBound..<text.endIndex),
                  let decoded = Data(base64Encoded: String(text[start.upperBound..<end.lowerBound]),
                                     options: .ignoreUnknownCharacters) else { return nil }
            der = decoded
        } else {
            der = data
        }
        return SecCertificateCreateWithData(nil, der as CFData) == nil ? nil : der
    }

    /// Who the certificate is for, such as "Lab Root CA".
    public static func summary(of der: Data) -> String? {
        SecCertificateCreateWithData(nil, der as CFData).flatMap { SecCertificateCopySubjectSummary($0) as String? }
    }
}
