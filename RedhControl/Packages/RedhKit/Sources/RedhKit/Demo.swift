import Foundation

/// A made-up homelab for previews, screenshots and the apps' `-demo` launch argument: one box,
/// five servers in different states, answered without any network. The box is the rooster of all
/// servers but backup, whose rooster is nas.
public enum Demo {
    static let box = Box(id: UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!, name: "lab-box",
                         host: "fritz.lab.internal", fallbackAddress: "192.0.2.1", username: "redh-control",
                         certificatePin: CertificatePin(String(repeating: "ab", count: 32)))

    static let servers = [
        server(2, "nas", .nas, .teal, mac: "AA:BB:CC:00:00:02", alwaysOn: true),
        server(3, "media", .media, .purple, mac: "AA:BB:CC:00:00:03"),
        server(4, "backup", .archive, .orange, mac: "AA:BB:CC:00:00:04", rooster: .server(id(2))),
        server(5, "pi", .cpu, .red, mac: "AA:BB:CC:00:00:05"),
        server(6, "lab", .lab, .green, mac: "AA:BB:CC:00:00:06", address: "https://192.0.2.16:8470",
               pin: CertificatePin(String(repeating: "cd", count: 32))),
    ]

    /// "Lab Root CA", a certificate made for the demo; its key was thrown away.
    static let root = Data(base64Encoded: "MIIBcDCCARagAwIBAgIUG1jlfbWh3B8jUMLWn6NyV7l+TMYwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLTGFiIFJvb3QgQ0EwHhcNMjYwMTAxMDAwMDAwWhcNNDYwMTAxMDAwMDAwWjAWMRQwEgYDVQQDDAtMYWIgUm9vdCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABAvkH3dQQyYvdCXv3VEt0BrkrliRVWslm35j6EJc20fbaozRwo3vGJP00BN7eLINH+DqbPcqXK3bk2haJw3SdFOjQjBAMB0GA1UdDgQWBBRzGlcJ8kHUCmAF75KLjPoHfxiYcDAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQDAgNIADBFAiEAp6RfKsZEqciRjv3BC9F6pvFO9gtMmAdsbnulpiph8K8CIB9hEP5ZFdhtORLg0BNwWBWOQtRnv6n/qNTbjkJLhZuG")!

    public static let setup = Setup(boxes: [box], servers: servers, rootCertificate: root)

    public static func secrets() -> MemorySecretStore {
        var secrets: [SecretKey: String] = [.password(box: box.id): "demo"]
        for server in servers {
            secrets[.token(server: server.id)] = "demo"
        }
        return MemorySecretStore(secrets)
    }

    @MainActor
    public static func monitor() -> Monitor {
        Monitor(setup: setup, secrets: secrets(), file: nil, transport: transport)
    }

