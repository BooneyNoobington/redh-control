import Foundation

/// What `GET /v1/status` reports, as RedhAPI/README.md describes it.
public struct ServerStatus: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    /// The kernel's ID for this boot, a new one after every start; nil without /proc.
    public var bootID: String?
    public var uptimeSeconds: Int?
    public var shutdown: ShutdownStatus
    /// Where it sends the packets that wake other servers; nil before RedhAPI 0.2.0, which can't.
    public var wake: WakeStatus?

    public init(name: String, version: String, bootID: String? = nil, uptimeSeconds: Int? = nil,
                shutdown: ShutdownStatus, wake: WakeStatus? = nil) {
        self.name = name
        self.version = version
        self.bootID = bootID
        self.uptimeSeconds = uptimeSeconds
        self.shutdown = shutdown
        self.wake = wake
    }

    enum CodingKeys: String, CodingKey {
        case name, version, shutdown, wake
        case bootID = "boot_id"
        case uptimeSeconds = "uptime_seconds"
    }
}

/// Where `POST /v1/wake` sends its magic packets: a UDP broadcast to this address and port.
public struct WakeStatus: Codable, Hashable, Sendable {
    public var broadcast: String
    public var port: Int

    public init(broadcast: String, port: Int) {
        self.broadcast = broadcast
        self.port = port
    }
}

public struct ShutdownStatus: Codable, Hashable, Sendable {
    /// Whether a shutdown request would be carried out.
    public var ready: Bool
    /// Why not, when `ready` is false.
    public var problem: String?
    /// A shutdown was accepted, and redh-shut hasn't finished yet.
    public var pending: Bool
    /// Why the last shutdown failed, if it did.
    public var lastError: String?

    public init(ready: Bool, problem: String? = nil, pending: Bool = false, lastError: String? = nil) {
        self.ready = ready
        self.problem = problem
        self.pending = pending
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case ready, problem, pending
        case lastError = "last_error"
    }
}

/// The answer to `POST /v1/shutdown`.
public struct ShutdownAccepted: Codable, Hashable, Sendable {
    public var accepted: Bool
    /// Seconds until redh-shut runs.
    public var delaySeconds: Double

    enum CodingKeys: String, CodingKey {
        case accepted
        case delaySeconds = "delay_seconds"
    }
}

/// The answer to `POST /v1/wake`. Sent isn't woken: the woken server is up once its own RedhAPI
/// answers.
public struct WakeSent: Codable, Hashable, Sendable {
    public var sent: Bool
    /// The MAC address the packet was for.
    public var mac: String
}

/// An answer from RedhAPI, or from Caddy in front of it, other than success.
public enum RedhAPIError: Error, Hashable, Sendable, LocalizedError {
    /// 401: the server is up, but the token isn't accepted.
    case unauthorized
    /// 409: RedhAPI can't shut the server down; the message says why.
    case shutdownUnavailable(String)
    /// 409: RedhAPI can't list the apps, without redh-manager for instance; the message says why.
    case appsUnavailable(String)
    /// 409: RedhAPI couldn't send the packet that wakes another server; the message says why.
    case wakeFailed(String)
    /// 502, 503 or 504, which come from Caddy: the server is up, RedhAPI isn't running.
    case notRunning(status: Int)
    /// Any other error status, with RedhAPI's code and message if there were any.
    case answer(status: Int, code: String?, message: String?)
    /// A success whose body isn't what the contract says.
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "RedhAPI doesn't accept the token."
        case .shutdownUnavailable(let problem): "RedhAPI can't shut the server down: \(problem)"
        case .appsUnavailable(let problem): "RedhAPI can't list the apps: \(problem)"
        case .wakeFailed(let problem): problem
        case .notRunning: "RedhAPI isn't running."
        case .answer(let status, _, let message?): "RedhAPI answered with HTTP \(status): \(message)"
        case .answer(let status, _, nil): "The server answered with HTTP \(status)."
        case .unreadable(let reason): "RedhAPI's answer can't be read: \(reason)"
        }
    }
}

