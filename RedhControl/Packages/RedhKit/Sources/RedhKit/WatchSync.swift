import Foundation

/// What the iPhone sends the Watch: the setup and the secrets that go with it. The Watch has no
/// setup of its own; it takes what comes.
public struct WatchSync: Codable, Hashable, Sendable {
    public var setup: Setup
    public var tokens: [UUID: String]
    public var passwords: [UUID: String]

    /// The setup and its secrets as they are now.
    public init(setup: Setup, secrets: SecretStore) throws {
        self.setup = setup
        tokens = [:]
        passwords = [:]
        for server in setup.servers {
            tokens[server.id] = try secrets.secret(for: .token(server: server.id))
        }
        for box in setup.boxes {
            passwords[box.id] = try secrets.secret(for: .password(box: box.id))
        }
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(WatchSync.self, from: data)
    }

    public func data() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Puts it into place: first the secrets, also removing those of servers and boxes that went
    /// away, then the setup.
    @MainActor
    public func apply(to monitor: Monitor) throws {
        let secrets = monitor.secrets
        for server in monitor.setup.servers where !setup.servers.contains(where: { $0.id == server.id }) {
            try secrets.setSecret(nil, for: .token(server: server.id))
        }
        for box in monitor.setup.boxes where !setup.boxes.contains(where: { $0.id == box.id }) {
            try secrets.setSecret(nil, for: .password(box: box.id))
        }
        for server in setup.servers {
            try secrets.setSecret(tokens[server.id], for: .token(server: server.id))
        }
        for box in setup.boxes {
            try secrets.setSecret(passwords[box.id], for: .password(box: box.id))
        }
        try monitor.replaceSetup(setup)
    }
}
