import Foundation
import Testing
@testable import RedhKit

@MainActor
struct WatchSyncTests {
    let box = Box(name: "lab-box", host: "fritz.lab.internal", username: "redh-control")
    let server = Server(name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!)

    /// The iPhone's side: a setup with a token and a password.
    func phone() -> (Setup, MemorySecretStore) {
        var server = server
        server.rooster = .box(box.id)
        let setup = Setup(boxes: [box], servers: [server], rootCertificate: Data([1]))
        return (setup, MemorySecretStore([.token(server: server.id): "t0ken", .password(box: box.id): "secret"]))
    }

    @Test func carriesTheSetupAndItsSecrets() throws {
        let (setup, secrets) = phone()
        let sync = try WatchSync(setup: setup, secrets: secrets)
        #expect(sync.tokens == [server.id: "t0ken"])
        #expect(sync.passwords == [box.id: "secret"])
        #expect(try WatchSync(data: sync.data()) == sync)
    }

    @Test func putsItIntoPlaceOnTheWatch() throws {
        let (setup, secrets) = phone()
        let watch = Monitor(setup: Setup(), secrets: MemorySecretStore(), file: nil)
        try WatchSync(setup: setup, secrets: secrets).apply(to: watch)
        #expect(watch.setup == setup)
        #expect(try watch.secrets.secret(for: .token(server: server.id)) == "t0ken")
        #expect(try watch.secrets.secret(for: .password(box: box.id)) == "secret")
    }

    @Test func whatWentAwayOnTheiPhoneGoesOnTheWatch() throws {
        let (setup, secrets) = phone()
        let watch = Monitor(setup: Setup(), secrets: MemorySecretStore(), file: nil)
        try WatchSync(setup: setup, secrets: secrets).apply(to: watch)
        try WatchSync(setup: Setup(rootCertificate: Data([1])), secrets: secrets).apply(to: watch)
        #expect(watch.setup.servers.isEmpty)
        #expect(!watch.hasSecret(.token(server: server.id)))
        #expect(!watch.hasSecret(.password(box: box.id)))
    }

    @Test func theSameSetupAgainKeepsTheReadings() async throws {
        let (setup, secrets) = phone()
        let network = FakeNetwork()
        await network.reply { _ in throw TransportError.unreachable("timed out") }
        let watch = Monitor(setup: setup, secrets: secrets, file: nil, transport: network.transport)
        await watch.refresh()
        let revision = watch.revision
        try WatchSync(setup: setup, secrets: secrets).apply(to: watch)
        #expect(watch.readings[server.id] != nil)
        #expect(watch.revision == revision)
    }

    @Test func changesCountUp() throws {
        let monitor = Monitor(setup: Setup(), secrets: MemorySecretStore(), file: nil)
        try monitor.save(server, token: "t0ken")
        try monitor.setRootCertificate(Data([1]))
        try monitor.remove(server)
        #expect(monitor.revision == 3)
    }
}

@MainActor
struct LaunchTests {
    @Test func options() {
        let arguments = ["RedhControl", "-demo", "-open", "nas", "-edit"]
        #expect(LaunchOptions.has("-demo", in: arguments))
        #expect(!LaunchOptions.has("-setup", in: arguments))
        #expect(LaunchOptions.value(after: "-open", in: arguments) == "nas")
        #expect(LaunchOptions.value(after: "-edit", in: arguments) == nil)
    }

    @Test func theDemoStartsWithItsOwnSetup() throws {
        #expect(try Monitor.forLaunch(arguments: ["RedhControl", "-demo"]).setup == Demo.setup)
    }
}
