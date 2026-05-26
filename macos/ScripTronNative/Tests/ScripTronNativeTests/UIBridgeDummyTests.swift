import XCTest
import SwiftUI
@testable import ScripTronNative

@MainActor
final class UIBridgeDummyTests: XCTestCase {
    func testBootUsesInjectedDummyBridgeToLoadWorkspaceAndHermesModelState() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("get_workspace_path", json: #""/tmp/ScripTron""#)
        bridge.stub("list_workspace_files", json: #"[]"#)
        bridge.stub("list_tools", json: #"[]"#)
        bridge.stub("get_active_config", json: #"{"provider":"hermes","model":"Hermes Dummy"}"#)
        bridge.stub("get_auth_status", json: #"[{"provider":"hermes","display_name":"Hermes Gateway","connected":true,"auth_method":"stdio","available_models":["Hermes Dummy"],"default_model":"Hermes Dummy"}]"#)
        bridge.stub("list_skills", json: #"[]"#)
        bridge.stub("list_tronhub", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.boot()

        XCTAssertEqual(model.workspacePath, "/tmp/ScripTron")
        XCTAssertEqual(model.activeConfig?.provider, "hermes")
        XCTAssertEqual(model.activeConfig?.model, "Hermes Dummy")
        XCTAssertEqual(model.providerStatuses.first?.display_name, "Hermes Gateway")
        XCTAssertEqual(model.status, "Connected")
        XCTAssertTrue(bridge.calledMethods.contains("get_auth_status"))
    }

    func testCreateProjectRejectsEmptyNameBeforeBridgeCall() throws {
        let bridge = DummyScripTronBridge()
        let model = AppModel(bridge: bridge)

        model.createProject(named: "   ")

        XCTAssertEqual(model.errorMessage, "Project name cannot be empty.")
        XCTAssertTrue(bridge.voidCalls.isEmpty)
    }

    func testCreateProjectDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stubVoid("create_project")
        bridge.stub("list_workspace_files", json: #"[]"#)
        bridge.stub("list_projects", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"

        model.createProject(named: "Weekly Digest")

        XCTAssertEqual(bridge.voidCalls.first?.method, "create_project")
        XCTAssertEqual(bridge.voidCalls.first?.params["name"] as? String, "Weekly Digest")
        XCTAssertEqual(model.status, "Created project Weekly Digest")
    }

    func testRefreshFilesLoadsProjectArchiveStateFromBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("list_workspace_files", json: #"[]"#)
        bridge.stub("list_projects", json: #"[{"name":"weekly-digest","path":"/tmp/ScripTron/weekly-digest","status":"Archived","archived":true,"packaged":false}]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"

        model.refreshFiles()

        XCTAssertEqual(model.projects.count, 1)
        XCTAssertEqual(model.projects.first?.name, "weekly-digest")
        XCTAssertEqual(model.projects.first?.archived, true)
        XCTAssertTrue(bridge.calledMethods.contains("list_projects"))
    }

    func testDeleteProjectDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stubVoid("delete_project")
        bridge.stub("list_workspace_files", json: #"[]"#)
        bridge.stub("list_projects", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        let project = AppModel.ProjectItem(
            name: "weekly-digest",
            path: "/tmp/ScripTron/weekly-digest",
            status: "Ready"
        )

        model.deleteProject(project)

        XCTAssertEqual(bridge.voidCalls.first?.method, "delete_project")
        XCTAssertEqual(bridge.voidCalls.first?.params["path"] as? String, "/tmp/ScripTron/weekly-digest")
        XCTAssertEqual(model.status, "Deleted weekly-digest")
    }

    func testCreateFolderDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("create_folder", json: #"{"name":"Drafts","path":"/tmp/ScripTron/Demo/Drafts","is_dir":true,"is_tron":false}"#)
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)

        model.createFolder(named: "Drafts")

        XCTAssertEqual(bridge.calledMethods.first, "create_folder")
        XCTAssertEqual(bridge.lastParams["create_folder"]?["parent_path"] as? String, "/tmp/ScripTron/Demo")
        XCTAssertEqual(bridge.lastParams["create_folder"]?["name"] as? String, "Drafts")
        XCTAssertEqual(model.status, "Created folder Drafts")
    }

    func testRenameFileDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("rename_entry", json: #"{"name":"final.md","path":"/tmp/ScripTron/Demo/final.md","is_dir":false,"is_tron":false}"#)
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)
        let file = FileEntry(name: "draft.md", path: "/tmp/ScripTron/Demo/draft.md", is_dir: false, is_tron: false)

        model.renameFile(file, to: "final.md")

        XCTAssertEqual(bridge.calledMethods.first, "rename_entry")
        XCTAssertEqual(bridge.lastParams["rename_entry"]?["path"] as? String, "/tmp/ScripTron/Demo/draft.md")
        XCTAssertEqual(bridge.lastParams["rename_entry"]?["name"] as? String, "final.md")
        XCTAssertEqual(model.status, "Renamed to final.md")
    }

    func testCreatePlainFileDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("create_file", json: #"{"name":"notes.md","path":"/tmp/ScripTron/Demo/notes.md","is_dir":false,"is_tron":false}"#)
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)

        model.createFile(named: "notes", fileExtension: "md")

        XCTAssertEqual(bridge.calledMethods.first, "create_file")
        XCTAssertEqual(bridge.lastParams["create_file"]?["parent_path"] as? String, "/tmp/ScripTron/Demo")
        XCTAssertEqual(bridge.lastParams["create_file"]?["name"] as? String, "notes.md")
        XCTAssertEqual(model.status, "Created notes.md")
    }

    func testDeleteFileDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stubVoid("delete_entry")
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)
        let file = FileEntry(name: "notes.md", path: "/tmp/ScripTron/Demo/notes.md", is_dir: false, is_tron: false)

        model.deleteFile(file)

        XCTAssertEqual(bridge.voidCalls.first?.method, "delete_entry")
        XCTAssertEqual(bridge.voidCalls.first?.params["path"] as? String, "/tmp/ScripTron/Demo/notes.md")
        XCTAssertEqual(model.status, "Deleted notes.md")
    }

    func testCopyDroppedFilesDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("copy_entry", json: #"{"name":"notes 2.md","path":"/tmp/ScripTron/Demo/notes 2.md","is_dir":false,"is_tron":false}"#)
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)

        let sourceURL = URL(fileURLWithPath: "/tmp/ScripTron/Demo/notes.md")
        let provider = NSItemProvider(object: sourceURL as NSURL)

        XCTAssertTrue(model.copyDroppedFiles([provider], to: "/tmp/ScripTron/Demo"))
        let expectation = XCTestExpectation(description: "copy callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(bridge.calledMethods.first, "copy_entry")
        XCTAssertEqual(bridge.lastParams["copy_entry"]?["path"] as? String, sourceURL.path)
        XCTAssertEqual(bridge.lastParams["copy_entry"]?["target_directory_path"] as? String, "/tmp/ScripTron/Demo")
        XCTAssertEqual(model.status, "Copied notes 2.md")
    }

    func testMoveDroppedFilesDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("move_entry", json: #"{"name":"final.md","path":"/tmp/ScripTron/Demo/Final/final.md","is_dir":false,"is_tron":false}"#)
        bridge.stub("list_dir_files", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.screen = .project(.explorer)

        let sourceURL = URL(fileURLWithPath: "/tmp/ScripTron/Demo/draft.md")
        let provider = NSItemProvider(object: sourceURL as NSURL)

        XCTAssertTrue(model.moveDroppedFiles([provider], to: "/tmp/ScripTron/Demo/Final"))
        let expectation = XCTestExpectation(description: "move callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(bridge.calledMethods.first, "move_entry")
        XCTAssertEqual(bridge.lastParams["move_entry"]?["path"] as? String, sourceURL.path)
        XCTAssertEqual(bridge.lastParams["move_entry"]?["target_directory_path"] as? String, "/tmp/ScripTron/Demo/Final")
        XCTAssertEqual(model.status, "Moved final.md")
    }

    func testImportProjectZipDropsDelegatesToRustBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("import_zip_project", json: #"{"name":"bundle","path":"/tmp/ScripTron/bundle","status":"Ready","archived":false,"packaged":false}"#)
        bridge.stub("list_workspace_files", json: #"[]"#)
        bridge.stub("list_projects", json: #"[]"#)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleDir = tempDir.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try "# Imported Project".write(to: bundleDir.appendingPathComponent("main.tron"), atomically: true, encoding: .utf8)
        let sourceURL = tempDir.appendingPathComponent("bundle.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", bundleDir.path, sourceURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let provider = NSItemProvider(object: sourceURL as NSURL)

        XCTAssertTrue(model.importProjectZipDrops([provider]))
        let expectation = XCTestExpectation(description: "import callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(bridge.calledMethods.first, "import_zip_project")
        XCTAssertEqual(bridge.lastParams["import_zip_project"]?["path"] as? String, sourceURL.path)
        XCTAssertEqual(model.status, "Imported bundle")
    }

    func testSubmitHermesPromptUsesInjectedBridgeAndStoresDummyRunEventsByBlock() async throws {
        let bridge = DummyScripTronBridge()
        let fileJSON = #"""
        {
          "path": "/tmp/ScripTron/Demo/main.tron",
          "cells": [
            {"run": false, "content": "# Context"},
            {"run": true, "content": "[[scriptron:run-name]] build\nCreate a launch plan."}
          ],
          "blackboard": {"notes":[{"source":"dummy","summary":"Hermes dummy response"}]}
        }
        """#
        bridge.stubVoid("hermes_prompt_submit")
        bridge.stub("hermes_poll_events", json: #"[{"type":"message_delta","content":"Hermes dummy response"},{"type":"tool_start","tool":"write_file"}]"#)
        bridge.stub("open_tron_file", json: fileJSON)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.selectedFile = try DummyScripTronBridge.decode(fileJSON, as: TronFile.self)
        model.documentBlocks = [
            AppModel.DocumentBlock(kind: .markdownLine, content: "# Context"),
            AppModel.DocumentBlock(kind: .run, content: "Create a launch plan.", name: "build")
        ]
        let runBlock = try XCTUnwrap(model.documentBlocks.first { $0.kind == .run })

        model.submitHermesPrompt(block: runBlock)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(bridge.voidCalls.first?.method, "hermes_prompt_submit")
        XCTAssertTrue(bridge.calledMethods.contains("hermes_poll_events"))
        XCTAssertEqual(model.status, "Hermes prompt submitted")
        XCTAssertFalse(model.isRunningTask)
        XCTAssertEqual(model.runEvents(for: runBlock).map(\.type), ["message_delta", "tool_start"])
    }

    func testModelManagementViewRendersHermesGatewayDummyStatusWithoutLegacyProviderCards() throws {
        let model = AppModel(bridge: DummyScripTronBridge())
        model.activeConfig = ActiveConfig(provider: "hermes", model: "Hermes Dummy")
        model.providerStatuses = [
            ProviderStatus(
                provider: "hermes",
                display_name: "Hermes Gateway",
                connected: true,
                auth_method: "stdio",
                available_models: ["Hermes Dummy"],
                default_model: "Hermes Dummy"
            )
        ]

        let view = ModelManagementView().environmentObject(model)

        XCTAssertNotNil(view)
        XCTAssertEqual(model.providerStatuses.first?.display_name, "Hermes Gateway")
    }

    func testRunEventPresentationSplitsDummyHermesEventsIntoUICoreSections() throws {
        let events: [RunEvent] = [
            RunEvent.local(type: "message_delta", content: "Drafting"),
            RunEvent.local(type: "tool_start", content: "write_file"),
            RunEvent.local(type: "delegation_status", content: "Researcher running"),
            RunEvent.local(type: "approval_request", content: "Allow write?"),
            RunEvent.local(type: "complete", content: "")
        ]

        let sections = RunEventPresentation.sections(for: events)

        XCTAssertEqual(sections.response.map(\.type), ["message_delta"])
        XCTAssertEqual(sections.log.map(\.type), ["tool_start"])
        XCTAssertEqual(sections.delegations.map(\.type), ["delegation_status"])
        XCTAssertEqual(sections.approvals.map(\.type), ["approval_request"])
    }

    func testRunCellActionMenuModelUsesHermesCommandCatalogAndMarksPrimarySubmitAction() {
        let menu = RunCellActionMenuModel.default

        XCTAssertEqual(menu.primary.method, "prompt.submit")
        XCTAssertEqual(menu.items.map(\.method), HermesRunCommandCatalog.default.commands.map(\.method))
        XCTAssertTrue(menu.items.contains { $0.title == "Interrupt session" })
        XCTAssertTrue(menu.items.allSatisfy { !$0.title.contains("/") })
    }

    func testTronFileEditingInsertsRunAndGenBlocksThenSavesCellsThroughBridge() throws {
        let bridge = DummyScripTronBridge()
        let fileJSON = #"""
        {
          "path": "/tmp/ScripTron/Demo/main.tron",
          "cells": [
            {"run": false, "content": "# Brief"},
            {"run": true, "content": "[[scriptron:run-name]] build\nDraft launch notes."}
          ],
          "blackboard": {"notes":[]}
        }
        """#
        bridge.stubVoid("save_tron_file")
        bridge.stub("open_tron_file", json: fileJSON)

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.selectedFile = try DummyScripTronBridge.decode(fileJSON, as: TronFile.self)
        model.documentBlocks = [
            AppModel.DocumentBlock(kind: .markdownLine, content: "# Brief"),
            AppModel.DocumentBlock(kind: .run, content: "Draft launch notes.", name: "build")
        ]
        let first = try XCTUnwrap(model.documentBlocks.first)

        model.updateDocumentBlock(first, content: "# Updated Brief")
        model.insertDocumentBlock(after: first, kind: .gen)
        let gen = try XCTUnwrap(model.documentBlocks.first { $0.kind == .gen })
        model.updateDocumentBlock(gen, content: "Turn this into a markdown checklist.")
        let run = try XCTUnwrap(model.documentBlocks.first { $0.kind == .run })
        model.updateRunBlockName(run, name: "ship_plan!")
        model.saveSelectedFile()

        let save = try XCTUnwrap(bridge.voidCalls.first { $0.method == "save_tron_file" })
        let cells = try XCTUnwrap(save.params["cells"] as? [[String: Any]])
        XCTAssertTrue(cells.contains { $0["run"] as? Bool == false && ($0["content"] as? String)?.contains("# Updated Brief") == true })
        XCTAssertTrue(cells.contains { $0["run"] as? Bool == true && ($0["content"] as? String)?.contains("[[scriptron:gen-markdown]]") == true })
        XCTAssertTrue(cells.contains { $0["run"] as? Bool == true && ($0["content"] as? String)?.contains("[[scriptron:run-name]] ship_plan") == true })
        XCTAssertEqual(model.status, "Saved main.tron")
        XCTAssertFalse(model.isDirty)
    }

    func testPlainFileEditingMarksDirtyAndSavesThroughBridge() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("notes.md")
        try "Initial notes".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bridge = DummyScripTronBridge()
        bridge.stubVoid("save_plain_file")
        let model = AppModel(bridge: bridge)
        model.workspacePath = tempDir.path
        model.activeProjectPath = tempDir.path

        model.openFile(FileEntry(name: "notes.md", path: fileURL.path, is_dir: false, is_tron: false))
        model.updateOpenedFileContent("Edited notes")

        XCTAssertEqual(model.openedFile?.viewer, .text)
        XCTAssertTrue(model.isDirty)

        model.saveSelectedFile()

        XCTAssertEqual(bridge.voidCalls.first?.method, "save_plain_file")
        XCTAssertEqual(bridge.voidCalls.first?.params["path"] as? String, fileURL.path)
        XCTAssertEqual(bridge.voidCalls.first?.params["content"] as? String, "Edited notes")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.status, "Saved notes.md")
    }

    func testGenCellUsesDummyAgentResponseAndReplacesGenBlockWithMarkdown() async throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("troner_agent_message", json: "\"# Generated\\n- First task\\n- Second task\"")

        let model = AppModel(bridge: bridge)
        model.workspacePath = "/tmp/ScripTron"
        model.activeProjectPath = "/tmp/ScripTron/Demo"
        model.documentBlocks = [
            AppModel.DocumentBlock(kind: .gen, content: "Create a launch checklist.")
        ]
        let gen = try XCTUnwrap(model.documentBlocks.first)

        model.generateMarkdown(from: gen)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(model.documentBlocks.contains { $0.kind == .gen })
        XCTAssertTrue(model.documentBlocks.contains { $0.content.contains("Generated") || $0.content.contains("First task") })
        XCTAssertTrue(bridge.calledMethods.contains("troner_agent_message"))
        XCTAssertEqual(model.status, "Generated markdown")
    }

    func testSkillAndModelManagementLoadInstallAndRemoveThroughBridge() throws {
        let bridge = DummyScripTronBridge()
        bridge.stub("list_tools", json: #"[{"name":"ripgrep","kind":"tool","description":"Search","version":"1.0","command":"/usr/bin/rg","args_schema":[],"examples":[],"homepage":null,"author":null}]"#)
        bridge.stub("get_active_config", json: #"{"provider":"hermes","model":"Hermes Dummy"}"#)
        bridge.stub("get_auth_status", json: #"[{"provider":"hermes","display_name":"Hermes Gateway","connected":true,"auth_method":"stdio","available_models":["Hermes Dummy"],"default_model":"Hermes Dummy"}]"#)
        bridge.stub("list_skills", json: #"[{"name":"writer","description":"Drafts text","path":"/tmp/.skills/writer"}]"#)
        bridge.stub("list_tronhub", json: #"[{"name":"writer","kind":"skill","description":"Drafts text","source_path":"/remote/writer","installed":false,"manifest_json":null}]"#)
        bridge.stubVoid("install_tronhub")
        bridge.stubVoid("remove_skill")

        let model = AppModel(bridge: bridge)
        model.selectWorkspacePanel(.modelManagement)

        XCTAssertEqual(model.cliRegistry.first?.name, "ripgrep")
        XCTAssertEqual(model.installedSkills.first?.name, "writer")
        XCTAssertEqual(model.providerStatuses.first?.display_name, "Hermes Gateway")
        XCTAssertEqual(model.tronhubSkills.first?.name, "writer")

        let skillMarketItem = try XCTUnwrap(model.tronhubSkills.first)
        model.installTronhub(skillMarketItem)
        XCTAssertEqual(bridge.voidCalls.last?.method, "install_tronhub")
        XCTAssertEqual(bridge.voidCalls.last?.params["kind"] as? String, "skill")
        XCTAssertEqual(model.status, "Installed writer")

        let installedSkill = try XCTUnwrap(model.installedSkills.first)
        model.removeSkill(installedSkill)
        XCTAssertEqual(bridge.voidCalls.last?.method, "remove_skill")
        XCTAssertEqual(bridge.voidCalls.last?.params["name"] as? String, "writer")
        XCTAssertEqual(model.status, "Skill removed")
    }

    func testExtensionCatalogFiltersBySourceCategoryAndSearchWithHermesOwnershipActions() {
        let catalog = ExtensionCatalogState(items: [
            ExtensionCatalogItem(
                name: "github-pr-review",
                kind: .skill,
                source: .hermesHub,
                category: "Software Dev",
                trustLevel: "official",
                description: "Review pull requests",
                installed: false,
                wrapsExternalCLI: false,
                hermesCompatible: true
            ),
            ExtensionCatalogItem(
                name: "scriptron-deck-writer",
                kind: .skill,
                source: .tronHub,
                category: "Creative",
                trustLevel: "workspace",
                description: "Create decks from .tron workflow packs",
                installed: false,
                wrapsExternalCLI: true,
                hermesCompatible: true
            ),
            ExtensionCatalogItem(
                name: "legacy-project-template",
                kind: .cli,
                source: .tronHub,
                category: "Productivity",
                trustLevel: "workspace",
                description: "ScripTron-only template",
                installed: false,
                wrapsExternalCLI: false,
                hermesCompatible: false
            )
        ])

        XCTAssertEqual(catalog.sources, [.hermesHub, .tronHub])
        XCTAssertTrue(catalog.categories.contains("Software Dev"))
        XCTAssertTrue(catalog.categories.contains("Creative"))

        let hermesSoftware = catalog.filtered(source: .hermesHub, category: "Software Dev", query: "pull")
        XCTAssertEqual(hermesSoftware.map(\.name), ["github-pr-review"])
        XCTAssertEqual(hermesSoftware.first?.primaryAction, .installIntoHermes)

        let tronhubCreative = catalog.filtered(source: .tronHub, category: "Creative", query: "deck")
        XCTAssertEqual(tronhubCreative.map(\.name), ["scriptron-deck-writer"])
        XCTAssertEqual(tronhubCreative.first?.primaryAction, .installIntoHermes)
        XCTAssertTrue(tronhubCreative.first?.wrapsExternalCLI == true)

        let scriptronOnly = catalog.filtered(source: .tronHub, category: "Productivity", query: "template")
        XCTAssertEqual(scriptronOnly.first?.primaryAction, .installIntoScripTron)
    }
}

final class DummyScripTronBridge: ScripTronBridgeClient, @unchecked Sendable {
    struct VoidCall {
        let method: String
        let params: [String: Any]
    }

    private var responses: [String: String] = [:]
    private var voidMethods: Set<String> = []
    private(set) var calledMethods: [String] = []
    private(set) var voidCalls: [VoidCall] = []
    private(set) var lastParams: [String: [String: Any]] = [:]

    func initialize() throws {
        calledMethods.append("initialize")
    }

    func call<T: Decodable>(_ method: String, params: [String: Any], as type: T.Type) throws -> T {
        calledMethods.append(method)
        lastParams[method] = params
        guard let json = responses[method] else {
            throw RustBridge.BridgeError.runtime("Missing dummy response for \(method)")
        }
        return try Self.decode(json, as: T.self)
    }

    func callVoid(_ method: String, params: [String: Any]) throws {
        voidCalls.append(VoidCall(method: method, params: params))
        guard voidMethods.contains(method) else {
            throw RustBridge.BridgeError.runtime("Missing dummy void response for \(method)")
        }
    }

    func stub(_ method: String, json: String) {
        responses[method] = json
    }

    func stubVoid(_ method: String) {
        voidMethods.insert(method)
    }

    static func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
