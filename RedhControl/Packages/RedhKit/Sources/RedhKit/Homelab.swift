import Foundation

/// What one look at a server found: RedhAPI's answer, and the rooster's if it was asked.
public struct Probe: Hashable, Sendable {
    public var api: APIAnswer
    public var rooster: RoosterAnswer

    public init(api: APIAnswer, rooster: RoosterAnswer) {
        self.api = api
        self.rooster = rooster
    }

    public func reading(command: PendingCommand?, now: Date = Date()) -> Reading {
        Guess.reading(api: api, rooster: rooster, command: command, now: now)
    }
}

/// Whether a server could be woken up again, as its rooster says.
public enum WakeCheck: Hashable, Sendable {
    /// Its rooster can wake it up; the text says which, and how it knows.
    case possible(String)
    /// Redh Control can't count on waking it up; the text says why.
    case uncertain(String)
}

/// The setup, its secrets and the two clients together: looking at servers, waking them up,
/// shutting them down.
public struct Homelab: Sendable {
    public let setup: Setup
    private let secrets: SecretStore
    private let api: RedhAPIClient
    private let boxes: FritzBoxClient

    public init(setup: Setup, secrets: SecretStore, transport: @escaping Transport = URLSessionTransport.shared.transport) {
        self.setup = setup
        self.secrets = secrets
        api = RedhAPIClient(rootCertificate: setup.rootCertificate, transport: transport)
        boxes = FritzBoxClient(transport: transport)
    }

    init(setup: Setup, secrets: SecretStore, transport: @escaping Transport, cnonce: @escaping @Sendable () -> String) {
        self.setup = setup
        self.secrets = secrets
        api = RedhAPIClient(rootCertificate: setup.rootCertificate, transport: transport)
        boxes = FritzBoxClient(transport: transport, cnonce: cnonce)
    }

    /// One look at the server: RedhAPI first, its status with a token, `/health` without one.
    /// The rooster only when RedhAPI doesn't answer.
    public func probe(_ server: Server) async -> Probe {
        let api = await askAPI(server)
        switch api {
        case .unreachable, .untrusted:
            return Probe(api: api, rooster: await askRooster(about: server, api: api))
        case .status, .noAccess, .notRunning, .failed:
            return Probe(api: api, rooster: .notAsked)
        }
    }

    /// Asks the server's RedhAPI to shut it down.
    public func shutDown(_ server: Server) async throws -> ShutdownAccepted {
        guard let token = try secrets.secret(for: .token(server: server.id)) else {
            throw HomelabError.noToken(server: server.name)
        }
        return try await api.shutdown(server, token: token)
    }

    /// redh-manager's list of the server's apps, through its RedhAPI.
    public func apps(_ server: Server) async throws -> AppsListing {
        guard let token = try secrets.secret(for: .token(server: server.id)) else {
            throw HomelabError.noToken(server: server.name)
        }
        return try await api.apps(of: server, token: token)
    }

    /// What the server's machine is doing, through its RedhAPI.
    public func system(_ server: Server) async throws -> SystemReport {
        guard let token = try secrets.secret(for: .token(server: server.id)) else {
            throw HomelabError.noToken(server: server.name)
        }
        return try await api.system(of: server, token: token)
    }

    /// Asks the server's rooster to wake it up: its FRITZ!Box, or the RedhAPI of another server.
    public func wake(_ server: Server) async throws {
        if let box = setup.box(for: server) {
            let mac = try macAddress(of: server)
            guard let password = try secrets.secret(for: .password(box: box.id)) else {
                throw HomelabError.noPassword(box: box.name)
            }
            try await boxes.wake(mac, via: box, password: password)
        } else if let rooster = setup.roosterServer(for: server) {
            let mac = try macAddress(of: server)
                guard let token = try secrets.secret(for: .token(server: rooster.id)) else {
                throw HomelabError.noToken(server: rooster.name)
            }
            do {
                _ = try await api.wake(mac, via: rooster, token: token)
            } catch RedhAPIError.answer(status: 404, _, _) {
                throw HomelabError.roosterCantWake(rooster: rooster.name)
            } catch RedhAPIError.notRunning, TransportError.unreachable {
                throw HomelabError.roosterNotUp(rooster: rooster.name, server: server.name)
            }
        } else {
            throw HomelabError.noRooster(server: server.name)
        }
    }

