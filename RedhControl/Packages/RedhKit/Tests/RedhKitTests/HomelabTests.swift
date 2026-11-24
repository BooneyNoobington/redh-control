import Foundation
import Testing
@testable import RedhKit

struct HomelabTests {
    let network = FakeNetwork()
    let boxID = UUID()
    let serverID = UUID()

    var server: Server {
        Server(id: serverID, name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!, rooster: .box(boxID),
               mac: MACAddress("aa:bb:cc:dd:ee:ff"))
    }

    var setup: Setup {
        Setup(boxes: [Box(id: boxID, name: "lab-box", host: "fritz.lab.internal", username: "redh-control",
                          certificatePin: CertificatePin(String(repeating: "ab", count: 32)))],
              servers: [server], rootCertificate: Data([1, 2, 3]))
    }

    func homelab(_ secrets: [SecretKey: String], setup: Setup? = nil) -> Homelab {
        Homelab(setup: setup ?? self.setup, secrets: MemorySecretStore(secrets), transport: network.transport) { "0a4f113b" }
    }

    /// A box that wants the digest login of FritzBoxClientTests, then answers with the fixture.
    static func box(_ body: Data, status: Int = 200) -> @Sendable (URLRequest) -> Reply {
        { request in
            request.value(forHTTPHeaderField: "Authorization") == FritzBoxClientTests.answer
                ? (status, [:], body) : (401, ["WWW-Authenticate": FritzBoxClientTests.challenge], Data())
        }
    }

    @Test func withATokenItAsksForTheStatus() async throws {
        let example = try statusExample()
        await network.reply { _ in (200, [:], example) }
        let probe = await homelab([.token(server: serverID): "t0ken"]).probe(server)
        guard case .status = probe.api else {
            Issue.record("no status but \(probe.api)")
            return
        }
        #expect(probe.rooster == .notAsked)
        #expect(await network.sent.count == 1)
    }

    @Test func withoutATokenItAsksForHealth() async throws {
        await network.reply { _ in (200, [:], json(#"{"status": "ok"}"#)) }
        #expect(await homelab([:]).probe(server) == Probe(api: .noAccess("There's no token for lab."), rooster: .notAsked))
        #expect(await network.sent.last?.request.url?.path() == "/health")
    }

    @Test func whenRedhAPIIsSilentTheBoxIsAsked() async throws {
        let box = Self.box(try fixture("host-entry.xml"))
        await network.reply { request in
            if request.url?.host() == "rapi.lab.internal" {
                throw TransportError.unreachable("timed out")
            }
            return box(request)
        }
        let probe = await homelab([.token(server: serverID): "t0ken", .password(box: boxID): "secret"]).probe(server)
        #expect(probe == Probe(api: .unreachable("timed out"), rooster: .active))
        #expect(probe.reading(command: nil).state == .probablyUp)
    }

    @Test func noPasswordNoBox() async {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        let probe = await homelab([.token(server: serverID): "t0ken"]).probe(server)
        #expect(probe.rooster == .unavailable("There's no password for the FRITZ!Box lab-box."))
    }

    @Test func noRootCertificateNoTrust() async {
        var setup = self.setup
        setup.rootCertificate = nil
        let probe = await homelab([:], setup: setup).probe(server)
        #expect(probe.api == .untrusted("The setup has no root certificate for RedhAPI."))
        #expect(await network.sent.isEmpty)
    }

    @Test func shuttingDownNeedsAToken() async {
        await #expect(throws: HomelabError.noToken(server: "lab")) {
            try await homelab([:]).shutDown(server)
        }
    }

    @Test func wakingGoesThroughTheBox() async throws {
        await network.reply(Self.box(try fixture("wake.xml")))
        try await homelab([.password(box: boxID): "secret"]).wake(server)
        #expect(await network.sent.last?.request.value(forHTTPHeaderField: "SOAPAction")
                == "urn:dslforum-org:service:Hosts:1#X_AVM-DE_WakeOnLANByMACAddress")
    }

    @Test func wakingNeedsARooster() async {
        var loner = server
        loner.rooster = nil
        await #expect(throws: HomelabError.noRooster(server: "lab")) {
            try await homelab([:]).wake(loner)
        }
        loner.rooster = .server(UUID())  // a server that has gone from the setup
        await #expect(throws: HomelabError.noRooster(server: "lab")) {
            try await homelab([:]).wake(loner)
        }
    }

    @Test func aBoxThatKnowsTheMACAddressCanWakeItAgain() async throws {
        await network.reply(Self.box(try fixture("host-entry.xml")))
        #expect(await homelab([.password(box: boxID): "secret"]).wakeCheck(server)
                == .possible("The FRITZ!Box lab-box knows its MAC address and can wake it up again."))
    }

    @Test func aBoxThatDoesntKnowItCant() async throws {
        await network.reply(Self.box(try fixture("fault-714.xml"), status: 500))
        #expect(await homelab([.password(box: boxID): "secret"]).wakeCheck(server)
                == .uncertain("The FRITZ!Box lab-box doesn't know its MAC address, so it can't wake it up again."))
    }

    @Test func withoutRoosterMACAddressOrPasswordNothingIsAsked() async {
        var loner = server
        loner.rooster = nil
        #expect(await homelab([:]).wakeCheck(loner)
                == .uncertain("It has no rooster, so nothing can wake it up again."))
        var unknown = server
        unknown.mac = nil
        #expect(await homelab([:]).wakeCheck(unknown) == .uncertain("Without its MAC address, nothing can wake it up again."))
        #expect(await homelab([:]).wakeCheck(server)
                == .uncertain("There's no password for the FRITZ!Box lab-box, so it can't wake it up again."))
        #expect(await network.sent.isEmpty)
    }

    @Test func aBoxThatCantBeAskedLeavesItUncertain() async {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        guard case .uncertain(let why) = await homelab([.password(box: boxID): "secret"]).wakeCheck(server) else {
            Issue.record("not uncertain")
            return
        }
        #expect(why.hasPrefix("The FRITZ!Box lab-box can't say whether it could wake it up: "))
    }
}

