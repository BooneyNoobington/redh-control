import Foundation
import Observation

/// What the apps show and do: the setup, a reading per server, and the commands waiting for their
/// effect. Changes to the setup are saved at once; secrets go to the ``SecretStore``.
@MainActor
@Observable
public final class Monitor {
    public private(set) var setup: Setup
    /// The latest guess per server; none before the first look, or after the server changed.
    public private(set) var readings: [Server.ID: Reading] = [:]
    public private(set) var lastRefresh: Date?
    public private(set) var isRefreshing = false
    /// Counts the changes to the setup and its secrets, so that the iPhone knows when to send them
    /// to the Watch.
    public private(set) var revision = 0

    public let secrets: SecretStore
    private var commands: [Server.ID: PendingCommand] = [:]
    private let file: SetupFile?
    private let transport: Transport
    private let now: @Sendable () -> Date

    /// `file` nil keeps changes in memory only, as the demo does.
    public init(setup: Setup, secrets: SecretStore, file: SetupFile?,
                transport: @escaping Transport = URLSessionTransport.shared.transport,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.setup = setup
        self.secrets = secrets
        self.file = file
        self.transport = transport
        self.now = now
    }

    /// The saved setup, and the Keychain.
    public static func standard() throws -> Monitor {
        let file = try SetupFile.standard()
        return Monitor(setup: try file.load(), secrets: KeychainSecretStore(), file: file)
    }

    /// Whether a command is waiting for its effect, so that looking more often is worth it.
    public var isWaiting: Bool {
        !commands.isEmpty
    }

    /// Looks at every server at once.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let homelab = Homelab(setup: setup, secrets: secrets, transport: transport)
        let servers = setup.servers
        let probes = await withTaskGroup(of: (Server.ID, Probe).self) { group in
            for server in servers {
                group.addTask { (server.id, await homelab.probe(server)) }
            }
            var probes: [Server.ID: Probe] = [:]
            for await (id, probe) in group {
                probes[id] = probe
            }
            return probes
        }
        let time = now()
        for (id, probe) in probes where setup.servers.contains(where: { $0.id == id }) {
            let reading = probe.reading(command: commands[id], now: time)
            readings[id] = reading
            commands[id] = reading.command
        }
        lastRefresh = time
    }

    /// Has the server's rooster wake it up. A rooster server whose RedhAPI didn't answer the last
    /// look can't, so the answer comes at once: wake that one up first.
    public func wake(_ server: Server) async throws {
        if let rooster = setup.roosterServer(for: server), readings[rooster.id]?.answers == false {
            throw HomelabError.roosterNotUp(rooster: rooster.name, server: server.name)
        }
        try await Homelab(setup: setup, secrets: secrets, transport: transport).wake(server)
        start(.wake(since: now()), for: server)
    }

    /// Has the server's RedhAPI shut it down.
    public func shutDown(_ server: Server) async throws {
        _ = try await Homelab(setup: setup, secrets: secrets, transport: transport).shutDown(server)
        start(.shutdown(since: now()), for: server)
    }

    /// redh-manager's list of the server's apps. Not part of `refresh()`: only a server's page asks.
    public func apps(of server: Server) async throws -> AppsListing {
        try await Homelab(setup: setup, secrets: secrets, transport: transport).apps(server)
    }

    /// What the server's machine is doing. Not part of `refresh()` either: only a server's page asks.
    public func system(of server: Server) async throws -> SystemReport {
        try await Homelab(setup: setup, secrets: secrets, transport: transport).system(server)
    }

    /// Whether the server's rooster could wake it up again; asked before an always-on server is
    /// shut down.
    public func wakeCheck(_ server: Server) async -> WakeCheck {
        await Homelab(setup: setup, secrets: secrets, transport: transport).wakeCheck(server)
    }

    /// The certificate a box presents, for the user to confirm before it is pinned.
    public func presentedCertificate(of box: Box) async throws -> CertificatePin {
        try await Homelab(setup: setup, secrets: secrets, transport: transport).presentedCertificate(of: box)
    }

    // MARK: The setup

    /// Adds the server, or replaces the one with its ID. A token replaces the stored one; nil
    /// leaves it as it is.
    public func save(_ server: Server, token: String?) throws {
        try change { setup in
            if let index = setup.servers.firstIndex(where: { $0.id == server.id }) {
                setup.servers[index] = server
            } else {
                setup.servers.append(server)
            }
        }
        readings[server.id] = nil
        if let token {
            try secrets.setSecret(token, for: .token(server: server.id))
        }
    }

    /// Removes the server and its token; the servers it woke have no rooster afterwards.
    public func remove(_ server: Server) throws {
        try change { setup in
            setup.servers.removeAll { $0.id == server.id }
            for index in setup.servers.indices where setup.servers[index].rooster == .server(server.id) {
                setup.servers[index].rooster = nil
            }
        }
        try secrets.setSecret(nil, for: .token(server: server.id))
    }

    /// Adds the box, or replaces the one with its ID. A password replaces the stored one; nil
    /// leaves it as it is.
    public func save(_ box: Box, password: String?) throws {
        try change { setup in
            if let index = setup.boxes.firstIndex(where: { $0.id == box.id }) {
                setup.boxes[index] = box
            } else {
                setup.boxes.append(box)
            }
        }
        if let password {
            try secrets.setSecret(password, for: .password(box: box.id))
        }
    }

    /// Removes the box and its password; the servers it woke have no rooster afterwards.
    public func remove(_ box: Box) throws {
        try change { setup in
            setup.boxes.removeAll { $0.id == box.id }
            for index in setup.servers.indices where setup.servers[index].rooster == .box(box.id) {
                setup.servers[index].rooster = nil
            }
        }
        try secrets.setSecret(nil, for: .password(box: box.id))
    }

    /// The root certificate RedhAPI's certificates chain up to, in DER; nil removes it.
    public func setRootCertificate(_ der: Data?) throws {
        try change { $0.rootCertificate = der }
        readings = [:]
    }

    /// The whole setup at once, as the Watch gets it from the iPhone. If anything changed, the
    /// readings start over.
    public func replaceSetup(_ new: Setup) throws {
        guard new != setup else { return }
        try change { $0 = new }
        readings = [:]
    }

    public func hasSecret(_ key: SecretKey) -> Bool {
        ((try? secrets.secret(for: key)) ?? nil) != nil
    }

    private func start(_ command: PendingCommand, for server: Server) {
        commands[server.id] = command
        let state: ServerState = if case .wake = command { .waking } else { .shuttingDown }
        readings[server.id] = Reading(state: state, command: command)
    }

    private func change(_ edit: (inout Setup) -> Void) throws {
        var changed = setup
        edit(&changed)
        try file?.save(changed)
        setup = changed
        revision += 1
        let ids = Set(changed.servers.map(\.id))
        readings = readings.filter { ids.contains($0.key) }
        commands = commands.filter { ids.contains($0.key) }
    }
}
