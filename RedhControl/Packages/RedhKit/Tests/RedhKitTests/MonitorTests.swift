import Foundation
import Testing
@testable import RedhKit

#if canImport(AppKit)
import AppKit
#endif

@MainActor
struct MonitorTests {
    let network = FakeNetwork()
    let clock = Clock()
    let server = Server(name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!)
    let ready = #"{"name": "lab", "version": "0.1.0", "uptime_seconds": 60, "shutdown": {"ready": true, "problem": null, "pending": false, "last_error": null}}"#

    /// Time for the tests, moved on by hand.
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    func monitor(file: SetupFile? = nil) -> Monitor {
        let clock = clock
        return Monitor(setup: Setup(servers: [server], rootCertificate: Data([1])),
                       secrets: MemorySecretStore([.token(server: server.id): "t0ken"]), file: file,
                       transport: network.transport, now: { clock.now })
    }

    @Test func refreshLooksAtEveryServer() async throws {
        let ready = json(ready)
        await network.reply { _ in (200, [:], ready) }
        let monitor = monitor()
        #expect(monitor.readings.isEmpty)
        await monitor.refresh()
        #expect(monitor.readings[server.id]?.canShutDown == true)
        #expect(monitor.lastRefresh == clock.now)
        #expect(!monitor.isRefreshing)
    }

    @Test func aShutdownWaitsUntilTheServerIsGone() async throws {
        let ready = json(ready)
        await network.reply { request in
            request.url?.path() == "/v1/shutdown" ? (202, [:], json(#"{"accepted": true, "delay_seconds": 2}"#)) : (200, [:], ready)
        }
        let monitor = monitor()
        try await monitor.shutDown(server)
        #expect(monitor.readings[server.id]?.state == .shuttingDown)
        #expect(monitor.isWaiting)

        clock.now += 5
        await monitor.refresh()
        #expect(monitor.readings[server.id]?.state == .shuttingDown)

        await network.reply { _ in throw TransportError.unreachable("timed out") }
        clock.now += Guess.shutdownTimeout
        await monitor.refresh()
        #expect(monitor.readings[server.id]?.state == .probablyDown)
        #expect(!monitor.isWaiting)
    }

    @Test func changesAreSaved() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "RedhKitTests-\(UUID().uuidString)/setup.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let monitor = monitor(file: SetupFile(url: url))
        var renamed = server
        renamed.name = "lab2"
        try monitor.save(renamed, token: nil)
        try monitor.save(Box(name: "lab-box", host: "fritz.lab.internal", username: "redh-control"), password: "secret")
        let saved = try SetupFile(url: url).load()
        #expect(saved.servers.map(\.name) == ["lab2"])
        #expect(saved.boxes.map(\.name) == ["lab-box"])
        #expect(monitor.hasSecret(.token(server: server.id)))
    }

    @Test func removingABoxFreesItsServersAndForgetsItsPassword() throws {
        let monitor = monitor()
        let box = Box(name: "lab-box", host: "fritz.lab.internal", username: "redh-control")
        try monitor.save(box, password: "secret")
        var server = server
        server.rooster = .box(box.id)
        try monitor.save(server, token: nil)
        try monitor.remove(box)
        #expect(monitor.setup.boxes.isEmpty)
        #expect(monitor.setup.servers.first?.rooster == nil)
        #expect(!monitor.hasSecret(.password(box: box.id)))
    }

    @Test func removingAServerFreesTheServersItWoke() throws {
        let monitor = monitor()
        let backup = Server(name: "backup", apiURL: URL(string: "https://rapi.backup.internal")!, rooster: .server(server.id))
        try monitor.save(backup, token: nil)
        try monitor.remove(server)
        #expect(monitor.setup.servers.map(\.name) == ["backup"])
        #expect(monitor.setup.servers.first?.rooster == nil)
    }

    @Test func aRoosterThatDidntAnswerIsReportedAtOnce() async throws {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        let monitor = monitor()
        let backup = Server(name: "backup", apiURL: URL(string: "https://rapi.backup.internal")!, rooster: .server(server.id),
                            mac: MACAddress("aa:bb:cc:dd:ee:04"))
        try monitor.save(backup, token: nil)
        await monitor.refresh()
        let looks = await network.sent.count
        await #expect(throws: HomelabError.roosterNotUp(rooster: "lab", server: "backup")) {
            try await monitor.wake(backup)
        }
        #expect(await network.sent.count == looks)
    }

    @Test func removingAServerForgetsItsReadingAndToken() async throws {
        let ready = json(ready)
        await network.reply { _ in (200, [:], ready) }
        let monitor = monitor()
        await monitor.refresh()
        try monitor.remove(server)
        #expect(monitor.readings.isEmpty)
        #expect(!monitor.hasSecret(.token(server: server.id)))
    }

