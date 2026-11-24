import Foundation

/// Sends a request, judging the server's certificate by the policy. The default is
/// ``URLSessionTransport/shared``; tests pass their own.
public typealias Transport = @Sendable (URLRequest, TrustPolicy) async throws -> (Data, HTTPURLResponse)

/// Why a request got no answer at all.
public enum TransportError: Error, Hashable, Sendable, LocalizedError {
    /// The server's certificate was refused. `presented` is the one it showed, to pin it.
    case untrusted(reason: String, presented: CertificatePin?)
    /// No connection: no such name, nobody listening, or no answer in time.
    case unreachable(String)

    public var errorDescription: String? {
        switch self {
        case .untrusted(let reason, _): reason
        case .unreachable(let reason): reason
        }
    }
}

/// Requests through URLSession, with one session per trust policy so that connections are reused.
/// Nothing is cached and no cookies are kept.
public final class URLSessionTransport: @unchecked Sendable {
    public static let shared = URLSessionTransport()

    private let lock = NSLock()
    private var sessions: [TrustPolicy: (session: URLSession, delegate: TrustDelegate)] = [:]

    public init() {}

    public var transport: Transport {
        { request, policy in try await self.send(request, trust: policy) }
    }

    public func send(_ request: URLRequest, trust policy: TrustPolicy) async throws -> (Data, HTTPURLResponse) {
        let (session, delegate) = session(for: policy)
        let answer: (Data, URLResponse)
        do {
            answer = try await session.data(for: request)
        } catch let error as URLError {
            if let host = request.url?.host(), let refusal = delegate.takeRefusal(for: host) {
                throw refusal
            }
            throw TransportError.unreachable(error.localizedDescription)
        }
        guard let response = answer.1 as? HTTPURLResponse else {
            throw TransportError.unreachable("The answer isn't HTTP.")
        }
        return (answer.0, response)
    }

    private func session(for policy: TrustPolicy) -> (URLSession, TrustDelegate) {
        lock.withLock {
            if let existing = sessions[policy] {
                return existing
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForResource = 30
            configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
            let delegate = TrustDelegate(policy: policy)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            sessions[policy] = (session, delegate)
            return (session, delegate)
        }
    }
}

/// Answers a session's server-trust challenges by its policy, and remembers the refusals,
/// so that the caller learns why and which certificate it was.
final class TrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let policy: TrustPolicy
    private let lock = NSLock()
    private var refusals: [String: TransportError] = [:]

    init(policy: TrustPolicy) {
        self.policy = policy
    }

    func takeRefusal(for host: String) -> TransportError? {
        lock.withLock { refusals.removeValue(forKey: host) }
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        answer(challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        answer(challenge)
    }

    private func answer(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else {
            // Digest and the like: with no credential stored, the 401 comes back to the caller.
            return (.performDefaultHandling, nil)
        }
        switch policy.evaluate(trust, host: space.host) {
        case .trusted:
            return (.useCredential, URLCredential(trust: trust))
        case .refused(let reason, let presented):
            lock.withLock { refusals[space.host] = .untrusted(reason: reason, presented: presented) }
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}
