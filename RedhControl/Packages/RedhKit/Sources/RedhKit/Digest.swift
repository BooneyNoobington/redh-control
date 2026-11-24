import CryptoKit
import Foundation

/// An HTTP Digest challenge (RFC 7616) and its answer, with MD5 as the FRITZ!Box uses it for
/// TR-064. MD5 is what the protocol prescribes here, and the connection is TLS anyway.
struct DigestChallenge: Hashable, Sendable {
    var realm: String
    var nonce: String
    /// `auth` when the server offers it, nil for the old RFC 2069 answer.
    var qop: String?
    /// `MD5` or `MD5-sess`.
    var algorithm: String
    var opaque: String?

    /// Reads a `WWW-Authenticate` header; nil unless it is a Digest challenge this can answer.
    init?(header: String) {
        let text = header.trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasPrefix("digest ") else { return nil }
        let parameters = Self.parameters(text.dropFirst("digest ".count))
        guard let realm = parameters["realm"], let nonce = parameters["nonce"] else { return nil }
        let algorithm = parameters["algorithm"] ?? "MD5"
        guard ["md5", "md5-sess"].contains(algorithm.lowercased()) else { return nil }
        if let offered = parameters["qop"] {
            guard offered.split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "auth" })
            else { return nil }
            qop = "auth"
        } else {
            qop = nil
        }
        self.realm = realm
        self.nonce = nonce
        self.algorithm = algorithm
        opaque = parameters["opaque"]
    }

    /// The `Authorization` header for a request. `cnonce` is the client's random nonce.
    func authorization(method: String, uri: String, username: String, password: String, cnonce: String,
                       count: Int = 1) -> String {
        let nc = String(String(count, radix: 16).suffix(8)).leftPadded(to: 8)
        var ha1 = md5("\(username):\(realm):\(password)")
        if algorithm.lowercased() == "md5-sess" {
            ha1 = md5("\(ha1):\(nonce):\(cnonce)")
        }
        let ha2 = md5("\(method):\(uri)")
        let response = qop.map { md5("\(ha1):\(nonce):\(nc):\(cnonce):\($0):\(ha2)") } ?? md5("\(ha1):\(nonce):\(ha2)")
        var fields = [
            "username=\(quoted(username))", "realm=\(quoted(realm))", "nonce=\(quoted(nonce))",
            "uri=\(quoted(uri))", "algorithm=\(algorithm)", "response=\(quoted(response))",
        ]
        if let qop {
            fields += ["qop=\(qop)", "nc=\(nc)", "cnonce=\(quoted(cnonce))"]
        }
        if let opaque {
            fields.append("opaque=\(quoted(opaque))")
        }
        return "Digest " + fields.joined(separator: ", ")
    }

    /// `key=value` and `key="quoted, \"value\""` pairs, separated by commas; keys in lower case.
    static func parameters(_ text: Substring) -> [String: String] {
        var parameters: [String: String] = [:]
        var rest = text
        while true {
            rest = rest.drop { $0 == " " || $0 == "," }
            guard let equals = rest.firstIndex(of: "=") else { break }
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            rest = rest[rest.index(after: equals)...].drop { $0 == " " }
            var value = ""
            if rest.first == "\"" {
                rest = rest.dropFirst()
                var escaped = false
                while let character = rest.first {
                    rest = rest.dropFirst()
                    if escaped {
                        value.append(character)
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        break
                    } else {
                        value.append(character)
                    }
                }
            } else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                value = rest[..<end].trimmingCharacters(in: .whitespaces)
                rest = rest[end...]
            }
            parameters[key] = value
        }
        return parameters
    }
}

private func md5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { hex($0, uppercase: false) }.joined()
}

private func quoted(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
