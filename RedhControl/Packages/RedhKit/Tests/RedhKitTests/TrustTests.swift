import Foundation
import Testing
@testable import RedhKit

struct CertificatePinTests {
    /// `openssl x509 -inform DER -in Fixtures/box.der -noout -fingerprint -sha256`
    let openssl = "sha256 Fingerprint=E9:41:B0:C2:AD:9E:26:A0:F2:30:17:B6:67:85:12:49:0C:DB:CB:6A:8D:3E:E8:EC:BC:A1:71:B1:FB:98:84:5E"

    @Test func isTheFingerprintOpensslShows() throws {
        let pin = CertificatePin(certificate: try fixture("box.der"))
        #expect(pin.description == String(openssl.dropFirst("sha256 Fingerprint=".count)))
        #expect(CertificatePin(openssl) == pin)
    }

    @Test func readsFingerprintsWithoutColons() throws {
        let pin = CertificatePin(certificate: try fixture("box.der"))
        #expect(CertificatePin(pin.description.replacingOccurrences(of: ":", with: "").lowercased()) == pin)
        #expect(CertificatePin(String(pin.description.dropLast(3))) == nil)
        #expect(CertificatePin("not a fingerprint") == nil)
    }

    @Test func isCodableAsText() throws {
        let pin = CertificatePin(certificate: try fixture("box.der"))
        let data = try JSONEncoder().encode([pin])
        #expect(String(decoding: data, as: UTF8.self) == "[\"\(pin.description)\"]")
        #expect(try JSONDecoder().decode([CertificatePin].self, from: data) == [pin])
    }
}

struct TrustPolicyTests {
    @Test func theRootTrustsItsLeafForItsName() throws {
        let policy = TrustPolicy.root(try fixture("root.der"))
        #expect(policy.evaluate(try serverTrust("leaf"), host: "rapi.lab.internal") == .trusted)
    }

    @Test func butNotForAnotherName() throws {
        let verdict = TrustPolicy.root(try fixture("root.der")).evaluate(try serverTrust("leaf"), host: "rapi.other.internal")
        guard case .refused(_, let presented) = verdict else {
            Issue.record("trusted for another name")
            return
        }
        #expect(presented == CertificatePin(certificate: try fixture("leaf.der")))
    }

    @Test func norALeafOfAnotherRoot() throws {
        let policy = TrustPolicy.root(try fixture("root.der"))
        #expect(policy.evaluate(try serverTrust("stranger-leaf", "stranger-root"), host: "rapi.lab.internal") != .trusted)
    }

    @Test func norTheRootItselfAsAServer() throws {
        let policy = TrustPolicy.root(try fixture("root.der"))
        #expect(policy.evaluate(try serverTrust("root"), host: "rapi.lab.internal") != .trusted)
    }

    @Test func aRootThatIsNoCertificate() throws {
        let verdict = TrustPolicy.root(Data([1, 2, 3])).evaluate(try serverTrust("leaf"), host: "rapi.lab.internal")
        #expect(verdict == .refused(reason: "The root certificate in the setup can't be read.",
                                    presented: CertificatePin(certificate: try fixture("leaf.der"))))
    }

    @Test func aPinnedCertificateIsTrustedWhateverItsName() throws {
        let pin = CertificatePin(certificate: try fixture("box.der"))
        #expect(TrustPolicy.pinned(pin).evaluate(try serverTrust("box"), host: "192.0.2.1") == .trusted)
    }

    @Test func anotherCertificateIsNot() throws {
        let pin = CertificatePin(certificate: try fixture("box.der"))
        let verdict = TrustPolicy.pinned(pin).evaluate(try serverTrust("leaf"), host: "fritz.lab.internal")
        #expect(verdict == .refused(reason: "It presented another certificate than the pinned one.",
                                    presented: CertificatePin(certificate: try fixture("leaf.der"))))
    }

    @Test func pairingCodes() throws {
        let hex = String(repeating: "ab", count: 32)
        let code = try #require(PairingCode(" redh1:\(hex):am7zjEPH9VIWSAtbXxBu18SlWSojCFM9dM4KK7ab-_s\n"))
        #expect(code.pin == CertificatePin(hex))
        #expect(code.token == "am7zjEPH9VIWSAtbXxBu18SlWSojCFM9dM4KK7ab-_s")
        for text in ["", "redh1:\(hex)", "redh1:\(hex):", "redh2:\(hex):t0ken", "redh1:abcd:t0ken",
                     "redh1:\(String(repeating: "zz", count: 32)):t0ken", "redh1:\(hex):t0ken with space",
                     "redh1:\(hex):tök"] {
            #expect(PairingCode(text) == nil, "\(text)")
        }
    }

    @Test func withoutAPinNothingIsTrustedButThePresentedOneIsNamed() throws {
        let verdict = TrustPolicy.pinned(nil).evaluate(try serverTrust("box"), host: "fritz.lab.internal")
        #expect(verdict == .refused(reason: "No certificate is pinned for it yet.",
                                    presented: CertificatePin(certificate: try fixture("box.der"))))
    }
}
