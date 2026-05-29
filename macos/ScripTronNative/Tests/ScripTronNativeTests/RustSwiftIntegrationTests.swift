import XCTest
@testable import ScripTronNative

final class RustSwiftIntegrationTests: XCTestCase {
    @MainActor
    func testRustBridgeCallsRustFfiAndFakeHermesOfficialSkillRepository() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fakeHermes = repoRoot
            .appendingPathComponent("crates/scriptron-core/tests/fixtures/fake-hermes")
            .path
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scriptron-swift-rust-\(UUID().uuidString)")
        let log = home.appendingPathComponent("fake-hermes-commands.log")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        setenv("HOME", home.path, 1)
        setenv("SCRIPTRON_HERMES_BIN", fakeHermes, 1)
        setenv("FAKE_HERMES_LOG", log.path, 1)

        let bridge = RustBridge.shared
        try bridge.initialize()

        let status = try bridge.call("hermes_status", as: HermesStatusResponse.self)
        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.version, "hermes 0.0.0-fake")

        let browsed = try bridge.call("hermes_skills_browse", as: [HermesSkillCatalogEntry].self)
        XCTAssertEqual(browsed.map(\.name), ["claude-code", "github-pr-review", "research-brief"])
        XCTAssertEqual(browsed.first?.source, "Hermes Official / Hub")
        XCTAssertEqual(browsed.first?.tags, ["official", "cli", "coding"])
        XCTAssertEqual(browsed.first?.icon, "terminal")

        let model = AppModel(bridge: bridge)
        model.boot()
        XCTAssertFalse(model.skillMarketCatalogItems.isEmpty)
        XCTAssertFalse(model.cliMarketCatalogItems.isEmpty)
        XCTAssertNil(model.errorMessage)

        let searched = try bridge.call(
            "hermes_skills_search",
            params: ["query": "github"],
            as: [HermesSkillCatalogEntry].self
        )
        XCTAssertEqual(searched.map(\.name), ["github-pr-review"])

        try bridge.callVoid("hermes_skills_install", params: ["install_ref": "github-pr-review"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: home.appendingPathComponent("ScripTron/.skills/github-pr-review").path),
            "Hermes official skill install must stay in Hermes, not workspace .skills"
        )

        let commands = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(commands.contains("--version"))
        XCTAssertTrue(commands.contains("skills browse --size 100"))
        XCTAssertTrue(commands.contains("skills search github --limit 20"))
        XCTAssertTrue(commands.contains("skills install github-pr-review"))
    }
}

private struct HermesStatusResponse: Decodable {
    let installed: Bool
    let running: Bool
    let version: String?
    let diagnostic: String?
}