    @Test func wakingAgainStartsTheWaitAnew() async throws {
        let box = Box(name: "lab-box", host: "fritz.lab.internal", username: "redh-control",
                      certificatePin: CertificatePin(String(repeating: "ab", count: 32)))
        let sleeper = Server(name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!, rooster: .box(box.id),
                             mac: MACAddress("aa:bb:cc:dd:ee:ff"))
        let (wake, entry) = (try fixture("wake.xml"), try fixture("host-entry.xml"))
        await network.reply { request in
            if request.url?.host() == "rapi.lab.internal" {
                throw TransportError.unreachable("timed out")
            }
            guard request.value(forHTTPHeaderField: "Authorization") != nil else {
                return (401, ["WWW-Authenticate": FritzBoxClientTests.challenge], Data())
            }
            let waking = request.value(forHTTPHeaderField: "SOAPAction")?.hasSuffix("WakeOnLANByMACAddress") == true
            return (200, [:], waking ? wake : entry)
        }
        let clock = clock
        let monitor = Monitor(setup: Setup(boxes: [box], servers: [sleeper], rootCertificate: Data([1])),
                              secrets: MemorySecretStore([.password(box: box.id): "secret"]), file: nil,
                              transport: network.transport, now: { clock.now })
        try await monitor.wake(sleeper)
        clock.now += Guess.wakeTimeout - 60
        await monitor.refresh()
        #expect(monitor.readings[sleeper.id]?.canWake == true)
        #expect(monitor.readings[sleeper.id]?.wakeTitle == "Wake Up Again")

        try await monitor.wake(sleeper)
        clock.now += 120
        await monitor.refresh()
        #expect(monitor.readings[sleeper.id]?.state == .waking)  // the first wake-up alone would be over

        clock.now += Guess.wakeTimeout
        await monitor.refresh()
        #expect(monitor.readings[sleeper.id]?.state == .probablyUp)
    }
}

@MainActor
struct DemoTests {
    @Test func everyServerIsAsTheDemoSays() async {
        let monitor = Demo.monitor()
        await monitor.refresh()
        let states = Dictionary(uniqueKeysWithValues: monitor.setup.servers.map { ($0.name, monitor.readings[$0.id]) })
        #expect(monitor.setup.servers.filter(\.alwaysOn).map(\.name) == ["nas"])
        #expect(states["nas"]??.canShutDown == true)
        #expect(states["media"]??.tone == .up)
        #expect(states["media"]??.canShutDown == false)
        #expect(states["backup"]??.summary == "RedhAPI doesn't answer, while its rooster nas does.")
        #expect(states["backup"]??.state == .probablyDown)
        #expect(states["pi"]??.state == .upWithoutStatus)
        #expect(states["lab"]??.state == .probablyUp)
    }

    @Test func wakingAndShuttingDownWork() async throws {
        let monitor = Demo.monitor()
        let backup = try #require(monitor.setup.servers.first { $0.name == "backup" })
        let nas = try #require(monitor.setup.servers.first { $0.name == "nas" })
        await monitor.refresh()
        try await monitor.wake(backup)  // through nas, its rooster
        try await monitor.shutDown(nas)
        #expect(monitor.readings[backup.id]?.state == .waking)
        #expect(monitor.readings[nas.id]?.state == .shuttingDown)
        #expect(await monitor.wakeCheck(nas) == .possible("The FRITZ!Box lab-box knows its MAC address and can wake it up again."))
        #expect(await monitor.wakeCheck(backup) == .possible("Its rooster nas is up and can wake it up again."))
    }

    @Test func shuttingDownTheNasWarnsOfTheBackup() throws {
        let nas = try #require(Demo.setup.servers.first { $0.name == "nas" })
        #expect(Demo.setup.shutdownNote(for: nas)
                == "Only nas can wake backup up. Afterwards, the FRITZ!Box lab-box has to wake nas first.")
    }

    @Test func theNasHasAppsTheMediaServerHasNoRedhManager() async throws {
        let monitor = Demo.monitor()
        let nas = try #require(monitor.setup.servers.first { $0.name == "nas" })
        let media = try #require(monitor.setup.servers.first { $0.name == "media" })
        let listing = try await monitor.apps(of: nas)
        #expect(listing.apps.map(\.name) == ["nextcloud", "vaultwarden", "bookstack"])
        #expect(listing.containersSummary == "4 containers running, 1 of them in no app")
        await #expect(throws: RedhAPIError.appsUnavailable("/usr/local/bin/redh does not exist; redh-manager isn't installed")) {
            try await monitor.apps(of: media)
        }
    }
}

struct PresentationTests {
    let status = ServerStatus(name: "lab", version: "0.1.0", uptimeSeconds: 1_049_000, shutdown: ShutdownStatus(ready: true))

    @Test func summaries() {
        #expect(Reading(state: .up(status)).summary == "Running for 12 days")
        #expect(Reading(state: .up(status), detail: "The shutdown failed: disk busy").summary == "The shutdown failed: disk busy")
        #expect(Reading(state: .probablyDown).summary == "Neither RedhAPI nor the FRITZ!Box sees it.")
    }

    @Test func wakeTitles() {
        #expect(Reading(state: .probablyDown).wakeTitle == "Wake Up")
        #expect(Reading(state: .waking, command: .wake(since: Date())).wakeTitle == "Wake Up Again")
    }

