import Foundation

/// The setup on disk, as JSON, normally in Application Support. Secrets are never in it.
public struct SetupFile: Sendable {
    /// The format's version; a file from a newer one isn't read. Format 2 gives each server a
    /// rooster, where format 1 gave it a box.
    public static let version = 2

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/RedhControl/setup.json`.
    public static func standard() throws -> SetupFile {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return SetupFile(url: support.appending(path: "RedhControl/setup.json"))
    }

    /// The saved setup, or an empty one if nothing was saved yet.
    public func load() throws -> Setup {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return Setup()
        }
        let version = try JSONDecoder().decode(Version.self, from: data).version
        guard version <= Self.version else { throw SetupFileError.newerVersion(version) }
        return try JSONDecoder().decode(Stored.self, from: data).setup
    }

    public func save(_ setup: Setup) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var options: Data.WritingOptions = .atomic
        #if os(iOS) || os(watchOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try encoder.encode(Stored(version: Self.version, setup: setup)).write(to: url, options: options)
    }

    private struct Version: Decodable {
        var version: Int
    }

    private struct Stored: Codable {
        var version: Int
        var setup: Setup
    }
}

public enum SetupFileError: Error, Hashable, Sendable, LocalizedError {
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .newerVersion(let version):
            "The setup was saved by a newer version of Redh Control (format \(version)); update this one."
        }
    }
}