/// A rooster that is another server: nas wakes backup up, through its RedhAPI.
struct RoosterServerTests {
    let network = FakeNetwork()
    let nas = Server(name: "nas", apiURL: URL(string: "https://rapi.nas.internal")!)
    let backup: Server
    let setup: Setup

    init() {
        backup = Server(name: "backup", apiURL: URL(string: "https://rapi.backup.internal")!, rooster: .server(nas.id),
                        mac: MACAddress("aa:bb:cc:dd:ee:04"))
        setup = Setup(servers: [nas, backup], rootCertificate: Data([1, 2, 3]))
    }

    func homelab(_ secrets: [SecretKey: String]? = nil) -> Homelab {
        Homelab(setup: setup, secrets: MemorySecretStore(secrets ?? [.token(server: nas.id): "nas-t0ken"]),
                transport: network.transport)
    }

    func status(wake: Bool) -> Data {
        let version = wake ? "0.2.0" : "0.1.0"
        let extra = wake ? #", "wake": {"broadcast": "255.255.255.255", "port": 9}"# : ""
        return json(#"{"name": "nas", "version": "\#(version)", "shutdown": {"ready": true, "problem": null, "pending": false, "last_error": null}\#(extra)}"#)
    }

    @Test func itWakesThroughTheRoostersRedhAPI() async throws {
        await network.reply { _ in (200, [:], json(#"{"sent": true, "mac": "AA:BB:CC:DD:EE:04"}"#)) }
        try await homelab().wake(backup)
        let request = try #require(await network.sent.last?.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://rapi.nas.internal/v1/wake")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer nas-t0ken")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["mac": "AA:BB:CC:DD:EE:04"])
    }

    @Test func itNeedsTheRoostersToken() async {
        await #expect(throws: HomelabError.noToken(server: "nas")) {
            try await homelab([.token(server: backup.id): "backup-t0ken"]).wake(backup)
        }
        #expect(await network.sent.isEmpty)
    }

    @Test func aRoosterThatDoesntAnswerSaysToWakeItFirst() async {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        await #expect(throws: HomelabError.roosterNotUp(rooster: "nas", server: "backup")) {
            try await homelab().wake(backup)
        }
        #expect(HomelabError.roosterNotUp(rooster: "nas", server: "backup").localizedDescription
                == "nas wakes backup up, but doesn't answer now. Wake nas up first.")
    }

    @Test func anOlderRedhAPICantWake() async {
        await network.reply { _ in (404, [:], json(#"{"error": {"code": "not_found", "message": "There is no /v1/wake here."}}"#)) }
        await #expect(throws: HomelabError.roosterCantWake(rooster: "nas")) {
            try await homelab().wake(backup)
        }
    }

    @Test func aPacketThatCantBeSentSaysWhy() async {
        let message = "The magic packet for AA:BB:CC:DD:EE:04 couldn't be sent to 255.255.255.255:9: Network is unreachable"
        await network.reply { _ in (409, [:], json(#"{"error": {"code": "wake_failed", "message": "\#(message)"}}"#)) }
        await #expect(throws: RedhAPIError.wakeFailed(message)) {
            try await homelab().wake(backup)
        }
    }

    @Test func aSilentServerWhoseRoosterAnswersIsProbablyDown() async {
        await network.reply { request in
            if request.url?.host() == "rapi.backup.internal" {
                throw TransportError.unreachable("timed out")
            }
            return (200, [:], json(#"{"status": "ok"}"#))
        }
        let probe = await homelab().probe(backup)
        #expect(probe.rooster == .answers("nas"))
        #expect(probe.reading(command: nil)
                == Reading(state: .probablyDown, detail: "RedhAPI doesn't answer, while its rooster nas does."))
    }

    @Test func whenNeitherAnswersItsUnknown() async {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        let probe = await homelab().probe(backup)
        #expect(probe.rooster == .notAsked)
        #expect(probe.reading(command: nil) == Reading(state: .unknown, detail: "RedhAPI doesn't answer: timed out"))
    }

    @Test func aRoosterThatIsUpCanWakeItAgain() async {
        let status = status(wake: true)
        await network.reply { _ in (200, [:], status) }
        #expect(await homelab().wakeCheck(backup) == .possible("Its rooster nas is up and can wake it up again."))
    }

    @Test func aRoosterWithAnOlderRedhAPICant() async {
        let status = status(wake: false)
        await network.reply { _ in (200, [:], status) }
        #expect(await homelab().wakeCheck(backup)
                == .uncertain("Its rooster nas has RedhAPI 0.1.0, which can't wake servers yet."))
    }

    @Test func aRoosterThatDoesntAnswerCantWakeItAgainNow() async {
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        #expect(await homelab().wakeCheck(backup)
                == .uncertain("Its rooster nas doesn't answer, so it couldn't wake it up again now."))
    }
}