    @Test func appsAsRedhListsThem() {
        let nextcloud = AppsListing.Entry(name: "nextcloud", layout: "quadlet/", units: 3, services: 2, active: 2,
                                          running: 1, installed: "in sync", caddy: 1)
        #expect((nextcloud.activeText, nextcloud.runningText) == ("2/2", "1"))
        #expect(nextcloud.summary == "2/2 active, 1 running, in sync")
        let sourcesOnly = AppsListing.Entry(name: "wiki", layout: "none", running: 0, installed: "no")
        #expect((sourcesOnly.activeText, sourcesOnly.runningText) == ("-", "-"))
        #expect(sourcesOnly.summary == "0 running, not installed")
        let unknown = AppsListing.Entry(name: "db", services: 1, active: nil, running: nil)
        #expect((unknown.activeText, unknown.runningText) == ("?", "?"))
        #expect(unknown.summary == "1 service, state unknown, running unknown")
    }

    @Test func containersAsRedhCountsThem() {
        var listing = AppsListing(root: "/opt/podman", apps: [], containers: nil, warnings: [])
        #expect(listing.containersSummary == "Podman can't say what runs.")
        listing.containers = AppsListing.Containers(running: 1, inNoApp: [])
        #expect(listing.containersSummary == "1 container running")
    }

    @Test func wakeCheckExplanations() {
        #expect(WakeCheck.possible("Its rooster nas is up and can wake it up again.").explanation
                == "Its rooster nas is up and can wake it up again.")
        #expect(WakeCheck.uncertain("Without its MAC address, nothing can wake it up again.").explanation
                == "Without its MAC address, nothing can wake it up again. It would have to be switched on by hand.")
    }

    @Test func shutdownNotes() throws {
        let box = Box(name: "lab-box", host: "fritz.lab.internal", username: "redh-control")
        let mac = MACAddress("aa:bb:cc:dd:ee:01")
        var nas = Server(name: "nas", apiURL: URL(string: "https://rapi.nas.internal")!, rooster: .box(box.id), mac: mac)
        let media = Server(name: "media", apiURL: URL(string: "https://rapi.media.internal")!, rooster: .server(nas.id), mac: mac)
        let backup = Server(name: "backup", apiURL: URL(string: "https://rapi.backup.internal")!, rooster: .server(nas.id))
        var setup = Setup(boxes: [box], servers: [nas, media], rootCertificate: nil)
        #expect(setup.shutdownNote(for: media) == "Its rooster nas can wake it up again.")
        #expect(setup.shutdownNote(for: nas)
                == "Only nas can wake media up. Afterwards, the FRITZ!Box lab-box has to wake nas first.")
        setup.servers.append(backup)
        #expect(setup.shutdownNote(for: backup) == "Without its MAC address, nothing can wake it up again.")
        nas.rooster = nil
        setup.servers[0] = nas
        #expect(setup.shutdownNote(for: nas) == "Only nas can wake media and backup up, and nothing can wake nas up again.")
        setup.boxes = []
        nas.rooster = .box(box.id)  // a box that has gone from the setup
        setup.servers[0] = nas
        #expect(setup.shutdownNote(for: nas) == "Only nas can wake media and backup up, and nothing can wake nas up again.")
        #expect(setup.shutdownNote(for: Server(name: "pi", apiURL: URL(string: "https://rapi.pi.internal")!))
                == "It has no rooster, so nothing can wake it up again.")
    }

    @Test func listsOfNames() {
        #expect(listed([]) == "")
        #expect(listed(["nas"]) == "nas")
        #expect(listed(["nas", "media"]) == "nas and media")
        #expect(listed(["nas", "media", "backup"]) == "nas, media and backup")
    }

    @Test func uptimes() {
        #expect([0, 59, 60, 119, 3_600, 7_200, 86_399, 86_400, 1_049_000].map(uptimeText)
                == ["less than a minute", "less than a minute", "1 minute", "1 minute", "1 hour", "2 hours",
                    "23 hours", "1 day", "12 days"])
    }

    #if canImport(AppKit)
    @Test(arguments: [ServerState.up(ServerStatus(name: "", version: "", shutdown: ShutdownStatus(ready: true))),
                      .upWithoutStatus, .probablyUp, .probablyDown, .unknown, .waking, .shuttingDown])
    func everyStateHasAnSFSymbol(_ state: ServerState) {
        #expect(NSImage(systemSymbolName: Reading(state: state).symbolName, accessibilityDescription: nil) != nil)
    }
    #endif
}

struct RootCertificateTests {
    @Test func readsPEM() throws {
        #expect(RootCertificate.der(from: try fixture("root.pem")) == (try fixture("root.der")))
    }

    @Test func takesDERAsItIs() throws {
        let der = try fixture("root.der")
        #expect(RootCertificate.der(from: der) == der)
    }

    @Test func refusesWhatIsNoCertificate() {
        #expect(RootCertificate.der(from: json("hello")) == nil)
        #expect(RootCertificate.der(from: json("-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----")) == nil)
    }

    @Test func namesTheSubject() throws {
        #expect(RootCertificate.summary(of: try fixture("root.der")) == "RedhKit Test Root")
    }
}
