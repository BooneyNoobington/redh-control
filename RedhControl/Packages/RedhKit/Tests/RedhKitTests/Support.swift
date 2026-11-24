import Foundation
import Security
import Testing
@testable import RedhKit

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func json(_ text: String) -> Data {
    Data(text.utf8)
}

/// The example of `GET /v1/status` in RedhAPI's README, which is the contract. RedhAPI is a
/// repository of its own, so this is a copy; ``ContractTests`` compares it with the README.
func statusExample() throws -> Data {
    try fixture("status.json")
}

/// 2027-01-01, within the validity of the test leaves (see Fixtures/make-certificates.sh).
let evaluationDate = Date(timeIntervalSince1970: 1_798_761_600)

/// A SecTrust for certificates from the fixtures, the leaf first, evaluated as of `evaluationDate`.
func serverTrust(_ names: String...) throws -> SecTrust {
    let certificates = try names.map { name in
        try #require(SecCertificateCreateWithData(nil, try fixture("\(name).der") as CFData))
    }
    var trust: SecTrust?
    #expect(SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
    let made = try #require(trust)
    SecTrustSetVerifyDate(made, evaluationDate as CFDate)
    return made
}

typealias Reply = (status: Int, headers: [String: String], body: Data)

/// Answers requests through a handler, and remembers them with their trust policies.
actor FakeNetwork {
    private(set) var sent: [(request: URLRequest, policy: TrustPolicy)] = []
    private var handler: @Sendable (URLRequest) throws -> Reply = { _ in (404, [:], Data()) }

    func reply(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) {
        self.handler = handler
    }

    private func handle(_ request: URLRequest, _ policy: TrustPolicy) throws -> Reply {
        sent.append((request, policy))
        return try handler(request)
    }

    nonisolated var transport: Transport {
        { request, policy in
            let reply = try await self.handle(request, policy)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: reply.headers)!
            return (reply.body, response)
        }
    }
}
