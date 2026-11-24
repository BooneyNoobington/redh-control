import Foundation
import Testing
@testable import RedhKit

#if canImport(AppKit)
import AppKit
#endif

struct MACAddressTests {
    @Test(arguments: ["aa:bb:cc:dd:ee:0f", "AA-BB-CC-DD-EE-0F", "aabb.ccdd.ee0f", "aabbccddee0f", " AA:BB:CC:DD:EE:0F "])
    func readsTheUsualSpellings(_ text: String) throws {
        #expect(try #require(MACAddress(text)).description == "AA:BB:CC:DD:EE:0F")
    }

    @Test(arguments: ["", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "gg:bb:cc:dd:ee:ff", "aa bb cc dd ee ff",
                      "ａａ:bb:cc:dd:ee:ff"])
    func refusesEverythingElse(_ text: String) {
        #expect(MACAddress(text) == nil)
    }

    @Test func isCodableAsText() throws {
        let mac = try #require(MACAddress("aa:bb:cc:dd:ee:ff"))
        let data = try JSONEncoder().encode([mac])
        #expect(String(decoding: data, as: UTF8.self) == #"["AA:BB:CC:DD:EE:FF"]"#)
        #expect(try JSONDecoder().decode([MACAddress].self, from: data) == [mac])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([MACAddress].self, from: json(#"["nope"]"#)) }
    }
}

struct SetupTests {
    let box: Box
    let setup: Setup

    init() {
        box = Box(name: "lab-box", host: "fritz.lab.internal", fallbackAddress: "192.0.2.1", username: "redh-control",
                  certificatePin: CertificatePin(String(repeating: "ab", count: 32)))
        setup = Setup(boxes: [box],
                      servers: [Server(name: "lab", apiURL: URL(string: "https://rapi.lab.internal")!, rooster: .box(box.id),
                                       mac: MACAddress("aa:bb:cc:dd:ee:ff"), icon: .nas, color: .teal)],
                      rootCertificate: Data([1, 2, 3]))
    }

    @Test func survivesJSON() throws {
        #expect(try JSONDecoder().decode(Setup.self, from: JSONEncoder().encode(setup)) == setup)
    }

    @Test func alwaysOnSurvivesJSON() throws {
        var setup = self.setup
        setup.servers[0].alwaysOn = true
        #expect(try JSONDecoder().decode(Setup.self, from: JSONEncoder().encode(setup)) == setup)
    }

    @Test func serversSavedBeforeAlwaysOnArentAlwaysOn() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
        var servers = try #require(object["servers"] as? [[String: Any]])
        #expect(servers[0].removeValue(forKey: "alwaysOn") as? Bool == false)
        object["servers"] = servers
        #expect(try JSONDecoder().decode(Setup.self, from: JSONSerialization.data(withJSONObject: object)) == setup)
    }

    @Test func iconsAndColorsOfANewerVersionFallBack() throws {
        let text = String(decoding: try JSONEncoder().encode(setup), as: UTF8.self)
            .replacingOccurrences(of: #""externaldrive.connected.to.line.below""#, with: #""hologram""#)
            .replacingOccurrences(of: #""teal""#, with: #""ultraviolet""#)
        let server = try #require(try JSONDecoder().decode(Setup.self, from: json(text)).servers.first)
        #expect((server.icon, server.color) == (.serverRack, .blue))
    }

    @Test func findsTheRoosterOfAServer() throws {
        let server = try #require(setup.servers.first)
        #expect(setup.box(for: server) == box)
        #expect(setup.roosterName(for: server) == "lab-box")
        var loner = server
        loner.rooster = nil
        #expect(setup.box(for: loner) == nil)
        #expect(setup.roosterName(for: loner) == nil)
    }

    @Test func aServerCanBeTheRoosterOfOthers() throws {
        var setup = self.setup
        let nas = try #require(setup.servers.first)
        let backup = Server(name: "backup", apiURL: URL(string: "https://rapi.backup.internal")!, rooster: .server(nas.id))
        setup.servers.append(backup)
        #expect(setup.roosterServer(for: backup) == nas)
        #expect(setup.box(for: backup) == nil)
        #expect(setup.roosterName(for: backup) == "lab")
        #expect(setup.servers(wokenBy: nas) == [backup])
        #expect(setup.servers(wokenBy: backup).isEmpty)
        #expect(try JSONDecoder().decode(Setup.self, from: JSONEncoder().encode(setup)) == setup)
    }

    @Test func aPairedServerKeepsItsPin() throws {
        var setup = self.setup
        setup.servers[0].certificatePin = CertificatePin(String(repeating: "cd", count: 32))
        #expect(try JSONDecoder().decode(Setup.self, from: JSONEncoder().encode(setup)) == setup)
        #expect(try JSONDecoder().decode(Setup.self, from: JSONEncoder().encode(self.setup)).servers[0].certificatePin == nil)
    }

    @Test func roostersAreSavedByKindAndID() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
        let server = try #require((object["servers"] as? [[String: Any]])?.first)
        #expect(server["rooster"] as? [String: String] == ["box": box.id.uuidString])
        #expect(server["boxID"] == nil)
    }

    @Test func theBoxOfFormatOneBecomesTheRooster() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
        var servers = try #require(object["servers"] as? [[String: Any]])
        servers[0].removeValue(forKey: "rooster")
        servers[0]["boxID"] = box.id.uuidString
        object["servers"] = servers
        #expect(try JSONDecoder().decode(Setup.self, from: JSONSerialization.data(withJSONObject: object)) == setup)
    }

    @Test func triesTheBoxByNameThenByAddress() {
        #expect(box.addresses == ["fritz.lab.internal", "192.0.2.1"])
        var nameOnly = box
        nameOnly.fallbackAddress = " "
        #expect(nameOnly.addresses == ["fritz.lab.internal"])
    }

    @Test func defaultAPIURL() {
        #expect(Server.defaultAPIURL(for: "NAS") == URL(string: "https://rapi.nas.internal"))
        #expect(Server.defaultAPIURL(for: "my nas") == nil)
        #expect(Server.defaultAPIURL(for: "") == nil)
        #expect(Server.defaultAPIURL(for: "nas.") == nil)
    }

    #if canImport(AppKit)
    @Test(arguments: ServerIcon.allCases)
    func everyIconIsAnSFSymbol(_ icon: ServerIcon) {
        #expect(NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil) != nil)
    }
    #endif
}

