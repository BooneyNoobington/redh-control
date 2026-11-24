import Foundation

/// What a FRITZ!Box knows about a device on its network.
public struct HostEntry: Hashable, Sendable {
    /// Whether the box sees the device on the network right now. It notices a device that went
    /// away only after a while.
    public var active: Bool
    public var ipAddress: String?
    public var hostName: String?
}

public enum FritzBoxError: Error, Hashable, Sendable, LocalizedError {
    /// The box has neither a name nor an address in the setup.
    case noAddress
    /// The box turned the login down: wrong user or password.
    case loginFailed
    /// A SOAP fault, with its UPnP error code.
    case fault(code: Int?, description: String?)
    /// Neither success nor a fault.
    case answer(status: Int)
    /// The box presented no certificate to pin.
    case noCertificate

    public var errorDescription: String? {
        switch self {
        case .noAddress: "The FRITZ!Box has neither a name nor an address."
        case .loginFailed: "The FRITZ!Box doesn't accept the user and password."
        case .fault(606, _): "The FRITZ!Box user lacks the rights for this (UPnP error 606)."
        case .fault(let code, let description):
            "The FRITZ!Box refused: \(description ?? "no reason given")\(code.map { " (UPnP error \($0))" } ?? "")."
        case .answer(let status): "The FRITZ!Box answered with HTTP \(status)."
        case .noCertificate: "The FRITZ!Box presented no certificate."
        }
    }
}

/// A client for a FRITZ!Box's TR-064 interface over HTTPS: Wake-on-LAN, and its list of hosts.
/// The box's self-signed certificate is pinned; the login is HTTP Digest.
public struct FritzBoxClient: Sendable {
    private let transport: Transport
    private let cnonce: @Sendable () -> String

    public init(transport: @escaping Transport = URLSessionTransport.shared.transport) {
        self.init(transport: transport) {
            (0..<8).map { _ in hex(UInt8.random(in: 0...255), uppercase: false) }.joined()
        }
    }

    init(transport: @escaping Transport, cnonce: @escaping @Sendable () -> String) {
        self.transport = transport
        self.cnonce = cnonce
    }

    /// Has the box send the Wake-on-LAN packet to the MAC address.
    public func wake(_ mac: MACAddress, via box: Box, password: String) async throws {
        _ = try await call("X_AVM-DE_WakeOnLANByMACAddress", [("NewMACAddress", mac.description)], box: box,
                           password: password)
    }

    /// What the box knows about the MAC address; nil if it doesn't know it at all.
    public func hostEntry(_ mac: MACAddress, on box: Box, password: String) async throws -> HostEntry? {
        let values: [String: String]
        do {
            values = try await call("GetSpecificHostEntry", [("NewMACAddress", mac.description)], box: box,
                                    password: password)
        } catch FritzBoxError.fault(code: 714, _) {
            return nil  // NoSuchEntryInArray
        }
        let nonEmpty = { (key: String) in values[key].flatMap { $0.isEmpty ? nil : $0 } }
        return HostEntry(active: values["NewActive"] == "1", ipAddress: nonEmpty("NewIPAddress"),
                         hostName: nonEmpty("NewHostName"))
    }

    /// The certificate the box presents, so that it can be pinned. The connection is refused on
    /// purpose, before anything is sent.
    public func presentedCertificate(of box: Box) async throws -> CertificatePin {
        var unpinned = box
        unpinned.certificatePin = nil
        do {
            _ = try await call("GetHostNumberOfEntries", [], box: unpinned, password: "")
        } catch TransportError.untrusted(_, let presented?) {
            return presented
        }
        throw FritzBoxError.noCertificate
    }

    /// Calls an action of the Hosts service, by name first, then by address.
    func call(_ action: String, _ arguments: [(name: String, value: String)], box: Box,
              password: String) async throws -> [String: String] {
        var failure: Error = FritzBoxError.noAddress
        for address in box.addresses {
            do {
                return try await call(action, arguments, at: address, box: box, password: password)
            } catch let error as TransportError {
                guard case .unreachable = error else { throw error }
                failure = error
            }
        }
        throw failure
    }

    private func call(_ action: String, _ arguments: [(name: String, value: String)], at address: String, box: Box,
                      password: String) async throws -> [String: String] {
        let host = address.contains(":") ? "[\(address)]" : address
        guard let url = URL(string: "https://\(host):\(box.port)\(SOAP.hostsPath)") else {
            throw TransportError.unreachable("'\(address)' is no address.")
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\(SOAP.hostsService)#\(action)", forHTTPHeaderField: "SOAPAction")
        request.httpBody = SOAP.envelope(action, service: SOAP.hostsService, arguments: arguments)
        let policy = TrustPolicy.pinned(box.certificatePin)

        var (data, response) = try await transport(request, policy)
        if response.statusCode == 401, let header = response.value(forHTTPHeaderField: "WWW-Authenticate"),
           let challenge = DigestChallenge(header: header) {
            let authorization = challenge.authorization(method: "POST", uri: SOAP.hostsPath, username: box.username,
                                                        password: password, cnonce: cnonce())
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            (data, response) = try await transport(request, policy)
        }
        if response.statusCode == 401 {
            throw FritzBoxError.loginFailed
        }
        let answer = SOAP.parse(data)
        if let fault = answer?.fault {
            throw FritzBoxError.fault(code: fault.code, description: fault.description)
        }
        guard response.statusCode == 200, let answer else { throw FritzBoxError.answer(status: response.statusCode) }
        return answer.values
    }
}
