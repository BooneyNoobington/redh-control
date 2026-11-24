import Foundation
import Testing
@testable import RedhKit

struct RedhAPIClientTests {
    let network = FakeNetwork()
    let root = Data([1, 2, 3])
    let server = Server(name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!)
    var client: RedhAPIClient {
        RedhAPIClient(rootCertificate: root, transport: network.transport)
    }

    @Test func readsTheStatusAsTheContractShowsIt() async throws {
        let example = try statusExample()
        await network.reply { _ in (200, ["Content-Type": "application/json"], example) }
        let status = try await client.status(of: server, token: "t0ken")
        #expect(status == ServerStatus(name: "SERVER", version: "0.2.0", bootID: "10ae18e3-9be7-42df-a9d2-9ecd0c34bf0d",
                                       uptimeSeconds: 273813, shutdown: ShutdownStatus(ready: true),
                                       wake: WakeStatus(broadcast: "255.255.255.255", port: 9)))
        let sent = try #require(await network.sent.last)
        #expect(sent.request.url?.absoluteString == "https://rapi.lab.internal/v1/status")
        #expect(sent.request.httpMethod == "GET")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        #expect(sent.policy == .root(root))
    }

    @Test func aPairedServerIsTrustedByItsPinAlone() async throws {
        let example = try statusExample()
        await network.reply { _ in (200, [:], example) }
        let pin = try #require(CertificatePin(String(repeating: "cd", count: 32)))
        let paired = Server(name: "lab", apiURL: URL(string: "https://192.0.2.16:8470")!, certificatePin: pin)
        _ = try await RedhAPIClient(rootCertificate: nil, transport: network.transport).status(of: paired, token: "t0ken")
        #expect(await network.sent.last?.policy == .pinned(pin))
        #expect(await network.sent.last?.request.url?.absoluteString == "https://192.0.2.16:8470/v1/status")
    }

    @Test func withoutPinOrRootNothingIsSent() async throws {
        await #expect(throws: TransportError.untrusted(reason: "The setup has no root certificate for RedhAPI.", presented: nil)) {
            _ = try await RedhAPIClient(rootCertificate: nil, transport: network.transport).status(of: server, token: "t0ken")
        }
        #expect(await network.sent.isEmpty)
    }

    @Test func readsTheSystemAsTheContractShowsIt() async throws {
        let example = try fixture("system.json")
        await network.reply { _ in (200, [:], example) }
        let report = try await client.system(of: server, token: "t0ken")
        #expect(report.cpu == SystemReport.CPU(count: 8, usagePercent: 7.3, load: [0.42, 0.38, 0.35], pressurePercent: 1.25))
        #expect(report.temperature == SystemReport.Temperature(celsius: 46, sensor: "coretemp: Package id 0"))
        #expect(report.power == SystemReport.Power(watts: 12.4, sensor: "package-0", problem: nil))
        #expect(report.memory == SystemReport.Memory(totalBytes: 16_384_000_000, availableBytes: 9_216_000_000, pressurePercent: 0))
        #expect(report.disks.map(\.path) == ["/", "/srv/data"])
        let sent = try #require(await network.sent.last)
        #expect(sent.request.url?.absoluteString == "https://rapi.lab.internal/v1/system")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
    }

    @Test func aMachineThatSaysNothing() async throws {
        let empty = json("""
            {"cpu": {"count": null, "usage_percent": null, "load": null, "pressure_percent": null},
            "temperature": {"celsius": null, "sensor": null},
            "power": {"watts": null, "sensor": null, "problem": "There is no energy counter (RAPL) for the processor."},
            "memory": {"total_bytes": null, "available_bytes": null, "pressure_percent": null},
            "swap": {"total_bytes": null, "free_bytes": null}, "disks": []}
            """)
        await network.reply { _ in (200, [:], empty) }
        let report = try await client.system(of: server, token: "t0ken")
        #expect(report.meters().isEmpty)
        #expect(report.notes.isEmpty)
    }

    @Test func aStatusBeforeVersionTwoCantWake() async throws {
        let old = json(#"{"name": "lab", "version": "0.1.0", "shutdown": {"ready": true, "problem": null, "pending": false, "last_error": null}}"#)
        await network.reply { _ in (200, [:], old) }
        #expect(try await client.status(of: server, token: "t0ken").wake == nil)
    }

    @Test func readsTheAppsAsTheContractShowsThem() async throws {
        let example = try fixture("apps.json")
        await network.reply { _ in (200, [:], example) }
        let listing = try await client.apps(of: server, token: "t0ken")
        #expect(listing.root == "/opt/podman")
        #expect(listing.apps == [AppsListing.Entry(name: "nextcloud", layout: "quadlet/", units: 3, services: 2, active: 2,
                                                   running: 1, installed: "in sync", caddy: 1)])
        #expect(listing.containers?.running == 2)
        #expect(listing.containers?.inNoApp.map(\.name) == ["scratch"])
        #expect(listing.containers?.inNoApp.first?.unit == nil)
        #expect(listing.warnings.isEmpty)
        let sent = try #require(await network.sent.last)
        #expect(sent.request.url?.absoluteString == "https://rapi.lab.internal/v1/apps")
        #expect(sent.request.timeoutInterval == 30)
    }

    @Test func appsWithoutRedhManager() async throws {
        let body = json(#"{"error": {"code": "apps_unavailable", "message": "/usr/local/bin/redh does not exist; redh-manager isn't installed"}}"#)
        await network.reply { _ in (409, [:], body) }
        await #expect(throws: RedhAPIError.appsUnavailable("/usr/local/bin/redh does not exist; redh-manager isn't installed")) {
            try await client.apps(of: server, token: "t0ken")
        }
    }

    @Test func shutsDown() async throws {
        await network.reply { _ in (202, [:], json(#"{"accepted": true, "delay_seconds": 2.0}"#)) }
        #expect(try await client.shutdown(server, token: "t0ken") == ShutdownAccepted(accepted: true, delaySeconds: 2))
        let request = try #require(await network.sent.last?.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/v1/shutdown")
        #expect(request.httpBody == nil)
    }

    @Test func healthNeedsNoToken() async throws {
        await network.reply { _ in (200, [:], json(#"{"status": "ok"}"#)) }
        try await client.health(of: server)
        let request = try #require(await network.sent.last?.request)
        #expect(request.url?.path() == "/health")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func healthFromSomethingElse() async throws {
        await network.reply { _ in (200, [:], json("<html>It works!</html>")) }
        await #expect(throws: RedhAPIError.unreadable("/health doesn't say ok")) {
            try await client.health(of: server)
        }
    }

    @Test(arguments: [
        (401, #"{"error": {"code": "unauthorized", "message": "This needs a valid bearer token."}}"#,
         RedhAPIError.unauthorized),
        (409, #"{"error": {"code": "shutdown_unavailable", "message": "/usr/local/bin/redh-shut does not exist"}}"#,
         RedhAPIError.shutdownUnavailable("/usr/local/bin/redh-shut does not exist")),
        (502, "", RedhAPIError.notRunning(status: 502)),
        (404, #"{"error": {"code": "not_found", "message": "There is no /v1/x here."}}"#,
         RedhAPIError.answer(status: 404, code: "not_found", message: "There is no /v1/x here.")),
        (500, "<html>", RedhAPIError.answer(status: 500, code: nil, message: nil)),
    ])
    func errors(status: Int, body: String, error: RedhAPIError) async throws {
        await network.reply { _ in (status, [:], json(body)) }
        await #expect(throws: error) {
            try await client.shutdown(server, token: "t0ken")
        }
    }

    @Test func aStatusWithoutItsFields() async throws {
        await network.reply { _ in (200, [:], json(#"{"name": "lab"}"#)) }
        await #expect(throws: RedhAPIError.unreadable("'version' is missing")) {
            try await client.status(of: server, token: "t0ken")
        }
    }
}
