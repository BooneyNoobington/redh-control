import Foundation
import Testing

/// RedhAPI's repository, where it is checked out next to this one: as `../redh-api`, its name on
/// GitHub, or as `../redhapi`, the name of older checkouts.
enum RedhAPIRepository {
    static let readme: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 1...7 {
            root.deleteLastPathComponent()
        }
        let readmes = ["redh-api", "redhapi"].map { root.appending(path: "\($0)/README.md") }
        return readmes.first { FileManager.default.fileExists(atPath: $0.path) } ?? readmes[0]
    }()

    static var checkedOut: Bool {
        FileManager.default.fileExists(atPath: readme.path)
    }

    /// The JSON example under the README's heading for the endpoint, such as "`GET /v1/status`".
    static func example(of endpoint: String) throws -> Any {
        let readme = try String(contentsOf: Self.readme, encoding: .utf8)
        let section = try #require(readme.range(of: "### \(endpoint)"))
        let start = try #require(readme.range(of: "```json\n", range: section.upperBound..<readme.endIndex))
        let end = try #require(readme.range(of: "\n```", range: start.upperBound..<readme.endIndex))
        return try JSONSerialization.jsonObject(with: Data(readme[start.upperBound..<end.lowerBound].utf8))
    }
}

/// The copies of the contract in the fixtures are still RedhAPI's own. Skipped where RedhAPI isn't
/// checked out next to this repository.
@Suite(.enabled(if: RedhAPIRepository.checkedOut))
struct ContractTests {
    @Test func theStatusExampleIsTheOneInRedhAPIsReadme() throws {
        let original = try RedhAPIRepository.example(of: "`GET /v1/status`")
        let copy = try JSONSerialization.jsonObject(with: try statusExample())
        #expect(original as? NSDictionary == copy as? NSDictionary)
    }

    @Test func theAppsExampleIsTheOneInRedhAPIsReadme() throws {
        let original = try RedhAPIRepository.example(of: "`GET /v1/apps`")
        let copy = try JSONSerialization.jsonObject(with: try fixture("apps.json"))
        #expect(original as? NSDictionary == copy as? NSDictionary)
    }

    @Test func theSystemExampleIsTheOneInRedhAPIsReadme() throws {
        let original = try RedhAPIRepository.example(of: "`GET /v1/system`")
        let copy = try JSONSerialization.jsonObject(with: try fixture("system.json"))
        #expect(original as? NSDictionary == copy as? NSDictionary)
    }
}
