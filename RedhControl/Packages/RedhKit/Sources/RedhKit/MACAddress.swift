import Foundation

/// A MAC address, written the way the FRITZ!Box wants it: `AA:BB:CC:DD:EE:FF`.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    /// Reads six bytes in hex, separated by colons, dashes, dots or nothing:
    /// `aa:bb:cc:dd:ee:ff`, `AA-BB-CC-DD-EE-FF`, `aabb.ccdd.eeff`, `aabbccddeeff`.
    public init?(_ text: String) {
        guard let bytes = hexBytes(text.trimmingCharacters(in: .whitespaces).filter { !":-.".contains($0) }),
              bytes.count == 6 else { return nil }
        self.bytes = bytes
    }

    public var description: String {
        bytes.map { hex($0) }.joined(separator: ":")
    }
}

extension MACAddress: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let address = MACAddress(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(text)' is not a MAC address")
        }
        self = address
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Two hex digits.
func hex(_ byte: UInt8, uppercase: Bool = true) -> String {
    let digits = String(byte, radix: 16, uppercase: uppercase)
    return byte < 16 ? "0" + digits : digits
}

/// The bytes of a string of hex digits, two per byte; nil if it's anything else.
func hexBytes(_ digits: String) -> [UInt8]? {
    let characters = Array(digits)
    guard characters.count.isMultiple(of: 2), characters.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
    return stride(from: 0, to: characters.count, by: 2).compactMap { UInt8(String(characters[$0...$0 + 1]), radix: 16) }
}
