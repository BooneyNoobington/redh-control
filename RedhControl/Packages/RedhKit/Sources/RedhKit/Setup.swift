import Foundation

/// Everything Redh Control knows about the homelab but the secrets, which a ``SecretStore`` keeps.
public struct Setup: Codable, Hashable, Sendable {
    public var boxes: [Box]
    public var servers: [Server]
    /// The root certificate, in DER, that RedhAPI's certificates chain up to: the homelab's ACME CA.
    public var rootCertificate: Data?

    public init(boxes: [Box] = [], servers: [Server] = [], rootCertificate: Data? = nil) {
        self.boxes = boxes
        self.servers = servers
        self.rootCertificate = rootCertificate
    }

    /// The FRITZ!Box that wakes the server up, if its rooster is one.
    public func box(for server: Server) -> Box? {
        guard case .box(let id)? = server.rooster else { return nil }
        return boxes.first { $0.id == id }
    }

    /// The server that wakes the server up, if its rooster is one.
    public func roosterServer(for server: Server) -> Server? {
        guard case .server(let id)? = server.rooster else { return nil }
        return servers.first { $0.id == id }
    }

    /// The name of the server's rooster, if it has one in the setup.
    public func roosterName(for server: Server) -> String? {
        box(for: server)?.name ?? roosterServer(for: server)?.name
    }

    /// The servers whose rooster this one is.
    public func servers(wokenBy server: Server) -> [Server] {
        servers.filter { $0.rooster == .server(server.id) }
    }
}

/// Who wakes a server up: a FRITZ!Box, or another server, whose RedhAPI sends the Wake-on-LAN
/// packet.
public enum Rooster: Hashable, Sendable {
    case box(Box.ID)
    case server(Server.ID)
}

extension Rooster: Codable {
    /// `{"box": ID}` or `{"server": ID}`.
    private enum CodingKeys: String, CodingKey {
        case box, server
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(UUID.self, forKey: .box) {
            self = .box(id)
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .server) {
            self = .server(id)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "A rooster is a box or a server."))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .box(let id): try container.encode(id, forKey: .box)
        case .server(let id): try container.encode(id, forKey: .server)
        }
    }
}

/// A FRITZ!Box: it wakes the servers whose rooster it is, and knows which of them are on the
/// network.
public struct Box: Codable, Hashable, Identifiable, Sendable {
    /// TR-064 over HTTPS.
    public static let defaultPort = 49443

    public var id: UUID
    /// What the app calls it, such as "lab-box".
    public var name: String
    /// Its name in the local DNS, such as "fritz.lab.internal".
    public var host: String
    /// Its IP address, tried when the name doesn't work.
    public var fallbackAddress: String?
    public var port: Int
    /// The FRITZ!Box user the app logs in as. The password is in the ``SecretStore``.
    public var username: String
    /// The box's own certificate, pinned when the app first connected to it; nil before that.
    public var certificatePin: CertificatePin?

    public init(id: UUID = UUID(), name: String, host: String, fallbackAddress: String? = nil,
                port: Int = Box.defaultPort, username: String, certificatePin: CertificatePin? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.fallbackAddress = fallbackAddress
        self.port = port
        self.username = username
        self.certificatePin = certificatePin
    }