struct SetupFileTests {
    func scratch() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RedhKitTests-\(UUID().uuidString)/setup.json")
    }

    @Test func nothingSavedIsAnEmptySetup() throws {
        #expect(try SetupFile(url: scratch()).load() == Setup())
    }

    @Test func savesAndLoads() throws {
        let file = SetupFile(url: scratch())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let setup = SetupTests().setup
        try file.save(setup)
        #expect(try file.load() == setup)
        let saved = String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
        #expect(saved.contains(#""version" : 2"#))
    }

    @Test func readsFormatOne() throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let box = "D0000000-0000-4000-8000-000000000001"
        try json("""
            {"version": 1, "setup": {"boxes": [{"id": "\(box)", "name": "lab-box", "host": "fritz.lab.internal", \
            "port": 49443, "username": "redh-control"}], "servers": [{"id": "D0000000-0000-4000-8000-000000000002", \
            "name": "nas", "apiURL": "https://rapi.nas.internal", "boxID": "\(box)", "mac": "AA:BB:CC:00:00:02", \
            "icon": "server.rack", "color": "teal", "alwaysOn": true}]}}
            """).write(to: url)
        let setup = try SetupFile(url: url).load()
        #expect(setup.servers.first?.rooster == .box(try #require(UUID(uuidString: box))))
    }

    @Test func refusesANewerFormat() throws {
        let url = scratch()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json(#"{"version": 3, "setup": {"boxes": [], "servers": []}}"#).write(to: url)
        #expect(throws: SetupFileError.newerVersion(3)) { try SetupFile(url: url).load() }
    }
}

struct SecretStoreTests {
    @Test func inMemory() throws {
        let store = MemorySecretStore()
        let key = SecretKey.token(server: UUID())
        #expect(try store.secret(for: key) == nil)
        try store.setSecret("t0ken", for: key)
        #expect(try store.secret(for: key) == "t0ken")
        try store.setSecret(nil, for: key)
        #expect(try store.secret(for: key) == nil)
    }

    @Test func keychainAccounts() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(SecretKey.token(server: id).account == "token:6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(SecretKey.password(box: id).account == "password:6F9619FF-8B86-D011-B42D-00C04FC964FF")
    }

    #if os(macOS)
    /// The Mac app has no provisioning profile, and so no keychain access group; nor has this test.
    /// The Keychain has to work without one. The test's item is gone afterwards.
    @Test func keychainOnTheMac() throws {
        let store = KeychainSecretStore(service: "com.redhwire.redhcontrol.tests")
        let key = SecretKey.token(server: UUID())
        defer { try? store.setSecret(nil, for: key) }
        #expect(try store.secret(for: key) == nil)
        try store.setSecret("t0ken", for: key)
        #expect(try store.secret(for: key) == "t0ken")
        try store.setSecret("n3w", for: key)
        #expect(try store.secret(for: key) == "n3w")
        try store.setSecret(nil, for: key)
        #expect(try store.secret(for: key) == nil)
    }
    #endif
}
