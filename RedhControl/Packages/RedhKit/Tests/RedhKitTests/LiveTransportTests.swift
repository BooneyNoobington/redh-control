import Foundation
import Testing
@testable import RedhKit

enum LiveServer {
    static let url = ProcessInfo.processInfo.environment["REDHKIT_LIVE_URL"]
    static let root = ProcessInfo.processInfo.environment["REDHKIT_LIVE_ROOT"]
    static var configured: Bool { url != nil && root != nil }
}

/// ``URLSessionTransport`` against a real TLS server, which answers `/health`. Skipped unless
/// `REDHKIT_LIVE_URL` (such as `https://localhost:18443`) and `REDHKIT_LIVE_ROOT` (the root that
/// issued the server's certificate, in DER) are set; RedhKit's README says how to run it.
@Suite(.enabled(if: LiveServer.configured))
struct LiveTransportTests {
    let url: URL
    let root: Data
    let transport = URLSessionTransport()

    init() throws {
        url = try #require(URL(string: LiveServer.url ?? ""))
        root = try Data(contentsOf: URL(fileURLWithPath: LiveServer.root ?? ""))
    }

    var health: URLRequest {
        URLRequest(url: url.appending(path: "health"), timeoutInterval: 5)
    }

    @Test func theRootThatIssuedTheCertificateIsTrusted() async throws {
        let (data, response) = try await transport.send(health, trust: .root(root))
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("ok"))
    }

    @Test func anotherRootIsNot() async throws {
        let error = try await #require(throws: TransportError.self) {
            try await transport.send(health, trust: .root(try fixture("root.der")))
        }
        guard case .untrusted(_, let presented) = error else {
            Issue.record("not refused but \(error)")
            return
        }
        #expect(presented != nil)
    }

    @Test func withoutAPinTheCertificateIsNamedAndCanBePinned() async throws {
        let error = try await #require(throws: TransportError.self) {
            try await transport.send(health, trust: .pinned(nil))
        }
        guard case .untrusted(_, let presented?) = error else {
            Issue.record("no certificate named but \(error)")
            return
        }
        let (_, response) = try await transport.send(health, trust: .pinned(presented))
        #expect(response.statusCode == 200)
    }

    @Test func nobodyListening() async throws {
        var request = health
        request.url = URL(string: "https://127.0.0.1:9/health")
        let error = try await #require(throws: TransportError.self) {
            try await transport.send(request, trust: .root(root))
        }
        guard case .unreachable = error else {
            Issue.record("not unreachable but \(error)")
            return
        }
    }
}
