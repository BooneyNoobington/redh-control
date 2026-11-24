import Foundation
import Testing
@testable import RedhKit

struct DigestTests {
    /// The example of RFC 2617, section 3.5.
    let rfc = #"Digest realm="testrealm@host.com", qop="auth,auth-int", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41""#

    func answer(_ header: String) throws -> String {
        try #require(DigestChallenge(header: header)).authorization(
            method: "GET", uri: "/dir/index.html", username: "Mufasa", password: "Circle Of Life", cnonce: "0a4f113b")
    }

    // The responses below were computed with Python's hashlib.

    @Test func answersTheRFCExample() throws {
        #expect(try answer(rfc) == #"Digest username="Mufasa", realm="testrealm@host.com", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", uri="/dir/index.html", algorithm=MD5, response="6629fae49393a05397450978507c4ef1", qop=auth, nc=00000001, cnonce="0a4f113b", opaque="5ccc069c403ebaf9f0171e9517f40e41""#)
    }

    @Test func md5Sess() throws {
        let header = try answer(#"Digest realm="testrealm@host.com", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", qop="auth", algorithm=MD5-sess"#)
        #expect(header.contains(#"response="8e3825c57e897f5a0dec6c2d4e5059d0""#))
    }

    @Test func withoutQop() throws {
        let header = try answer(#"Digest realm="testrealm@host.com", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093""#)
        #expect(header.contains(#"response="670fd8c2df070c60b045671b8b24ff02""#))
        #expect(!header.contains("cnonce"))
    }

    @Test(arguments: [
        #"Basic realm="fritz.box""#,
        #"Digest realm="x", nonce="y", algorithm=SHA-256"#,
        #"Digest realm="x", nonce="y", qop="auth-int""#,
        #"Digest realm="x""#,
    ])
    func refusesWhatItCantAnswer(_ header: String) {
        #expect(DigestChallenge(header: header) == nil)
    }

    @Test func readsQuotedValues() {
        #expect(DigestChallenge.parameters(#"realm="a, \"b\"", nonce=abc , QOP="auth""#[...])
                == ["realm": #"a, "b""#, "nonce": "abc", "qop": "auth"])
    }

    @Test func quotesTheUsername() throws {
        let challenge = try #require(DigestChallenge(header: #"Digest realm="r", nonce="n", qop="auth""#))
        let header = challenge.authorization(method: "POST", uri: "/", username: #"we"ird\"#, password: "p", cnonce: "c")
        #expect(header.contains(#"username="we\"ird\\""#))
    }
}

struct SOAPTests {
    @Test func envelope() {
        let envelope = SOAP.envelope("GetSpecificHostEntry", service: SOAP.hostsService,
                                     arguments: [("NewMACAddress", "AA:BB:CC:DD:EE:FF")])
        #expect(String(decoding: envelope, as: UTF8.self) == """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
            <u:GetSpecificHostEntry xmlns:u="urn:dslforum-org:service:Hosts:1">\
            <NewMACAddress>AA:BB:CC:DD:EE:FF</NewMACAddress></u:GetSpecificHostEntry></s:Body></s:Envelope>
            """)
    }

    @Test func escapesValues() {
        #expect(SOAP.escaped(#"<a href="x">Tom & Jerry's</a>"#)
                == "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&apos;s&lt;/a&gt;")
    }

    @Test func readsAHostEntry() throws {
        let answer = try #require(SOAP.parse(try fixture("host-entry.xml")))
        #expect(answer.fault == nil)
        #expect(answer.values["NewActive"] == "1")
        #expect(answer.values["NewIPAddress"] == "192.168.178.20")
        #expect(answer.values["GetSpecificHostEntryResponse"] == nil)
    }

    @Test func readsAFault() throws {
        #expect(SOAP.parse(try fixture("fault-714.xml"))?.fault == SOAP.Fault(code: 714, description: "NoSuchEntryInArray"))
    }

    @Test func notXML() {
        #expect(SOAP.parse(json("<html><body>401 Unauthorized")) == nil)
    }
}

struct FritzBoxClientTests {
    /// The challenge of the fake box, and the answer to it with the password "secret", computed
    /// with Python's hashlib.
    static let challenge = #"Digest realm="F!Box SOAP-Auth", nonce="4D7A6E1F8B2C9E03", algorithm=MD5, qop="auth""#
    static let answer = #"Digest username="redh-control", realm="F!Box SOAP-Auth", nonce="4D7A6E1F8B2C9E03", uri="/upnp/control/hosts", algorithm=MD5, response="64a8e1c2b414088bc8e9a3b384075455", qop=auth, nc=00000001, cnonce="0a4f113b""#

    let network = FakeNetwork()
    let mac = MACAddress("aa:bb:cc:dd:ee:ff")!
    let pin = CertificatePin(String(repeating: "ab", count: 32))
    var box: Box {
        Box(name: "lab-box", host: "fritz.lab.internal", fallbackAddress: "192.0.2.1", username: "redh-control",
            certificatePin: pin)
    }
    var client: FritzBoxClient {
        FritzBoxClient(transport: network.transport) { "0a4f113b" }
    }

    /// A box that wants the digest login, then answers with the fixture.
    func boxAnswers(_ name: String, status: Int = 200) async throws {
        let body = try fixture(name)
        await network.reply { request in
            guard request.value(forHTTPHeaderField: "Authorization") == Self.answer else {
                return (401, ["WWW-Authenticate": Self.challenge], Data())
            }
            return (status, ["Content-Type": "text/xml"], body)
        }
    }

    @Test func wakesAfterTheDigestLogin() async throws {
        try await boxAnswers("wake.xml")
        try await client.wake(mac, via: box, password: "secret")
        let sent = await network.sent
        #expect(sent.count == 2)
        let request = try #require(sent.last?.request)
        #expect(request.url?.absoluteString == "https://fritz.lab.internal:49443/upnp/control/hosts")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "SOAPAction")
                == "urn:dslforum-org:service:Hosts:1#X_AVM-DE_WakeOnLANByMACAddress")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(#"<u:X_AVM-DE_WakeOnLANByMACAddress xmlns:u="urn:dslforum-org:service:Hosts:1"><NewMACAddress>AA:BB:CC:DD:EE:FF</NewMACAddress>"#))
        #expect(sent.allSatisfy { $0.policy == .pinned(pin) })
    }

    @Test func readsTheHostEntry() async throws {
        try await boxAnswers("host-entry.xml")
        #expect(try await client.hostEntry(mac, on: box, password: "secret")
                == HostEntry(active: true, ipAddress: "192.168.178.20", hostName: "nas"))
    }

    @Test func aMACAddressTheBoxDoesntKnowIsNoEntry() async throws {
        try await boxAnswers("fault-714.xml", status: 500)
        #expect(try await client.hostEntry(mac, on: box, password: "secret") == nil)
    }

    @Test func missingRights() async throws {
        try await boxAnswers("fault-606.xml", status: 500)
        await #expect(throws: FritzBoxError.fault(code: 606, description: "Action not authorized")) {
            try await client.wake(mac, via: box, password: "secret")
        }
    }

    @Test func aWrongPassword() async throws {
        try await boxAnswers("wake.xml")
        await #expect(throws: FritzBoxError.loginFailed) {
            try await client.wake(mac, via: box, password: "wrong")
        }
    }

    @Test func triesTheAddressWhenTheNameFails() async throws {
        let body = try fixture("wake.xml")
        await network.reply { request in
            if request.url?.host() == "fritz.lab.internal" {
                throw TransportError.unreachable("no such host")
            }
            return request.value(forHTTPHeaderField: "Authorization") == Self.answer
                ? (200, [:], body) : (401, ["WWW-Authenticate": Self.challenge], Data())
        }
        try await client.wake(mac, via: box, password: "secret")
        #expect(await network.sent.last?.request.url?.absoluteString == "https://192.0.2.1:49443/upnp/control/hosts")
    }

    @Test func butNotWhenTheCertificateIsRefused() async throws {
        let refusal = TransportError.untrusted(reason: "another certificate", presented: nil)
        await network.reply { _ in throw refusal }
        await #expect(throws: refusal) {
            try await client.wake(mac, via: box, password: "secret")
        }
        #expect(await network.sent.count == 1)
    }

    @Test func namesThePresentedCertificate() async throws {
        let presented = CertificatePin(certificate: try fixture("box.der"))
        await network.reply { _ in throw TransportError.untrusted(reason: "not pinned", presented: presented) }
        #expect(try await client.presentedCertificate(of: box) == presented)
        #expect(await network.sent.first?.policy == .pinned(nil))
    }
}