/// A client for RedhAPI, as RedhAPI/README.md describes it. A server's certificate is the one its
/// pairing code pinned, or else has to chain up to the setup's root certificate.
public struct RedhAPIClient: Sendable {
    /// The setup's root certificate, in DER; nil where every server is paired.
    public let rootCertificate: Data?
    private let transport: Transport

    public init(rootCertificate: Data?, transport: @escaping Transport = URLSessionTransport.shared.transport) {
        self.rootCertificate = rootCertificate
        self.transport = transport
    }

    /// How the server's certificate is judged: RedhAPI's own, pinned, or one from the setup's root.
    /// Without either, nothing is sent.
    public func policy(for server: Server) throws -> TrustPolicy {
        if let pin = server.certificatePin {
            return .pinned(pin)
        }
        guard let rootCertificate else {
            throw TransportError.untrusted(reason: "The setup has no root certificate for RedhAPI.", presented: nil)
        }
        return .root(rootCertificate)
    }

    /// `GET /health`, which needs no token. Throws unless RedhAPI answers.
    public func health(of server: Server) async throws {
        let data = try await send("GET", "health", to: server, token: nil, timeout: 5)
        guard (try? JSONDecoder().decode([String: String].self, from: data)) == ["status": "ok"] else {
            throw RedhAPIError.unreadable("/health doesn't say ok")
        }
    }

    /// `GET /v1/status`.
    public func status(of server: Server, token: String) async throws -> ServerStatus {
        try decode(ServerStatus.self, from: try await send("GET", "v1/status", to: server, token: token, timeout: 5))
    }

    /// `POST /v1/shutdown`: RedhAPI answers, and shuts the server down `delaySeconds` later.
    public func shutdown(_ server: Server, token: String) async throws -> ShutdownAccepted {
        try decode(ShutdownAccepted.self, from: try await send("POST", "v1/shutdown", to: server, token: token, timeout: 10))
    }

    /// `GET /v1/apps`: redh-manager's list of the apps. It can take a while, as redh asks systemd
    /// and Podman.
    public func apps(of server: Server, token: String) async throws -> AppsListing {
        try decode(AppsListing.self, from: try await send("GET", "v1/apps", to: server, token: token, timeout: 30))
    }

    /// `GET /v1/system`: what the machine is doing. The first request after a while waits a second
    /// for RedhAPI's second reading.
    public func system(of server: Server, token: String) async throws -> SystemReport {
        try decode(SystemReport.self, from: try await send("GET", "v1/system", to: server, token: token, timeout: 10))
    }

    /// `POST /v1/wake`: the server, as the rooster of another one, sends the magic packet for that
    /// one's network card.
    public func wake(_ mac: MACAddress, via server: Server, token: String) async throws -> WakeSent {
        let body = try JSONEncoder().encode(["mac": mac.description])
        return try decode(WakeSent.self, from: try await send("POST", "v1/wake", to: server, token: token, body: body,
                                                              timeout: 10))
    }

    private func send(_ method: String, _ path: String, to server: Server, token: String?, body: Data? = nil,
                      timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: server.apiURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport(request, try policy(for: server))
        let status = response.statusCode
        if (200..<300).contains(status) {
            return data
        }
        let error = try? JSONDecoder().decode(ErrorAnswer.self, from: data).error
        switch (status, error?.code) {
        case (401, _): throw RedhAPIError.unauthorized
        case (409, "shutdown_unavailable"): throw RedhAPIError.shutdownUnavailable(error?.message ?? "")
        case (409, "apps_unavailable"): throw RedhAPIError.appsUnavailable(error?.message ?? "")
        case (409, "wake_failed"): throw RedhAPIError.wakeFailed(error?.message ?? "")
        case (502, _), (503, _), (504, _): throw RedhAPIError.notRunning(status: status)
        default: throw RedhAPIError.answer(status: status, code: error?.code, message: error?.message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw RedhAPIError.unreadable("'\(key.stringValue)' is missing")
        } catch {
            throw RedhAPIError.unreadable("it isn't the JSON the contract describes")
        }
    }
}

/// `{"error": {"code": ..., "message": ...}}`
private struct ErrorAnswer: Decodable {
    struct Body: Decodable {
        var code: String
        var message: String
    }

    var error: Body
}