    /// RedhAPI and the box as the demo has them:
    /// - nas: up for 12 days, ready to shut down, and always on; three apps; wakes backup up; a
    ///   quiet machine;
    /// - media: up, but its sudo rule is missing, and it has no redh-manager; a busy machine, nearly
    ///   full, whose energy counter only root may read;
    /// - backup: down, while nas, its rooster, answers;
    /// - pi: Caddy answers, RedhAPI doesn't;
    /// - lab: paired with RedhAPI's own certificate, at an IP address; RedhAPI doesn't answer, but
    ///   the box sees it.
    public static let transport: Transport = { request, _ in
        let url = request.url!
        let reply: (Int, String)
        switch (url.host(), url.path()) {
        case ("rapi.nas.internal", "/health"):
            reply = (200, #"{"status": "ok"}"#)
        case ("rapi.nas.internal", "/v1/status"):
            reply = (200, status(uptime: 1_049_000, shutdown: #"{"ready": true, "problem": null, "pending": false, "last_error": null}"#))
        case ("rapi.nas.internal", "/v1/shutdown"):
            reply = (202, #"{"accepted": true, "delay_seconds": 2.0}"#)
        case ("rapi.nas.internal", "/v1/apps"):
            reply = (200, apps)
        case ("rapi.nas.internal", "/v1/wake"):
            reply = (200, #"{"sent": true, "mac": "AA:BB:CC:00:00:04"}"#)
        case ("rapi.nas.internal", "/v1/system"):
            reply = (200, nasSystem)
        case ("rapi.media.internal", "/v1/system"):
            reply = (200, mediaSystem)
        case ("rapi.media.internal", "/v1/apps"):
            reply = (409, #"{"error": {"code": "apps_unavailable", "message": "/usr/local/bin/redh does not exist; redh-manager isn't installed"}}"#)
        case ("rapi.media.internal", "/v1/status"):
            reply = (200, status(uptime: 309_000, shutdown: #"{"ready": false, "problem": "sudo does not let redh-api run /usr/local/bin/redh-shut without a password (sudo: a password is required)", "pending": false, "last_error": null}"#))
        case ("rapi.pi.internal", _):
            reply = (502, "")
        case ("fritz.lab.internal", _):
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let active = body.contains("AA:BB:CC:00:00:06") ? "1" : "0"
            reply = (200, """
                <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
                <u:Response xmlns:u="urn:dslforum-org:service:Hosts:1"><NewActive>\(active)</NewActive></u:Response>\
                </s:Body></s:Envelope>
                """)
        default:
            throw TransportError.unreachable("The request timed out.")
        }
        return (Data(reply.1.utf8), HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }

    /// Behind Caddy at `rapi.NAME.internal`, or, with an address and a pin, paired with RedhAPI's own
    /// certificate.
    private static func server(_ number: Int, _ name: String, _ icon: ServerIcon, _ color: ServerColor,
                               mac: String, alwaysOn: Bool = false, rooster: Rooster = .box(box.id),
                               address: String? = nil, pin: CertificatePin? = nil) -> Server {
        Server(id: id(number), name: name, apiURL: address.flatMap(URL.init(string:)) ?? Server.defaultAPIURL(for: name)!,
               certificatePin: pin, rooster: rooster, mac: MACAddress(mac), icon: icon, color: color, alwaysOn: alwaysOn)
    }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: "D0000000-0000-4000-8000-00000000000\(number)")!
    }

    /// The nas's apps, as redh-manager lists them: one is behind its sources, and a container runs
    /// outside every app.
    private static let apps = """
        {"root": "/opt/podman", "apps": [
        {"name": "nextcloud", "layout": "quadlet/", "units": 3, "services": 2, "active": 2, "running": 1, "installed": "in sync", "caddy": 1},
        {"name": "vaultwarden", "layout": "quadlet/", "units": 1, "services": 1, "active": 1, "running": 1, "installed": "in sync", "caddy": 1},
        {"name": "bookstack", "layout": "quadlet/", "units": 3, "services": 2, "active": 1, "running": 1, "installed": "outdated", "caddy": 1}],
        "containers": {"running": 4, "in_no_app": [{"name": "scratch", "image": "docker.io/library/busybox:1", "unit": null}]},
        "warnings": []}
        """

    /// The nas's machine: the example in RedhAPI's README.
    private static let nasSystem = """
        {"cpu": {"count": 8, "usage_percent": 7.3, "load": [0.42, 0.38, 0.35], "pressure_percent": 1.25},
        "temperature": {"celsius": 46.0, "sensor": "coretemp: Package id 0"},
        "power": {"watts": 12.4, "sensor": "package-0", "problem": null},
        "memory": {"total_bytes": 16384000000, "available_bytes": 9216000000, "pressure_percent": 0.0},
        "swap": {"total_bytes": 4096000000, "free_bytes": 3584000000},
        "disks": [{"path": "/", "total_bytes": 249999998976, "free_bytes": 180999999488},
        {"path": "/srv/data", "total_bytes": 4000000000000, "free_bytes": 1619999997952}]}
        """

    /// The media server's machine: busy, short of memory and space, and without its energy counter.
    private static let mediaSystem = """
        {"cpu": {"count": 4, "usage_percent": 63.5, "load": [3.12, 2.75, 2.40], "pressure_percent": 4.2},
        "temperature": {"celsius": 71.5, "sensor": "k10temp: Tctl"},
        "power": {"watts": null, "sensor": "package-0", "problem": "Only root may read /sys/class/powercap/intel-rapl:0/energy_uj; RedhAPI's README says how to let RedhAPI read it."},
        "memory": {"total_bytes": 8250000000, "available_bytes": 1650000000, "pressure_percent": 0.4},
        "swap": {"total_bytes": 2147479552, "free_bytes": 1073741824},
        "disks": [{"path": "/", "total_bytes": 999000000000, "free_bytes": 105000000000}]}
        """

    private static func status(uptime: Int, shutdown: String) -> String {
        #"{"name": "demo", "version": "0.2.0", "boot_id": "6a1f0c52-8d1e-4f3b-9c0e-5b2a7d4e9f10", "uptime_seconds": \#(uptime), "shutdown": \#(shutdown), "wake": {"broadcast": "255.255.255.255", "port": 9}}"#
    }
}
