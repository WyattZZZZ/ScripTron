import XCTest
@testable import ScripTronNative

@MainActor
final class HermesStage2BridgeTests: XCTestCase {
    func testHermesSkillMarketLoadsOfficialHubFromBridgeNotFixtures() throws {
        let bridge = DummyScripTronBridge()
        stubWorkspaceManagementBasics(on: bridge)
        bridge.stub("hermes_skills_browse", json: #"""
        [
          {
            "name": "official-stage2-skill",
            "description": "Loaded from Hermes official skill hub",
            "source": "Hermes Official / Hub",
            "category": "Research",
            "trust_level": "official",
            "installed": false,
            "install_ref": "official-stage2-skill",
            "wraps_external_cli": false
          }
        ]
        """#)

        let model = AppModel(bridge: bridge)
        model.loadWorkspaceManagementData()

        XCTAssertTrue(bridge.calledMethods.contains("hermes_skills_browse"))
        XCTAssertEqual(model.hermesSkillCatalog.map(\.name), ["official-stage2-skill"])
        XCTAssertFalse(model.hermesSkillCatalog.contains { $0.name == "github-pr-review" })

        let catalog = ExtensionCatalogState(items: model.skillMarketCatalogItems)
        let hermesItems = catalog.filtered(source: .hermesHub, category: "Research", query: "official")
        XCTAssertEqual(hermesItems.map(\.name), ["official-stage2-skill"])
        XCTAssertEqual(hermesItems.first?.primaryAction, .installIntoHermes)
    }

    func testInstallHermesOfficialSkillCallsHermesInstallNotTronHubInstall() throws {
        let bridge = DummyScripTronBridge()
        bridge.stubVoid("hermes_skills_install")
        bridge.stubVoid("install_tronhub")

        let model = AppModel(bridge: bridge)
        let item = ExtensionCatalogItem(
            name: "official-stage2-skill",
            kind: .skill,
            source: .hermesHub,
            category: "Research",
            trustLevel: "official",
            description: "Loaded from Hermes official skill hub",
            installed: false,
            wrapsExternalCLI: false,
            hermesCompatible: true,
            installRef: "official-stage2-skill"
        )

        model.installCatalogItem(item)

        XCTAssertEqual(bridge.voidCalls.last?.method, "hermes_skills_install")
        XCTAssertEqual(bridge.voidCalls.last?.params["install_ref"] as? String, "official-stage2-skill")
        XCTAssertFalse(bridge.voidCalls.contains { $0.method == "install_tronhub" })
    }

    func testCliMarketIncludesHermesOfficialCliWrapperSkillsFromBridge() throws {
        let bridge = DummyScripTronBridge()
        stubWorkspaceManagementBasics(on: bridge)
        bridge.stub("hermes_skills_browse", json: #"""
        [
          {
            "name": "claude-code",
            "description": "Delegate coding tasks to Claude Code CLI.",
            "source": "Hermes Official / Hub",
            "category": "Autonomous AI Agents",
            "trust_level": "official",
            "installed": false,
            "install_ref": "official/autonomous-ai-agents/claude-code",
            "wraps_external_cli": true,
            "tags": ["official", "cli", "coding"],
            "icon": "terminal"
          },
          {
            "name": "github-issues",
            "description": "Work with GitHub issues through Hermes.",
            "source": "Hermes Official / Hub",
            "category": "GitHub",
            "trust_level": "official",
            "installed": false,
            "install_ref": "official/github/github-issues",
            "wraps_external_cli": false,
            "tags": ["official", "github"],
            "icon": "sparkles"
          }
        ]
        """#)

        let model = AppModel(bridge: bridge)
        model.loadWorkspaceManagementData()

        XCTAssertEqual(model.cliMarketCatalogItems.map(\.name), ["claude-code"])
        XCTAssertEqual(model.cliMarketCatalogItems.first?.kind, .cli)
        XCTAssertEqual(model.cliMarketCatalogItems.first?.tags, ["official", "cli", "coding"])
        XCTAssertEqual(model.cliMarketCatalogItems.first?.icon, "terminal")
    }

    func testMarketsFallbackToBundledOfficialCatalogWhenHermesBrowseFails() throws {
        let bridge = DummyScripTronBridge()
        stubWorkspaceManagementBasics(on: bridge)

        let model = AppModel(bridge: bridge)
        model.loadWorkspaceManagementData(reportErrors: false)

        XCTAssertFalse(model.skillMarketCatalogItems.isEmpty)
        XCTAssertFalse(model.cliMarketCatalogItems.isEmpty)
        XCTAssertTrue(model.skillMarketCatalogItems.allSatisfy { $0.source == .hermesHub })
        XCTAssertTrue(model.cliMarketCatalogItems.allSatisfy { $0.source == .hermesHub && $0.wrapsExternalCLI })
        XCTAssertNil(model.errorMessage)
    }

    private func stubWorkspaceManagementBasics(on bridge: DummyScripTronBridge) {
        bridge.stub("list_tools", json: #"[]"#)
        bridge.stub("get_active_config", json: #"{"provider":"hermes","model":"Hermes Dummy"}"#)
        bridge.stub("get_auth_status", json: #"[{"provider":"hermes","display_name":"Hermes Gateway","connected":true,"auth_method":"stdio","available_models":["Hermes Dummy"],"default_model":"Hermes Dummy"}]"#)
        bridge.stub("list_skills", json: #"[]"#)
        bridge.stub("list_tronhub", json: #"[]"#)
    }
}