    /// Whether the server's rooster could wake it up again, asked before an always-on server is
    /// shut down: a FRITZ!Box has to know the server's MAC address, another server has to be up
    /// with a RedhAPI that can wake servers.
    public func wakeCheck(_ server: Server) async -> WakeCheck {
        guard setup.roosterName(for: server) != nil else {
            return .uncertain("It has no rooster, so nothing can wake it up again.")
        }
        guard let mac = server.mac else {
            return .uncertain("Without its MAC address, nothing can wake it up again.")
        }
        if let box = setup.box(for: server) {
            do {
                guard let password = try secrets.secret(for: .password(box: box.id)) else {
                    return .uncertain("There's no password for the FRITZ!Box \(box.name), so it can't wake it up again.")
                }
                guard try await boxes.hostEntry(mac, on: box, password: password) != nil else {
                    return .uncertain("The FRITZ!Box \(box.name) doesn't know its MAC address, so it can't wake it up again.")
                }
                return .possible("The FRITZ!Box \(box.name) knows its MAC address and can wake it up again.")
            } catch {
                return .uncertain("The FRITZ!Box \(box.name) can't say whether it could wake it up: \(error.localizedDescription)")
            }
        }
        guard let rooster = setup.roosterServer(for: server) else {
            return .uncertain("It has no rooster, so nothing can wake it up again.")
        }
        switch await askAPI(rooster) {
        case .status(let status) where status.wake == nil:
            return .uncertain("Its rooster \(rooster.name) has RedhAPI \(status.version), which can't wake servers yet.")
        case .status:
            return .possible("Its rooster \(rooster.name) is up and can wake it up again.")
        case .noAccess(let why):
            return .uncertain("Its rooster \(rooster.name) can't be asked: \(why)")
        case .notRunning, .failed, .unreachable, .untrusted:
            return .uncertain("Its rooster \(rooster.name) doesn't answer, so it couldn't wake it up again now.")
        }
    }

    /// The certificate a box presents, for the user to confirm before it is pinned.
    public func presentedCertificate(of box: Box) async throws -> CertificatePin {
        try await boxes.presentedCertificate(of: box)
    }

    private func macAddress(of server: Server) throws -> MACAddress {
        guard let mac = server.mac else { throw HomelabError.noMACAddress(server: server.name) }
        return mac
    }

    private func askAPI(_ server: Server) async -> APIAnswer {
        do {
            guard let token = try secrets.secret(for: .token(server: server.id)) else {
                try await api.health(of: server)
                return .noAccess("There's no token for \(server.name).")
            }
            return .status(try await api.status(of: server, token: token))
        } catch RedhAPIError.unauthorized {
            return .noAccess("RedhAPI doesn't accept the token.")
        } catch RedhAPIError.notRunning {
            return .notRunning
        } catch let error as RedhAPIError {
            return .failed(error.localizedDescription)
        } catch TransportError.untrusted(let reason, _) {
            return .untrusted(reason)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// What the server's rooster can say while its RedhAPI doesn't: a FRITZ!Box whether it sees
    /// the server, another server whether the homelab can be reached at all. That one is asked
    /// only when there was no connection; a refused certificate means the server answered.
    private func askRooster(about server: Server, api answer: APIAnswer) async -> RoosterAnswer {
        if let box = setup.box(for: server) {
            return await askBox(box, about: server)
        }
        guard case .unreachable = answer, let rooster = setup.roosterServer(for: server) else {
            return .notAsked
        }
        do {
            try await api.health(of: rooster)
            return .answers(rooster.name)
        } catch {
            return .notAsked
        }
    }

    private func askBox(_ box: Box, about server: Server) async -> RoosterAnswer {
        guard let mac = server.mac else { return .unavailable("It has no MAC address in the setup.") }
        do {
            guard let password = try secrets.secret(for: .password(box: box.id)) else {
                return .unavailable("There's no password for the FRITZ!Box \(box.name).")
            }
            guard let entry = try await boxes.hostEntry(mac, on: box, password: password) else { return .unknownHost }
            return entry.active ? .active : .inactive
        } catch {
            return .unavailable("The FRITZ!Box \(box.name) can't say: \(error.localizedDescription)")
        }
    }
}

public enum HomelabError: Error, Hashable, Sendable, LocalizedError {
    case noToken(server: String)
    case noRooster(server: String)
    case noMACAddress(server: String)
    case noPassword(box: String)
    /// The rooster, another server, doesn't answer, so it can't wake the server.
    case roosterNotUp(rooster: String, server: String)
    /// The rooster's RedhAPI is older than 0.2.0, which brought `POST /v1/wake`.
    case roosterCantWake(rooster: String)

    public var errorDescription: String? {
        switch self {
        case .noToken(let server): "There's no token for \(server)."
        case .noRooster(let server): "\(server) has no rooster, so nothing can wake it up."
        case .noMACAddress(let server): "\(server) has no MAC address in the setup."
        case .noPassword(let box): "There's no password for the FRITZ!Box \(box)."
        case .roosterNotUp(let rooster, let server):
            "\(rooster) wakes \(server) up, but doesn't answer now. Wake \(rooster) up first."
        case .roosterCantWake(let rooster):
            "RedhAPI on \(rooster) can't wake servers yet: it needs version 0.2.0 or newer."
        }
    }
}