    /// Where TR-064 is tried, in this order: the name, then the address.
    public var addresses: [String] {
        [host, fallbackAddress ?? ""].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// A server with RedhAPI on it.
public struct Server: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// What the app calls it, such as "nas".
    public var name: String
    /// RedhAPI's base URL, normally ``defaultAPIURL(for:)`` behind Caddy, any of the server's names
    /// or addresses where RedhAPI has its own certificate.
    public var apiURL: URL
    /// RedhAPI's own certificate, which Redh Control trusts alone, from the server's pairing code;
    /// nil behind Caddy, where the setup's root certificate is trusted.
    public var certificatePin: CertificatePin?
    /// Who wakes it up: a FRITZ!Box or another server; nil for nobody.
    public var rooster: Rooster?
    /// The address of its network card, to wake it, and to ask a FRITZ!Box about it.
    public var mac: MACAddress?
    public var icon: ServerIcon
    public var color: ServerColor
    /// Meant to stay on: shutting it down asks once more, after asking its rooster whether it could
    /// wake it up again, and the Watch doesn't offer it.
    public var alwaysOn: Bool

    public init(id: UUID = UUID(), name: String, apiURL: URL, certificatePin: CertificatePin? = nil,
                rooster: Rooster? = nil, mac: MACAddress? = nil, icon: ServerIcon = .serverRack,
                color: ServerColor = .blue, alwaysOn: Bool = false) {
        self.id = id
        self.name = name
        self.apiURL = apiURL
        self.certificatePin = certificatePin
        self.rooster = rooster
        self.mac = mac
        self.icon = icon
        self.color = color
        self.alwaysOn = alwaysOn
    }

    /// `https://rapi.<name>.internal`, where a server's RedhAPI normally is; nil if the name
    /// doesn't make a host name.
    public static func defaultAPIURL(for name: String) -> URL? {
        let name = name.trimmingCharacters(in: .whitespaces).lowercased()
        let allowed = name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
        guard !name.isEmpty, allowed, !name.hasPrefix("."), !name.hasSuffix(".") else { return nil }
        return URL(string: "https://rapi.\(name).internal")
    }
}

/// The SF Symbols a server can have, to tell servers apart at a glance.
public enum ServerIcon: String, CaseIterable, Sendable {
    case serverRack = "server.rack"
    case xserve = "xserve"
    case nas = "externaldrive.connected.to.line.below"
    case drive = "externaldrive"
    case macMini = "macmini"
    case pc = "pc"
    case desktop = "desktopcomputer"
    case laptop = "laptopcomputer"
    case cpu = "cpu"
    case memory = "memorychip"
    case containers = "shippingbox"
    case cube = "cube"
    case media = "film"
    case music = "music.note"
    case photos = "photo"
    case home = "house"
    case security = "lock.shield"
    case network = "network"
    case router = "wifi.router"
    case antenna = "antenna.radiowaves.left.and.right"
    case power = "bolt"
    case games = "gamecontroller"
    case printer = "printer"
    case tv = "tv"
    case cloud = "cloud"
    case archive = "archivebox"
    case terminal = "terminal"
    case web = "globe"
    case mail = "envelope"
    case library = "books.vertical"
    case brain = "brain"
    case lab = "flask"

    public var symbolName: String { rawValue }

    /// A name for the picker and for VoiceOver.
    public var label: String {
        switch self {
        case .serverRack: "Server rack"
        case .xserve: "Rack server"
        case .nas: "NAS"
        case .drive: "Drive"
        case .macMini: "Mac mini"
        case .pc: "PC"
        case .desktop: "Desktop"
        case .laptop: "Laptop"
        case .cpu: "Processor"
        case .memory: "Memory"
        case .containers: "Containers"
        case .cube: "Cube"
        case .media: "Media"
        case .music: "Music"
        case .photos: "Photos"
        case .home: "Home"
        case .security: "Security"
        case .network: "Network"
        case .router: "Router"
        case .antenna: "Radio"
        case .power: "Power"
        case .games: "Games"
        case .printer: "Printer"
        case .tv: "TV"
        case .cloud: "Cloud"
        case .archive: "Archive"
        case .terminal: "Terminal"
        case .web: "Web"
        case .mail: "Mail"
        case .library: "Library"
        case .brain: "AI"
        case .lab: "Lab"
        }
    }
}

extension Server {
    /// Servers saved before `alwaysOn` existed come without it: they aren't always on. Those saved
    /// before roosters, in format 1, have the ID of their box, which becomes their rooster.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let box = try decoder.container(keyedBy: FormatOneKeys.self).decodeIfPresent(UUID.self, forKey: .boxID)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  apiURL: try container.decode(URL.self, forKey: .apiURL),
                  certificatePin: try container.decodeIfPresent(CertificatePin.self, forKey: .certificatePin),
                  rooster: try container.decodeIfPresent(Rooster.self, forKey: .rooster) ?? box.map(Rooster.box),
                  mac: try container.decodeIfPresent(MACAddress.self, forKey: .mac),
                  icon: try container.decode(ServerIcon.self, forKey: .icon),
                  color: try container.decode(ServerColor.self, forKey: .color),
                  alwaysOn: try container.decodeIfPresent(Bool.self, forKey: .alwaysOn) ?? false)
    }

    private enum FormatOneKeys: String, CodingKey {
        case boxID
    }
}

extension ServerIcon: Codable {
    /// An icon this version doesn't know, from a newer one, becomes the server rack.
    public init(from decoder: Decoder) throws {
        self = ServerIcon(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .serverRack
    }
}

/// The tint of a server's icon; the apps turn it into a SwiftUI color.
public enum ServerColor: String, CaseIterable, Sendable {
    case blue, teal, green, mint, yellow, orange, red, pink, purple, indigo, brown, gray
}

extension ServerColor: Codable {
    /// A color this version doesn't know, from a newer one, becomes blue.
    public init(from decoder: Decoder) throws {
        self = ServerColor(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .blue
    }
}
