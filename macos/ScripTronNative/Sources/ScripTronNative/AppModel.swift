import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let defaultManifestDraft = """
{
  "name": "my-cli-tool",
  "kind": "tool",
  "description": "Describe what this local CLI does.",
  "version": "0.1.0",
  "command": "/absolute/path/to/tool",
  "args_schema": [
    {
      "name": "input",
      "description": "Input text or file path.",
      "required": true,
      "type": "string"
    }
  ],
  "examples": [
    "my-cli-tool --input ./data.csv"
  ]
}
"""

    enum Screen {
        case workspace
        case project(ProjectPanel)
    }

    enum WorkspacePanel: String, CaseIterable, Identifiable {
        case allProjects = "All Projects"
        case archived = "Archived"
        case cliMarket = "CLI Market"
        case cliManagement = "CLI Management"
        case skillMarket = "Skill Market"
        case skillManagement = "Skill Management"
        case modelManagement = "Model Management"
        case settings = "Settings"

        var id: String { rawValue }
    }

    enum ProjectPanel: String, CaseIterable, Identifiable {
        case explorer = "Explorer"
        case settings = "Settings"

        var id: String { rawValue }
    }

    struct ProjectItem: Identifiable, Equatable, Decodable {
        let id = UUID()
        var name: String
        var path: String
        var status: String
        var archived: Bool = false
        var packaged: Bool = false

        enum CodingKeys: String, CodingKey {
            case name
            case path
            case status
            case archived
            case packaged
        }
    }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        let content: String
    }

    enum DocumentBlockKind: Equatable {
        case markdownLine
        case heading(Int)
        case list(Bool)
        case table
        case quote
        case code
        case checklist
        case divider
        case run
        case gen
    }

    struct DocumentBlock: Identifiable, Equatable {
        let id = UUID()
        var kind: DocumentBlockKind
        var content: String
        var name: String = ""
    }

    enum ViewerKind: String {
        case code = "Code"
        case csv = "CSV"
        case text = "Text"
        case pdf = "PDF"
        case word = "Word"
        case excel = "Excel"
        case quickLook = "Preview"
        case unsupported = "Unsupported"
    }

    struct OpenedFile {
        var name: String
        var path: String
        var content: String
        var viewer: ViewerKind
        var language: String
    }

    private struct ExternalTabState {
        var file: OpenedFile
        var dirty: Bool
    }

    private struct TronTabState {
        var file: TronFile
        var draftCells: [TronCell]
        var documentBlocks: [DocumentBlock]
        var dirty: Bool
    }

    @Published var screen: Screen = .workspace
    @Published var workspacePanel: WorkspacePanel = .allProjects
    @Published var workspacePath = "Loading..."
    @Published var activeProjectPath: String?
    @Published var activeProjectName = ""
    @Published var files: [FileEntry] = []
    @Published var expandedFolders = Set<String>()
    @Published var folderChildren: [String: [FileEntry]] = [:]
    @Published var projects: [ProjectItem] = []
    @Published var selectedFile: TronFile?
    @Published var openedFile: OpenedFile?
    @Published var openTabs: [FileEntry] = []
    @Published var activeTabPath: String?
    @Published var dirtyTabPaths = Set<String>()
    @Published var draggedFilePath: String?
    @Published var dropHoverFolderPath: String?
    @Published var draftCells: [TronCell] = []
    @Published var documentBlocks: [DocumentBlock] = []
    @Published var isDirty = false
    @Published var newScriptName = "untitled"
    @Published var runEvents: [RunEvent] = []
    @Published var runEventsByBlockID: [UUID: [RunEvent]] = [:]
    @Published var runEventsByBlockKey: [String: [RunEvent]] = [:]
    @Published var runEventsBlockID: UUID?
    @Published var isRunningTask = false
    @Published var selectedDocumentBlockIDs = Set<UUID>()
    @Published var lastSelectedDocumentBlockID: UUID?
    @Published var memorySnapshot: MemorySnapshot?
    @Published var cliRegistry: [CLIManifest] = []
    @Published var installedSkills: [SkillEntry] = []
    @Published var tronhubClis: [TronhubEntry] = []
    @Published var tronhubModels: [TronhubEntry] = []
    @Published var tronhubSkills: [TronhubEntry] = []
    @Published var hermesSkillCatalog: [ExtensionCatalogItem] = []
    @Published var activeConfig: ActiveConfig?
    @Published var providerStatuses: [ProviderStatus] = []
    @Published var hermesCommandOutput: HermesCommandReport?
    @Published var pluginLoginRunning: String? = nil
    @Published var pluginLoginOutput: (name: String, output: String)? = nil
    @Published var installManifestDraft = AppModel.defaultManifestDraft
    @Published var mentionSearch = MentionSearchResult(tools: [], files: [], cloud_suggestions: [])
    @Published var functionMentions: [MentionItem] = []
    @Published var selectedMentions: [MentionItem] = []
    @Published var agentBusy = false
    @Published var appLanguage = UserDefaults.standard.string(forKey: "scriptron.appLanguage") ?? "en"
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: "system", content: "Workspace Agent is scoped to project planning, file organization, CLI setup, and model configuration. It should not promise sharing or cloud collaboration features.")
    ]
    @Published var status = "Starting"
    @Published var errorMessage: String?
    @Published var focusedBlockID: UUID?

    private let bridge: ScripTronBridgeClient
    private var externalTabStates: [String: ExternalTabState] = [:]
    private var tronTabStates: [String: TronTabState] = [:]
    private var booted = false
    private var workspaceManagementDataLoaded = false

    init(bridge: ScripTronBridgeClient = AppModel.defaultBridge()) {
        self.bridge = bridge
    }

    private static func defaultBridge() -> ScripTronBridgeClient {
        if ProcessInfo.processInfo.environment["SCRIPTRON_DUMMY_BRIDGE"] == "1" {
            return DummyHermesBridge()
        }
        return RustBridge.shared
    }

    private var projectRootPath: String {
        activeProjectPath ?? workspacePath
    }

    func boot() {
        guard !booted else { return }
        do {
            try bridge.initialize()
            booted = true
            workspacePath = try bridge.call("get_workspace_path", as: String.self)
            if case .project = screen, activeProjectPath == nil {
                screen = .workspace
            }
            refreshFiles()
            loadWorkspaceManagementData(reportErrors: false, includeRemote: false)
            status = "Connected"
        } catch {
            errorMessage = error.localizedDescription
            status = "Rust bridge error"
        }
    }

    func openProject(panel: ProjectPanel = .explorer) {
        guard activeProjectPath != nil else {
            showWorkspace()
            return
        }
        screen = .project(panel)
        loadProjectFiles()
        loadMemorySnapshot()
    }

    func openProject(_ project: ProjectItem, panel: ProjectPanel = .explorer) {
        activeProjectPath = project.path
        activeProjectName = project.name
        selectedFile = nil
        openedFile = nil
        openTabs = []
        activeTabPath = nil
        dirtyTabPaths = []
        externalTabStates = [:]
        tronTabStates = [:]
        draftCells = []
        documentBlocks = []
        selectedDocumentBlockIDs = []
        lastSelectedDocumentBlockID = nil
        isDirty = false
        screen = .project(panel)
        loadProjectFiles()
    }

    func showWorkspace() {
        screen = .workspace
        activeProjectPath = nil
        activeProjectName = ""
        selectedFile = nil
        openedFile = nil
        openTabs = []
        activeTabPath = nil
        dirtyTabPaths = []
        externalTabStates = [:]
        tronTabStates = [:]
        draftCells = []
        documentBlocks = []
        selectedDocumentBlockIDs = []
        lastSelectedDocumentBlockID = nil
        isDirty = false
        refreshFiles()
    }

    func selectPanel(_ panel: ProjectPanel) {
        guard activeProjectPath != nil else {
            showWorkspace()
            return
        }
        screen = .project(panel)
        if panel == .settings {
            loadMemorySnapshot()
        }
    }

    func refreshFiles() {
        do {
            if activeProjectPath != nil, case .project = screen {
                files = try bridge.call("list_dir_files", params: ["path": projectRootPath], as: [FileEntry].self)
                reloadExpandedFolders()
            } else {
                files = try bridge.call("list_workspace_files", as: [FileEntry].self)
                rebuildProjects()
            }
            status = "Files refreshed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadProjectFiles() {
        do {
            files = try bridge.call("list_dir_files", params: ["path": projectRootPath], as: [FileEntry].self)
            updateFunctionRegistry()
            status = activeProjectName.isEmpty ? "Project opened" : "Opened \(activeProjectName)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Project open failed"
        }
    }

    func selectWorkspacePanel(_ panel: WorkspacePanel) {
        workspacePanel = panel
        if panel == .cliMarket || panel == .cliManagement || panel == .skillMarket || panel == .skillManagement || panel == .modelManagement {
            ensureWorkspaceManagementDataLoaded()
        }
        if panel == .settings {
            loadMemorySnapshot()
        }
    }

    func ensureWorkspaceManagementDataLoaded() {
        guard !workspaceManagementDataLoaded else { return }
        loadWorkspaceManagementData(includeRemote: false)
    }

    func loadWorkspaceManagementData(reportErrors: Bool = true, includeRemote: Bool = true) {
        if workspaceManagementDataLoaded && !includeRemote {
            return
        }
        let previousError = errorMessage
        refreshRegistry()
        loadActiveConfig()
        loadProviderStatuses()
        if includeRemote {
            syncHermesWorkspaceBridge()
            refreshHermesSkillCatalog()
        }
        refreshSkills()
        refreshTronhub()
        if !reportErrors {
            errorMessage = previousError
        }
        workspaceManagementDataLoaded = true
    }

    func refreshRegistry() {
        do {
            cliRegistry = try bridge.call("list_tools", as: [CLIManifest].self)
            status = "Registry refreshed"
        } catch {
            errorMessage = error.localizedDescription
            status = "Registry failed"
        }
    }

    func loadActiveConfig() {
        do {
            activeConfig = try bridge.call("get_active_config", as: ActiveConfig.self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProviderStatuses() {
        do {
            providerStatuses = try bridge.call("get_auth_status", as: [ProviderStatus].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActiveConfig(provider: String, model: String) {
        do {
            try bridge.callVoid("set_active_config", params: ["provider": provider, "model": model])
            loadActiveConfig()
            status = "已切换到 \(model)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkHermesInstall() {
        runHermesReport(method: "hermes_status_report", params: [:], successStatus: "Hermes install checked")
    }

    func runHermesDoctor() {
        runHermesReport(method: "hermes_doctor", params: [:], successStatus: "Hermes doctor completed")
    }

    func checkHermesAuth(provider: String = "codex") {
        runHermesReport(
            method: "hermes_provider_link_status",
            params: ["provider": provider],
            successStatus: "Hermes \(provider) link checked"
        )
    }

    func openHermesModelInstructions() {
        hermesCommandOutput = HermesCommandReport(
            success: true,
            output: """
            Run `hermes model` in Terminal to link Codex, Claude Code / Anthropic, or an API-key provider.

            Current checks in ScripTron:
            - Codex button: Hermes auth plus local `codex --version`
            - Claude Code button: Hermes auth plus local `claude --version` and `ANTHROPIC_API_KEY`
            - API button: Hermes OpenAI auth plus `OPENAI_API_KEY` / `OPENROUTER_API_KEY`

            After setup, return to ScripTron, click Refresh, then run a .tron Run block.
            """,
            exit_code: 0
        )
        status = "Hermes model setup instructions ready"
    }

    private func runHermesReport(method: String, params: [String: String], successStatus: String) {
        status = "Running \(method)"
        let bridge = bridge
        let params = params
        Task.detached(priority: .userInitiated) {
            do {
                let report = try bridge.call(method, params: params, as: HermesCommandReport.self)
                await MainActor.run {
                    self.hermesCommandOutput = report
                    self.status = report.success ? successStatus : "Hermes command failed"
                    if !report.success {
                        self.errorMessage = report.output
                    }
                    self.loadProviderStatuses()
                }
            } catch {
                await MainActor.run {
                    self.hermesCommandOutput = HermesCommandReport(
                        success: false,
                        output: error.localizedDescription,
                        exit_code: -1
                    )
                    self.errorMessage = error.localizedDescription
                    self.status = "Hermes command failed"
                }
            }
        }
    }

    func runPluginLogin(_ name: String) {
        pluginLoginRunning = name
        status = "正在登录 \(name)..."
        let bridge = bridge
        Task.detached(priority: .userInitiated) {
            do {
                let output = try bridge.call(
                    "run_plugin_login",
                    params: ["name": name],
                    as: String.self
                )
                await MainActor.run {
                    self.pluginLoginRunning = nil
                    self.pluginLoginOutput = (name: name, output: output)
                    self.status = "\(name) 登录完成"
                }
            } catch {
                await MainActor.run {
                    self.pluginLoginRunning = nil
                    self.pluginLoginOutput = (name: name, output: error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.status = "\(name) 登录失败"
                }
            }
        }
    }

    func syncTronhub() {
        do {
            try bridge.callVoid("sync_tronhub")
            refreshRegistry()
            refreshSkills()
            refreshTronhub()
            loadActiveConfig()
            status = "TronHub synced"
        } catch {
            errorMessage = error.localizedDescription
            status = "TronHub sync failed"
        }
    }

    func refreshTronhub() {
        do {
            tronhubClis = try bridge.call("list_tronhub", params: ["kind": "cli"], as: [TronhubEntry].self)
            tronhubModels = try bridge.call("list_tronhub", params: ["kind": "model"], as: [TronhubEntry].self)
            tronhubSkills = try bridge.call("list_tronhub", params: ["kind": "skill"], as: [TronhubEntry].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSkills() {
        do {
            installedSkills = try bridge.call("list_skills", as: [SkillEntry].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var skillMarketCatalogItems: [ExtensionCatalogItem] {
        let tronhubItems = tronhubSkills.map(ExtensionCatalogFixtures.fromTronhub)
        if hermesSkillCatalog.isEmpty && tronhubItems.isEmpty {
            return ExtensionCatalogFixtures.hermesSkillItems
        }
        return hermesSkillCatalog + tronhubItems
    }

    var cliMarketCatalogItems: [ExtensionCatalogItem] {
        let hermesCliWrappers = hermesSkillCatalog
            .filter(\.wrapsExternalCLI)
            .map { item in
                ExtensionCatalogItem(
                    name: item.name,
                    kind: .cli,
                    source: item.source,
                    category: item.category,
                    trustLevel: item.trustLevel,
                    description: item.description,
                    installed: item.installed,
                    wrapsExternalCLI: true,
                    hermesCompatible: item.hermesCompatible,
                    installRef: item.installRef,
                    tags: item.tags,
                    icon: item.icon
                )
            }
        let tronhubItems = tronhubClis.map(ExtensionCatalogFixtures.fromTronhub)
        if hermesCliWrappers.isEmpty && tronhubItems.isEmpty {
            return ExtensionCatalogFixtures.hermesCLIItems
        }
        return hermesCliWrappers + tronhubItems
    }

    func syncHermesWorkspaceBridge() {
        do {
            try bridge.callVoid("sync_hermes_workspace_bridge")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHermesSkillCatalog() {
        do {
            let entries = try bridge.call("hermes_skills_browse", as: [HermesSkillCatalogEntry].self)
            hermesSkillCatalog = entries.map(\.catalogItem)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installCatalogItem(_ item: ExtensionCatalogItem) {
        if item.source == .hermesHub || item.hermesCompatible {
            do {
                try bridge.callVoid("hermes_skills_install", params: ["install_ref": item.installRef ?? item.name])
                refreshHermesSkillCatalog()
                refreshSkills()
                status = "Installed \(item.name) through Hermes"
            } catch {
                errorMessage = error.localizedDescription
                status = "Install failed"
            }
            return
        }

        if let entry = (tronhubSkills + tronhubClis).first(where: { $0.name == item.name }) {
            installTronhub(entry)
        }
    }

    func installTronhub(_ entry: TronhubEntry) {
        do {
            try bridge.callVoid("install_tronhub", params: ["kind": entry.kind, "name": entry.name])
            refreshRegistry()
            refreshSkills()
            refreshTronhub()
            loadActiveConfig()
            status = "已复制 \(entry.name) 文件，正在执行 install.sh..."
            // For cli/model plugins, run install.sh asynchronously to install the underlying tool.
            if entry.kind == "cli" || entry.kind == "model" {
                runPluginInstallScript(kind: entry.kind, name: entry.name)
            } else {
                status = "Installed \(entry.name)"
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "Install failed"
        }
    }

    func runPluginInstallScript(kind: String, name: String) {
        pluginLoginRunning = name
        let bridge = bridge
        Task.detached(priority: .userInitiated) {
            do {
                let output = try bridge.call(
                    "run_plugin_install_script",
                    params: ["kind": kind, "name": name],
                    as: String.self
                )
                await MainActor.run {
                    self.pluginLoginRunning = nil
                    self.pluginLoginOutput = (name: "\(name) (install.sh)", output: output)
                    self.status = "\(name) 安装完成"
                    self.refreshRegistry()
                }
            } catch {
                await MainActor.run {
                    self.pluginLoginRunning = nil
                    self.pluginLoginOutput = (name: "\(name) (install.sh)", output: error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.status = "\(name) 安装失败"
                }
            }
        }
    }

    func installCLIManifest(_ manifestJSON: String) {
        do {
            try bridge.callVoid("install_tool_from_json", params: ["manifest_json": manifestJSON])
            refreshRegistry()
            installManifestDraft = Self.defaultManifestDraft
            status = "CLI installed"
        } catch {
            errorMessage = error.localizedDescription
            status = "CLI install failed"
        }
    }

    func removeCLI(_ manifest: CLIManifest) {
        do {
            try bridge.callVoid("remove_tool", params: ["name": manifest.name])
            refreshRegistry()
            if activeConfig?.model == manifest.name {
                loadActiveConfig()
            }
            status = "CLI removed"
        } catch {
            errorMessage = error.localizedDescription
            status = "CLI remove failed"
        }
    }

    func removeSkill(_ skill: SkillEntry) {
        do {
            try bridge.callVoid("remove_skill", params: ["name": skill.name])
            refreshSkills()
            refreshTronhub()
            status = "Skill removed"
        } catch {
            errorMessage = error.localizedDescription
            status = "Skill remove failed"
        }
    }

    func activateModelCLI(_ manifest: CLIManifest) {
        do {
            try bridge.callVoid("set_active_config", params: ["provider": "openai", "model": manifest.name])
            loadActiveConfig()
            status = "Model set to \(manifest.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Model switch failed"
        }
    }

    func createProject(named rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Project name cannot be empty."
            return
        }
        do {
            try bridge.callVoid("create_project", params: ["name": trimmed])
            refreshFiles()
            workspacePanel = .allProjects
            status = "Created project \(trimmed)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Create project failed"
        }
    }

    func importProjectZipDrops(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        status = "Importing zip project..."

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard let self else { return }
                guard let sourceURL = Self.fileURL(from: item), error == nil else {
                    Task { @MainActor in
                        self.errorMessage = error?.localizedDescription ?? "Could not read dropped zip file."
                        self.status = "Import failed"
                    }
                    return
                }

                Task { @MainActor in
                    self.startZipProjectImport(from: sourceURL)
                }
            }
        }

        return true
    }

    private func startZipProjectImport(from sourceURL: URL) {
        let bridge = self.bridge
        Task.detached(priority: .userInitiated) {
            do {
                let result: ProjectItem = try bridge.call(
                    "import_zip_project",
                    params: ["path": sourceURL.path],
                    as: ProjectItem.self
                )
                await MainActor.run {
                    self.workspacePanel = .allProjects
                    self.refreshFiles()
                    self.status = "Imported \(result.name)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = "Import failed"
                }
            }
        }
    }

    func archiveProject(_ project: ProjectItem) {
        do {
            try bridge.callVoid("archive_project", params: ["path": project.path])
            refreshFiles()
            status = "\(project.name): Archived"
        } catch {
            errorMessage = error.localizedDescription
            status = "Archive project failed"
        }
    }

    func restoreProject(_ project: ProjectItem) {
        do {
            try bridge.callVoid("restore_project", params: ["path": project.path])
            refreshFiles()
            status = "\(project.name): Ready"
        } catch {
            errorMessage = error.localizedDescription
            status = "Restore project failed"
        }
    }

    func packageProject(_ project: ProjectItem) {
        updateProject(project) { item in
            item.packaged = true
            item.status = "Packaged"
        }
    }

    func deleteProject(_ project: ProjectItem) {
        do {
            try bridge.callVoid("delete_project", params: ["path": project.path])
            refreshFiles()
            status = "Deleted \(project.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Delete project failed"
        }
    }

    func sendAgentMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(ChatMessage(role: "user", content: trimmed))
        agentBusy = true
        chatMessages.append(ChatMessage(role: "agent", content: "Troner Agent is working..."))
        let placeholderID = chatMessages.last?.id
        let bridge = bridge
        let projectPath = activeProjectPath ?? workspacePath
        Task.detached(priority: .userInitiated) {
            let response: String
            do {
                response = try bridge.call(
                    "troner_agent_message",
                    params: [
                        "message": trimmed,
                        "project_path": projectPath
                    ],
                    as: String.self
                )
            } catch {
                response = "Error: \(error.localizedDescription)"
            }

            await MainActor.run {
                if let placeholderID, let index = self.chatMessages.firstIndex(where: { $0.id == placeholderID }) {
                    self.chatMessages[index] = ChatMessage(role: "agent", content: response)
                } else {
                    self.chatMessages.append(ChatMessage(role: "agent", content: response))
                }
                self.agentBusy = false
            }
        }
    }

    func loadMemorySnapshot() {
        do {
            memorySnapshot = try bridge.call(
                "get_memory_snapshot",
                params: ["project_path": activeProjectPath ?? ""],
                as: MemorySnapshot.self
            )
            status = "Memory loaded"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGlobalMemory(_ memory: GlobalMemory) {
        do {
            try bridge.callVoid("update_global_memory", params: ["global_memory": try encodeJSONObject(memory)])
            loadMemorySnapshot()
            status = "Global memory saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProjectMemory(_ memory: ProjectMemory) {
        do {
            try bridge.callVoid("update_project_memory", params: ["project_memory": try encodeJSONObject(memory)])
            loadMemorySnapshot()
            status = "Project memory saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAppLanguage(_ language: String) {
        appLanguage = language
        UserDefaults.standard.set(language, forKey: "scriptron.appLanguage")
        status = language == "zh" ? "Language set to Chinese" : "Language set to English"
    }

    func factoryResetAppState() {
        do {
            try bridge.callVoid("factory_reset_app_state")
            UserDefaults.standard.set("en", forKey: "scriptron.appLanguage")
            appLanguage = "en"
            refreshFiles()
            loadWorkspaceManagementData(includeRemote: false)
            loadMemorySnapshot()
            status = "Factory settings restored"
        } catch {
            errorMessage = error.localizedDescription
            status = "Factory reset failed"
        }
    }

    func tr(_ english: String, _ chinese: String) -> String {
        appLanguage == "zh" ? chinese : english
    }

    func workspacePanelTitle(_ panel: WorkspacePanel) -> String {
        switch panel {
        case .allProjects: tr("All Projects", "所有项目")
        case .archived: tr("Archived", "归档")
        case .cliMarket: tr("CLI Market", "CLI 市场")
        case .cliManagement: tr("CLI Management", "CLI 管理")
        case .skillMarket: tr("Skill Market", "Skill 市场")
        case .skillManagement: tr("Skill Management", "Skill 管理")
        case .modelManagement: tr("Model Management", "模型管理")
        case .settings: tr("Settings", "设置")
        }
    }

    func searchMentions(query: String) {
        do {
            updateFunctionRegistry()
            mentionSearch = try bridge.call(
                "search_mentions",
                params: [
                    "query": query,
                    "project_path": activeProjectPath ?? workspacePath
                ],
                as: MentionSearchResult.self
            )
            status = "Mentions searched"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateFunctionRegistry() {
        guard let rootPath = activeProjectPath, !rootPath.isEmpty else {
            functionMentions = []
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        var mentions: [MentionItem] = []

        if let activePath = selectedFile?.path {
            mentions.append(contentsOf: Self.functionMentions(
                in: activePath,
                cells: Self.cells(from: documentBlocks),
                rootURL: rootURL
            ))
        }

        let manager = FileManager.default
        if let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "tron" && url.path != selectedFile?.path {
                let cells = (try? String(contentsOf: url, encoding: .utf8))
                    .flatMap { Self.parseTronCellsForRegistry($0) } ?? []
                mentions.append(contentsOf: Self.functionMentions(in: url.path, cells: cells, rootURL: rootURL))
            }
        }

        functionMentions = mentions.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        persistFunctionRegistry(rootURL: rootURL, mentions: functionMentions)
    }

    func selectMention(_ item: MentionItem, module: MentionModule? = nil) {
        selectedMentions.append(item)
        do {
            var reference: [String: Any] = [
                "kind": item.kind,
                "target": item.path,
                "label": item.label,
                "injection": module?.injection ?? (item.kind == "tron" ? "module_pending" : "attachment")
            ]
            if let module {
                reference["module"] = module.name
                reference["module_kind"] = module.kind
            }
            try bridge.callVoid("record_mention_reference", params: [
                "reference": reference
            ])
            status = "Mention recorded"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFile(_ file: FileEntry) {
        if file.is_dir {
            toggleFolder(file)
            return
        }
        if activeTabPath != file.path {
            stashActiveTabState()
        }
        if !file.is_tron {
            openExternalFile(file)
            return
        }
        if let cached = tronTabStates[file.path] {
            selectedFile = cached.file
            openedFile = nil
            registerOpenTab(file)
            draftCells = cached.draftCells
            documentBlocks = cached.documentBlocks
            selectedDocumentBlockIDs = []
            lastSelectedDocumentBlockID = nil
            updateFunctionRegistry()
            isDirty = cached.dirty
            screen = .project(.explorer)
            status = "Opened \(file.name)"
            return
        }
        do {
            selectedFile = try bridge.call("open_tron_file", params: ["path": file.path], as: TronFile.self)
            openedFile = nil
            registerOpenTab(file)
            draftCells = selectedFile?.cells ?? []
            documentBlocks = Self.documentBlocks(from: draftCells)
            selectedDocumentBlockIDs = []
            lastSelectedDocumentBlockID = nil
            updateFunctionRegistry()
            isDirty = false
            screen = .project(.explorer)
            status = "Opened \(file.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activateTab(_ tab: FileEntry) {
        openFile(tab)
    }

    func closeTab(_ tab: FileEntry) {
        closeTab(tab, discardChanges: false)
    }

    func closeTab(_ tab: FileEntry, discardChanges: Bool) {
        guard let index = openTabs.firstIndex(where: { $0.path == tab.path }) else { return }
        guard discardChanges || !isTabDirty(tab) else { return }
        let wasActive = activeTabPath == tab.path
        openTabs.remove(at: index)
        externalTabStates.removeValue(forKey: tab.path)
        tronTabStates.removeValue(forKey: tab.path)
        dirtyTabPaths.remove(tab.path)

        guard wasActive else { return }
        if openTabs.isEmpty {
            activeTabPath = nil
            selectedFile = nil
            openedFile = nil
            draftCells = []
            documentBlocks = []
            isDirty = false
            status = "No file open"
            return
        }

        let nextIndex = min(index, openTabs.count - 1)
        openFile(openTabs[nextIndex])
    }

    private func registerOpenTab(_ file: FileEntry) {
        if !openTabs.contains(where: { $0.path == file.path }) {
            openTabs.append(file)
        }
        activeTabPath = file.path
    }

    func isTabDirty(_ tab: FileEntry) -> Bool {
        dirtyTabPaths.contains(tab.path)
    }

    private func stashActiveTabState() {
        guard let path = activeTabPath else { return }
        if let openedFile {
            externalTabStates[path] = ExternalTabState(file: openedFile, dirty: isDirty)
        } else if let selectedFile {
            tronTabStates[path] = TronTabState(
                file: selectedFile,
                draftCells: draftCells,
                documentBlocks: documentBlocks,
                dirty: isDirty
            )
        }

        if isDirty {
            dirtyTabPaths.insert(path)
        } else {
            dirtyTabPaths.remove(path)
        }
    }

    private func markActiveTabDirty() {
        isDirty = true
        if let activeTabPath {
            dirtyTabPaths.insert(activeTabPath)
        }
    }

    private func clearActiveTabDirty() {
        isDirty = false
        if let activeTabPath {
            dirtyTabPaths.remove(activeTabPath)
        }
    }

    func runEvents(for block: DocumentBlock) -> [RunEvent] {
        if let events = runEventsByBlockID[block.id], !events.isEmpty {
            return events
        }
        return runEventsByBlockKey[runEventKey(for: block)] ?? []
    }

    private func runEventKey(for block: DocumentBlock) -> String {
        let filePath = selectedFile?.path ?? activeTabPath ?? ""
        let name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = name.isEmpty ? block.content.trimmingCharacters(in: .whitespacesAndNewlines) : name
        return "\(filePath)#\(identity)"
    }

    func toggleFolder(_ folder: FileEntry) {
        guard folder.is_dir else { return }
        if expandedFolders.contains(folder.path) {
            expandedFolders.remove(folder.path)
        } else {
            expandedFolders.insert(folder.path)
            loadChildren(for: folder.path)
        }
    }

    func loadChildren(for folderPath: String) {
        do {
            folderChildren[folderPath] = try bridge.call("list_dir_files", params: ["path": folderPath], as: [FileEntry].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginDraggingFile(_ path: String) {
        draggedFilePath = path
        dropHoverFolderPath = nil
    }

    func hoverDropFolder(_ path: String?) {
        dropHoverFolderPath = path
    }

    func endDraggingFile() {
        draggedFilePath = nil
        dropHoverFolderPath = nil
    }

    func finishDropInteraction() {
        dropHoverFolderPath = nil
    }

    func updateOpenedFileContent(_ content: String) {
        openedFile?.content = content
        markActiveTabDirty()
    }

    func createScript(named rawName: String) {
        createFile(named: rawName, fileExtension: "tron")
    }

    func createFile(named rawName: String, fileExtension rawExtension: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "File name cannot be empty."
            return
        }

        let normalizedExtension = normalizedFileExtension(rawExtension)
        guard !normalizedExtension.isEmpty else {
            errorMessage = "File extension cannot be empty."
            return
        }

        let fileName = fileNameForCreation(baseName: trimmed, fileExtension: normalizedExtension)
        let path = "\(projectRootPath)/\(fileName)"

        if normalizedExtension == "tron" {
            createTronFile(path: path, fileName: fileName)
        } else {
            createPlainFile(path: path, fileName: fileName)
        }
    }

    func createFolder(named rawName: String) {
        let trimmed = sanitizedPathComponent(rawName)
        guard !trimmed.isEmpty else {
            errorMessage = "Folder name cannot be empty."
            return
        }

        do {
            let created = try bridge.call(
                "create_folder",
                params: ["parent_path": projectRootPath, "name": trimmed],
                as: FileEntry.self
            )
            refreshFiles()
            status = "Created folder \(created.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Create folder failed"
        }
    }

    func renameFile(_ file: FileEntry, to rawName: String) {
        let trimmed = sanitizedPathComponent(rawName)
        guard !trimmed.isEmpty else {
            errorMessage = "Name cannot be empty."
            return
        }

        do {
            let renamed = try bridge.call(
                "rename_entry",
                params: ["path": file.path, "name": trimmed],
                as: FileEntry.self
            )
            if selectedFile?.path == file.path || openedFile?.path == file.path {
                selectedFile = nil
                openedFile = nil
                draftCells = []
                documentBlocks = []
                isDirty = false
            }
            openTabs.removeAll { $0.path == file.path }
            if activeTabPath == file.path { activeTabPath = nil }
            refreshFiles()
            status = "Renamed to \(renamed.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Rename failed"
        }
    }

    func deleteFile(_ file: FileEntry) {
        do {
            try bridge.callVoid("delete_entry", params: ["path": file.path])
            if selectedFile?.path == file.path || openedFile?.path == file.path {
                selectedFile = nil
                openedFile = nil
                draftCells = []
                documentBlocks = []
                isDirty = false
            }
            openTabs.removeAll { $0.path == file.path || $0.path.hasPrefix(file.path + "/") }
            if activeTabPath == file.path || activeTabPath?.hasPrefix(file.path + "/") == true {
                activeTabPath = nil
            }
            refreshFiles()
            status = "Deleted \(file.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Delete failed"
        }
    }

    private func createTronFile(path: String, fileName: String) {
        do {
            selectedFile = try bridge.call("create_tron_file", params: ["path": path], as: TronFile.self)
            draftCells = []
            documentBlocks = []
            isDirty = false
            refreshFiles()
            screen = .project(.explorer)
            status = "Created \(fileName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createPlainFile(path: String, fileName: String) {
        let requestedURL = URL(fileURLWithPath: path)

        do {
            let created = try bridge.call(
                "create_file",
                params: [
                    "parent_path": requestedURL.deletingLastPathComponent().path,
                    "name": requestedURL.lastPathComponent
                ],
                as: FileEntry.self
            )
            refreshFiles()
            selectedFile = nil
            openedFile = nil
            activeTabPath = nil
            draftCells = []
            documentBlocks = []
            isDirty = false
            screen = .project(.explorer)
            status = "Created \(created.name)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Create failed"
        }
    }

    func copyDroppedFiles(_ providers: [NSItemProvider], to targetDirectoryPath: String? = nil) -> Bool {
        guard !providers.isEmpty else { return false }
        status = "Copying dropped files..."

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard let sourceURL = Self.fileURL(from: item), error == nil else {
                    Task { @MainActor in
                        self?.errorMessage = error?.localizedDescription ?? "Could not read dropped file."
                        self?.status = "Drop failed"
                    }
                    return
                }

                Task { @MainActor in
                    self?.copyDroppedFile(from: sourceURL, to: targetDirectoryPath)
                }
            }
        }

        return true
    }

    func moveDroppedFiles(_ providers: [NSItemProvider], to targetDirectoryPath: String? = nil) -> Bool {
        guard !providers.isEmpty else { return false }
        status = "Moving dropped files..."

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard let sourceURL = Self.fileURL(from: item), error == nil else {
                    Task { @MainActor in
                        self?.errorMessage = error?.localizedDescription ?? "Could not read dragged file."
                        self?.status = "Move failed"
                        self?.endDraggingFile()
                    }
                    return
                }

                Task { @MainActor in
                    self?.moveDroppedFile(from: sourceURL, to: targetDirectoryPath)
                }
            }
        }

        return true
    }

    func moveInternalDroppedFiles(_ providers: [NSItemProvider], to targetDirectoryPath: String? = nil) -> Bool {
        guard !providers.isEmpty else { return false }
        status = "Moving files..."

        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.scriptronFilePath.identifier) { [weak self] data, error in
                guard let data,
                      let path = String(data: data, encoding: .utf8),
                      error == nil else {
                    Task { @MainActor in
                        self?.errorMessage = error?.localizedDescription ?? "Could not read dragged file."
                        self?.status = "Move failed"
                    }
                    return
                }

                Task { @MainActor in
                    self?.moveDroppedFile(from: URL(fileURLWithPath: path), to: targetDirectoryPath)
                }
            }
        }

        return true
    }

    func moveTextDroppedFiles(_ providers: [NSItemProvider], to targetDirectoryPath: String? = nil) -> Bool {
        guard !providers.isEmpty else { return false }
        status = "Moving files..."

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] item, error in
                guard let path = Self.string(from: item), error == nil else {
                    Task { @MainActor in
                        self?.errorMessage = error?.localizedDescription ?? "Could not read dragged file."
                        self?.status = "Move failed"
                        self?.endDraggingFile()
                    }
                    return
                }

                Task { @MainActor in
                    self?.moveDroppedFile(from: URL(fileURLWithPath: path), to: targetDirectoryPath)
                }
            }
        }

        return true
    }

    func updateCell(_ cell: TronCell, content: String) {
        guard let index = draftCells.firstIndex(where: { $0.id == cell.id }) else { return }
        draftCells[index].content = content
        markActiveTabDirty()
    }

    func updateDocumentBlock(_ block: DocumentBlock, content: String) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].content = content
        ensureTrailingBlankLine()
        markActiveTabDirty()
        updateFunctionRegistry()
    }

    func updateRunBlockName(_ block: DocumentBlock, name: String) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].name = sanitizedFunctionName(name)
        markActiveTabDirty()
        updateFunctionRegistry()
    }

    func insertDocumentBlock(after block: DocumentBlock?, kind: DocumentBlockKind) {
        let newBlock = DocumentBlock(kind: kind, content: defaultContent(for: kind))
        insertDocumentBlocks([newBlock], after: block)
    }

    func insertTable(after block: DocumentBlock?) {
        insertDocumentBlocks([DocumentBlock(kind: .table, content: """
        | Column 1 | Column 2 | Column 3 |
        | --- | --- | --- |
        |  |  |  |
        |  |  |  |
        """)], after: block)
    }

    func insertDivider(after block: DocumentBlock?) {
        insertDocumentBlocks([DocumentBlock(kind: .divider, content: "")], after: block)
    }

    func convertBlock(_ block: DocumentBlock, to kind: DocumentBlockKind) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].kind = kind
        if documentBlocks[index].content.isEmpty {
            documentBlocks[index].content = defaultContent(for: kind)
        }
        markActiveTabDirty()
    }

    func setHeading(_ block: DocumentBlock, level: Int) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].kind = .heading(max(1, min(level, 3)))
        documentBlocks[index].content = cleanMarkdownPrefix(documentBlocks[index].content)
        markActiveTabDirty()
    }

    func toggleOrderedList(_ block: DocumentBlock) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].kind = .list(true)
        documentBlocks[index].content = listBody(from: documentBlocks[index].content, ordered: true)
        markActiveTabDirty()
    }

    func toggleBulletList(_ block: DocumentBlock) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].kind = .list(false)
        documentBlocks[index].content = listBody(from: documentBlocks[index].content, ordered: false)
        markActiveTabDirty()
    }

    private func insertDocumentBlocks(_ newBlocks: [DocumentBlock], after block: DocumentBlock?) {
        guard !newBlocks.isEmpty else { return }
        guard let block, let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else {
            documentBlocks.insert(contentsOf: newBlocks, at: 0)
            ensureTrailingBlankLine()
            markActiveTabDirty()
            return
        }
        documentBlocks.insert(contentsOf: newBlocks, at: documentBlocks.index(after: index))
        ensureTrailingBlankLine()
        markActiveTabDirty()
    }

    func deleteDocumentBlock(_ block: DocumentBlock) {
        documentBlocks.removeAll { $0.id == block.id }
        selectedDocumentBlockIDs.remove(block.id)
        ensureTrailingBlankLine()
        markActiveTabDirty()
        updateFunctionRegistry()
    }

    func selectDocumentBlock(_ block: DocumentBlock, toggling: Bool = false, extending: Bool = false) {
        if extending,
           let lastSelectedDocumentBlockID,
           let start = documentBlocks.firstIndex(where: { $0.id == lastSelectedDocumentBlockID }),
           let end = documentBlocks.firstIndex(where: { $0.id == block.id }) {
            let range = start <= end ? start...end : end...start
            selectedDocumentBlockIDs = Set(documentBlocks[range].map(\.id))
        } else if toggling {
            if selectedDocumentBlockIDs.contains(block.id) {
                selectedDocumentBlockIDs.remove(block.id)
            } else {
                selectedDocumentBlockIDs.insert(block.id)
            }
            lastSelectedDocumentBlockID = block.id
        } else {
            selectedDocumentBlockIDs = [block.id]
            lastSelectedDocumentBlockID = block.id
        }
    }

    func clearDocumentBlockSelection() {
        selectedDocumentBlockIDs = []
        lastSelectedDocumentBlockID = nil
    }

    func deleteSelectedDocumentBlocks() {
        guard !selectedDocumentBlockIDs.isEmpty else { return }
        documentBlocks.removeAll { selectedDocumentBlockIDs.contains($0.id) }
        selectedDocumentBlockIDs = []
        lastSelectedDocumentBlockID = nil
        ensureTrailingBlankLine()
        markActiveTabDirty()
        updateFunctionRegistry()
        status = "Deleted selected blocks"
    }

    func deleteEmptyMarkdownBlockBefore(_ block: DocumentBlock) {
        guard block.kind == .markdownLine,
              block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = documentBlocks.firstIndex(where: { $0.id == block.id }),
              index < documentBlocks.count - 1 || documentBlocks.count > 1 else {
            return
        }
        documentBlocks.remove(at: index)
        selectedDocumentBlockIDs.remove(block.id)
        ensureTrailingBlankLine()
        markActiveTabDirty()
    }

    private func ensureTrailingBlankLine() {
        while documentBlocks.count > 1,
              let last = documentBlocks.last,
              let previous = documentBlocks.dropLast().last,
              last.kind == .markdownLine,
              previous.kind == .markdownLine,
              last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              previous.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            documentBlocks.removeLast()
        }
        guard let last = documentBlocks.last else {
            documentBlocks = [DocumentBlock(kind: .markdownLine, content: "")]
            return
        }
        if last.kind != .markdownLine || !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            documentBlocks.append(DocumentBlock(kind: .markdownLine, content: ""))
        }
    }

    func insertMarkdownLine(after block: DocumentBlock, content: String = "") {
        insertDocumentBlocks([DocumentBlock(kind: .markdownLine, content: content)], after: block)
    }

    func continueMarkdownLine(after block: DocumentBlock) {
        // If this is the trailing blank (last empty block), inserting after it would be
        // immediately collapsed by ensureTrailingBlankLine. Insert before it instead so
        // the new block becomes the new trailing blank's predecessor and stays alive.
        let isTrailingBlank = documentBlocks.last?.id == block.id
            && block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isTrailingBlank, let index = documentBlocks.firstIndex(where: { $0.id == block.id }) {
            let newBlock = DocumentBlock(kind: .markdownLine, content: "")
            documentBlocks.insert(newBlock, at: index)
            focusedBlockID = newBlock.id
            ensureTrailingBlankLine()
            markActiveTabDirty()
        } else {
            insertMarkdownLine(after: block)
        }
    }

    func continueListBlock(after block: DocumentBlock, ordered: Bool) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        var lines = documentBlocks[index].content.components(separatedBy: .newlines)
        if lines.isEmpty { lines = [""] }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("")
        }
        documentBlocks[index].content = lines.joined(separator: "\n")
        markActiveTabDirty()
    }

    func generateMarkdown(from block: DocumentBlock) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        let prompt = block.content
        let bridge = bridge
        let projectPath = projectRootPath
        status = "Generating markdown"
        Task.detached(priority: .userInitiated) {
            let request = """
            You are Troner's Gen Cell. Convert the user's natural language description into clean Markdown only.
            Return only Markdown. Include editable markdown tables when useful. Do not wrap the result in code fences.

            User request:
            \(prompt)
            """
            let markdown: String
            do {
                markdown = try bridge.call(
                    "troner_agent_message",
                    params: ["message": request, "project_path": projectPath],
                    as: String.self
                )
            } catch {
                markdown = Self.markdownFromNaturalLanguage(prompt)
            }
            await MainActor.run {
                guard self.documentBlocks.indices.contains(index), self.documentBlocks[index].id == block.id else { return }
                let lines = Self.markdownLineBlocks(from: markdown)
                self.documentBlocks.remove(at: index)
                self.documentBlocks.insert(contentsOf: lines, at: index)
                self.ensureTrailingBlankLine()
                self.markActiveTabDirty()
                self.status = "Generated markdown"
            }
        }
    }

    private func defaultContent(for kind: DocumentBlockKind) -> String {
        switch kind {
        case .markdownLine: ""
        case .heading: "Heading"
        case .list: "List item"
        case .table:
            """
            | Column 1 | Column 2 | Column 3 |
            | --- | --- | --- |
            |  |  |  |
            """
        case .quote: "Quote"
        case .code: ""
        case .checklist: "Todo"
        case .divider: ""
        case .run: ""
        case .gen: ""
        }
    }

    func toggleCell(_ cell: TronCell) {
        guard let index = draftCells.firstIndex(where: { $0.id == cell.id }) else { return }
        draftCells[index].run.toggle()
        markActiveTabDirty()
    }

    func addCell(run: Bool) {
        draftCells.append(TronCell(run: run, content: ""))
        markActiveTabDirty()
    }

    func insertCell(after cell: TronCell?, run: Bool) {
        let newCell = TronCell(run: run, content: "")
        guard let cell, let index = draftCells.firstIndex(where: { $0.id == cell.id }) else {
            draftCells.insert(newCell, at: 0)
            markActiveTabDirty()
            return
        }
        draftCells.insert(newCell, at: draftCells.index(after: index))
        markActiveTabDirty()
    }

    func insertGenCell(after cell: TronCell?) {
        let newCell = TronCell(run: true, content: "\(Self.genCellPrefix)\n")
        guard let cell, let index = draftCells.firstIndex(where: { $0.id == cell.id }) else {
            draftCells.insert(newCell, at: 0)
            markActiveTabDirty()
            return
        }
        draftCells.insert(newCell, at: draftCells.index(after: index))
        markActiveTabDirty()
    }

    func isGenCell(_ cell: TronCell) -> Bool {
        cell.run && cell.content.hasPrefix(Self.genCellPrefix)
    }

    func genPrompt(for cell: TronCell) -> String {
        guard isGenCell(cell) else { return cell.content }
        return String(cell.content.dropFirst(Self.genCellPrefix.count)).trimmingCharacters(in: .newlines)
    }

    func updateGenPrompt(_ cell: TronCell, prompt: String) {
        updateCell(cell, content: "\(Self.genCellPrefix)\n\(prompt)")
    }

    func generateMarkdown(from cell: TronCell) {
        let prompt = genPrompt(for: cell)
        let markdown = Self.markdownFromNaturalLanguage(prompt)
        guard let index = draftCells.firstIndex(where: { $0.id == cell.id }) else { return }
        draftCells[index] = TronCell(run: false, content: markdown)
        markActiveTabDirty()
        status = "Generated markdown"
    }

    func deleteCell(_ cell: TronCell) {
        guard draftCells.count > 1 else { return }
        draftCells.removeAll { $0.id == cell.id }
        markActiveTabDirty()
    }

    func saveSelectedFile() {
        if let file = openedFile {
            do {
                try bridge.callVoid("save_plain_file", params: ["path": file.path, "content": file.content])
                openedFile = file
                if let activeTabPath {
                    externalTabStates[activeTabPath] = ExternalTabState(file: file, dirty: false)
                }
                clearActiveTabDirty()
                status = "Saved \(file.name)"
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let file = selectedFile else {
            errorMessage = "No script is open."
            return
        }
        do {
            let savedCells = Self.cells(from: documentBlocks)
            try bridge.callVoid("save_tron_file", params: [
                "path": file.path,
                "cells": savedCells.map { ["run": $0.run, "content": $0.content] },
                "blackboard": file.blackboard.value
            ])
            selectedFile = TronFile(path: file.path, cells: savedCells, blackboard: file.blackboard)
            draftCells = savedCells
            documentBlocks = Self.documentBlocks(from: draftCells)
            updateFunctionRegistry()
            if let activeTabPath, let selectedFile {
                tronTabStates[activeTabPath] = TronTabState(
                    file: selectedFile,
                    draftCells: draftCells,
                    documentBlocks: documentBlocks,
                    dirty: false
                )
            }
            clearActiveTabDirty()
            status = "Saved \(file.path.split(separator: "/").last ?? "script")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitHermesPrompt() {
        submitHermesPrompt(block: nil)
    }

    func submitHermesPrompt(block: DocumentBlock?) {
        guard let file = selectedFile else {
            errorMessage = "No .tron file is open."
            return
        }
        if let validationError = validateRunReferenceTree(startingAt: block) {
            errorMessage = validationError
            status = "Run validation failed"
            return
        }
        isRunningTask = true
        runEventsBlockID = block?.id
        status = "Submitting Hermes prompt"
        runEvents = []
        let blockKey = block.map { runEventKey(for: $0) }
        if let block {
            let startEvent = RunEvent.local(type: "warning", content: "Hermes gateway submission started...")
            runEventsByBlockID[block.id] = [startEvent]
            if let blockKey {
                runEventsByBlockKey[blockKey] = [startEvent]
            }
        }
        let bridge = bridge
        let taskCells = Self.cells(from: documentBlocks)
        guard let cellsData = try? JSONEncoder().encode(taskCells),
              let blackboardData = try? JSONSerialization.data(withJSONObject: file.blackboard.value) else {
            errorMessage = "Could not encode task inputs."
            status = "Run failed"
            isRunningTask = false
            return
        }
        let projectPath = projectRootPath
        let filePath = file.path
        Task.detached(priority: .userInitiated) {
            do {
                let decodedCells = try JSONDecoder().decode([TronCell].self, from: cellsData)
                let blackboard = try JSONSerialization.jsonObject(with: blackboardData)
                try bridge.callVoid("hermes_prompt_submit", params: [
                    "path": filePath,
                    "cells": decodedCells.map { ["run": $0.run, "content": $0.content] },
                    "project_path": projectPath,
                    "blackboard": blackboard
                ])
                let events = try bridge.call("hermes_poll_events", as: [RunEvent].self)
                let refreshedFile = try? bridge.call("open_tron_file", params: ["path": filePath], as: TronFile.self)
                await MainActor.run {
                    if let refreshedFile {
                        self.selectedFile = refreshedFile
                        if let activeTabPath = self.activeTabPath {
                            self.tronTabStates[activeTabPath] = TronTabState(
                                file: refreshedFile,
                                draftCells: self.draftCells,
                                documentBlocks: self.documentBlocks,
                                dirty: false
                            )
                        }
                    }
                    self.runEvents = events
                    if let block {
                        self.runEventsByBlockID[block.id] = events
                        if let blockKey {
                            self.runEventsByBlockKey[blockKey] = events
                        }
                    }
                    self.clearActiveTabDirty()
                    self.status = "Hermes prompt submitted"
                    self.isRunningTask = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = "Run failed"
                    self.isRunningTask = false
                }
            }
        }
    }

    private func validateRunReferenceTree(startingAt block: DocumentBlock?) -> String? {
        updateFunctionRegistry()
        let graph = functionBodyMap()
        let startNames: [String]
        if let block, block.kind == .run {
            let name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
            startNames = [name.isEmpty ? Self.fallbackFunctionName(from: block.content, index: 0) : name]
        } else {
            startNames = documentBlocks.compactMap { block in
                guard block.kind == .run else { return nil }
                let name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? Self.fallbackFunctionName(from: block.content, index: 0) : name
            }
        }

        var visiting: [String] = []
        var visited = Set<String>()

        func visit(_ name: String, depth: Int) -> String? {
            guard depth <= 5 else { return "Reference tree is deeper than 5 levels near \(name)." }
            if visiting.contains(name) {
                return "Circular run-cell reference detected: \((visiting + [name]).joined(separator: " -> "))"
            }
            guard let body = graph[name] else { return nil }
            if visited.contains(name) { return nil }
            visiting.append(name)
            for reference in Self.extractFunctionReferences(from: body) {
                if let error = visit(reference, depth: depth + 1) {
                    return error
                }
            }
            visiting.removeLast()
            visited.insert(name)
            return nil
        }

        for name in startNames {
            if let error = visit(name, depth: 1) { return error }
        }
        return nil
    }

    private func functionBodyMap() -> [String: String] {
        var graph: [String: String] = [:]
        for (index, block) in documentBlocks.enumerated() where block.kind == .run {
            let name = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
            graph[name.isEmpty ? Self.fallbackFunctionName(from: block.content, index: index) : name] = block.content
        }
        guard let rootPath = activeProjectPath else { return graph }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "tron" && url.path != selectedFile?.path {
                let cells = (try? String(contentsOf: url, encoding: .utf8))
                    .flatMap { Self.parseTronCellsForRegistry($0) } ?? []
                for (index, cell) in cells.enumerated() where cell.run {
                    let parsed = Self.parseRunCellContent(cell.content)
                    let name = parsed.name.isEmpty ? Self.fallbackFunctionName(from: parsed.body, index: index) : parsed.name
                    graph[name] = parsed.body
                }
            }
        }
        return graph
    }

    private func rebuildProjects() {
        do {
            projects = try bridge.call("list_projects", as: [ProjectItem].self)
        } catch {
            errorMessage = error.localizedDescription
            projects = []
        }
    }

    private func openExternalFile(_ file: FileEntry) {
        let url = URL(fileURLWithPath: file.path)
        let viewer = Self.viewerKind(for: url.pathExtension)

        guard viewer != .unsupported else {
            errorMessage = "No viewer is installed for .\(url.pathExtension)."
            status = "Unsupported file"
            return
        }

        if let cached = externalTabStates[file.path] {
            selectedFile = nil
            draftCells = []
            documentBlocks = []
            openedFile = cached.file
            registerOpenTab(file)
            isDirty = cached.dirty
            status = "Opened \(file.name)"
            return
        }

        do {
            let content: String
            if viewer == .code || viewer == .text || viewer == .csv {
                let data = try Data(contentsOf: url)
                guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                    errorMessage = "Could not decode \(file.name) as text."
                    status = "Open failed"
                    return
                }
                content = decoded
            } else {
                content = ""
            }
            selectedFile = nil
            draftCells = []
            documentBlocks = []
            openedFile = OpenedFile(
                name: file.name,
                path: file.path,
                content: content,
                viewer: viewer,
                language: Self.languageName(for: url.pathExtension)
            )
            registerOpenTab(file)
            isDirty = false
            status = "Opened \(file.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadExpandedFolders() {
        let expanded = expandedFolders
        for path in expanded {
            loadChildren(for: path)
        }
    }

    private static func viewerKind(for ext: String) -> ViewerKind {
        let normalized = ext.lowercased()
        if normalized == "csv" { return .csv }
        if normalized == "pdf" { return .pdf }
        if wordExtensions.contains(normalized) { return .word }
        if excelExtensions.contains(normalized) { return .excel }
        if quickLookExtensions.contains(normalized) { return .quickLook }
        if codeExtensions.contains(normalized) { return .code }
        if textExtensions.contains(normalized) { return .text }
        return .unsupported
    }

    private static func languageName(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift": "Swift"
        case "rs": "Rust"
        case "js", "jsx": "JavaScript"
        case "ts", "tsx": "TypeScript"
        case "py": "Python"
        case "go": "Go"
        case "java": "Java"
        case "kt", "kts": "Kotlin"
        case "c", "h": "C"
        case "cpp", "cc", "cxx", "hpp": "C++"
        case "cs": "C#"
        case "rb": "Ruby"
        case "php": "PHP"
        case "html": "HTML"
        case "css": "CSS"
        case "json": "JSON"
        case "md", "markdown": "Markdown"
        case "toml": "TOML"
        case "yaml", "yml": "YAML"
        case "sh", "bash", "zsh": "Shell"
        case "sql": "SQL"
        case "csv": "CSV"
        case "pdf": "PDF"
        case "doc", "docx": "Word"
        case "xls", "xlsx": "Excel"
        default: ext.uppercased()
        }
    }

    private static let codeExtensions: Set<String> = [
        "swift", "rs", "js", "jsx", "ts", "tsx", "py", "go", "java", "kt", "kts",
        "c", "h", "cpp", "cc", "cxx", "hpp", "cs", "rb", "php", "html", "css",
        "json", "toml", "yaml", "yml", "sh", "bash", "zsh", "sql", "xml", "vue",
        "svelte", "dart", "scala", "lua", "r", "m", "mm"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "log", "env", "gitignore", "csv", "tsv"
    ]

    private static let wordExtensions: Set<String> = [
        "doc", "docx", "rtf", "pages"
    ]

    private static let excelExtensions: Set<String> = [
        "xls", "xlsx", "numbers"
    ]

    private static let quickLookExtensions: Set<String> = [
        "ppt", "pptx", "key", "png", "jpg", "jpeg", "gif", "heic", "webp", "svg"
    ]

    private func updateProject(_ project: ProjectItem, mutate: (inout ProjectItem) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        mutate(&projects[index])
        status = "\(projects[index].name): \(projects[index].status)"
    }

    private static let genCellPrefix = "[[scriptron:gen-markdown]]"
    private static let runNamePrefix = "[[scriptron:run-name]]"

    private static func documentBlocks(from cells: [TronCell]) -> [DocumentBlock] {
        var blocks = cells.flatMap { cell -> [DocumentBlock] in
            if cell.run && cell.content.hasPrefix(genCellPrefix) {
                let prompt = String(cell.content.dropFirst(genCellPrefix.count)).trimmingCharacters(in: .newlines)
                return [DocumentBlock(kind: .gen, content: prompt)]
            }
            if cell.run {
                let parsed = parseRunCellContent(cell.content)
                return [DocumentBlock(kind: .run, content: parsed.body, name: parsed.name)]
            }
            return markdownLineBlocks(from: cell.content)
        }
        if blocks.last?.kind != .markdownLine || !(blocks.last?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) {
            blocks.append(DocumentBlock(kind: .markdownLine, content: ""))
        }
        return blocks
    }

    private static func markdownLineBlocks(from markdown: String) -> [DocumentBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [DocumentBlock] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                blocks.append(DocumentBlock(kind: .divider, content: ""))
                index += 1
            } else if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(DocumentBlock(kind: .code, content: codeLines.joined(separator: "\n")))
            } else if let heading = parseHeading(trimmed) {
                blocks.append(DocumentBlock(kind: .heading(heading.level), content: heading.text))
                index += 1
            } else if isChecklistLine(trimmed) {
                var itemLines: [String] = []
                while index < lines.count, isChecklistLine(lines[index].trimmingCharacters(in: .whitespaces)) {
                    itemLines.append(cleanChecklistLine(lines[index]))
                    index += 1
                }
                blocks.append(DocumentBlock(kind: .checklist, content: itemLines.joined(separator: "\n")))
            } else if isOrderedListLine(trimmed) || isBulletListLine(trimmed) {
                let ordered = isOrderedListLine(trimmed)
                var itemLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard ordered ? isOrderedListLine(current) : isBulletListLine(current) else { break }
                    itemLines.append(cleanListLine(current))
                    index += 1
                }
                blocks.append(DocumentBlock(kind: .list(ordered), content: itemLines.joined(separator: "\n")))
            } else if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoteLines.append(lines[index].replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression))
                    index += 1
                }
                blocks.append(DocumentBlock(kind: .quote, content: quoteLines.joined(separator: "\n")))
            } else if index + 1 < lines.count, isMarkdownTableSeparator(lines[index + 1]), lines[index].contains("|") {
                var tableLines = [lines[index], lines[index + 1]]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    tableLines.append(lines[index])
                    index += 1
                }
                blocks.append(DocumentBlock(kind: .table, content: tableLines.joined(separator: "\n")))
            } else {
                blocks.append(DocumentBlock(kind: .markdownLine, content: lines[index]))
                index += 1
            }
        }

        return blocks
    }

    private static func isMarkdownTableSeparator(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty && line.contains("-")
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard let range = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) else { return nil }
        let marker = String(line[range]).trimmingCharacters(in: .whitespaces)
        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (min(marker.count, 3), text)
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private static func isBulletListLine(_ line: String) -> Bool {
        line.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil
    }

    private static func isChecklistLine(_ line: String) -> Bool {
        line.range(of: #"^[-*]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil
    }

    private static func cleanListLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func cleanChecklistLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func parseRunCellContent(_ content: String) -> (name: String, body: String) {
        var lines = content.components(separatedBy: .newlines)
        guard let first = lines.first, first.hasPrefix(runNamePrefix) else {
            return ("", content)
        }
        let name = String(first.dropFirst(runNamePrefix.count)).trimmingCharacters(in: .whitespaces)
        lines.removeFirst()
        return (name, lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    private static func cells(from blocks: [DocumentBlock]) -> [TronCell] {
        var cells: [TronCell] = []
        var markdownBuffer: [String] = []

        func flushMarkdown() {
            while markdownBuffer.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                markdownBuffer.removeLast()
            }
            guard !markdownBuffer.isEmpty else { return }
            cells.append(TronCell(run: false, content: markdownBuffer.joined(separator: "\n")))
            markdownBuffer.removeAll()
        }

        for block in blocks {
            switch block.kind {
            case .markdownLine:
                markdownBuffer.append(block.content)
            case .heading(let level):
                markdownBuffer.append("\(String(repeating: "#", count: max(1, min(level, 3)))) \(block.content)")
            case .list(let ordered):
                for (index, line) in block.content.components(separatedBy: .newlines).enumerated() {
                    markdownBuffer.append(ordered ? "\(index + 1). \(line)" : "- \(line)")
                }
            case .table:
                markdownBuffer.append(block.content)
            case .quote:
                markdownBuffer.append(block.content.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n"))
            case .code:
                markdownBuffer.append("```\n\(block.content)\n```")
            case .checklist:
                for line in block.content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    markdownBuffer.append(trimmed.hasPrefix("[") ? "- \(trimmed)" : "- [ ] \(line)")
                }
            case .divider:
                markdownBuffer.append("---")
            case .run:
                flushMarkdown()
                let prefix = block.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(runNamePrefix) \(block.name)\n"
                cells.append(TronCell(run: true, content: "\(prefix)\(block.content)"))
            case .gen:
                flushMarkdown()
                cells.append(TronCell(run: true, content: "\(genCellPrefix)\n\(block.content)"))
            }
        }

        flushMarkdown()
        return cells
    }

    nonisolated private static func markdownFromNaturalLanguage(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleFromPrompt(trimmed)

        return """
        # \(title)

        ## 文档介绍

        这里填写文档背景、整理目标、适用范围和阅读对象。

        ## 项目内容

        这里填写项目的主要内容、关键节点、负责人和当前状态。

        | 模块 | 内容 | 状态 |
        | --- | --- | --- |
        | 文档介绍 | 补充背景说明 | 待完善 |
        | 项目内容 | 补充项目细节 | 待完善 |
        | 总结 | 补充结论和下一步 | 待完善 |

        ## 总结

        这里填写最终结论、风险提示和下一步行动。
        """
    }

    nonisolated private static func titleFromPrompt(_ prompt: String) -> String {
        guard !prompt.isEmpty else { return "Untitled" }
        if let dashRange = prompt.range(of: " - ") {
            return String(prompt[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let colonRange = prompt.range(of: "：") ?? prompt.range(of: ":") {
            return String(prompt[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prompt.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
    }

    private func normalizedFileExtension(_ rawExtension: String) -> String {
        rawExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func sanitizedFunctionName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    private func cleanMarkdownPrefix(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^>\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func listBody(from text: String, ordered: Bool) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { cleanMarkdownPrefix($0) }
            .filter { !$0.isEmpty }
        return (lines.isEmpty ? ["List item"] : lines).joined(separator: "\n")
    }

    private func fileNameForCreation(baseName: String, fileExtension: String) -> String {
        let sanitizedBaseName = sanitizedPathComponent(baseName)
        let suffix = ".\(fileExtension)"
        if sanitizedBaseName.lowercased().hasSuffix(suffix) {
            return sanitizedBaseName
        }
        return "\(sanitizedBaseName)\(suffix)"
    }

    private func persistFunctionRegistry(rootURL: URL, mentions: [MentionItem]) {
        let payload = mentions.map { item in
            [
                "id": item.id,
                "label": item.label,
                "kind": item.kind,
                "path": item.path,
                "detail": item.detail
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: rootURL.appendingPathComponent(".troner-functions.json"))
    }

    private static func functionMentions(in path: String, cells: [TronCell], rootURL: URL) -> [MentionItem] {
        let relativePath = URL(fileURLWithPath: path).path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return cells.enumerated().compactMap { index, cell in
            guard cell.run, !cell.content.hasPrefix(genCellPrefix) else { return nil }
            let parsed = parseRunCellContent(cell.content)
            let name = parsed.name.isEmpty ? fallbackFunctionName(from: parsed.body, index: index) : parsed.name
            return MentionItem(
                id: "function:\(path)#\(name)",
                label: name,
                kind: "function",
                path: path,
                detail: "\(relativePath) · run cell",
                installed: true,
                modules: [
                    MentionModule(name: name, kind: "executable", injection: "function_call")
                ]
            )
        }
    }

    private static func fallbackFunctionName(from content: String, index: Int) -> String {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(40)) } ?? "run_\(index + 1)"
    }

    private static func parseTronCellsForRegistry(_ source: String) -> [TronCell] {
        let lines = source.components(separatedBy: .newlines)
        var cells: [TronCell] = []
        var index = 0
        while index < lines.count {
            let header = lines[index].trimmingCharacters(in: .whitespaces)
            guard header.hasPrefix("---run:") else {
                index += 1
                continue
            }
            let run = header.contains("true")
            index += 1
            var body: [String] = []
            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "---" {
                body.append(lines[index])
                index += 1
            }
            cells.append(TronCell(run: run, content: body.joined(separator: "\n").trimmingCharacters(in: .newlines)))
            index += 1
        }
        return cells
    }

    private static func extractFunctionReferences(from content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"@([\p{L}\p{N}_ .-]+)"#) else { return [] }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.matches(in: content, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            let raw = String(content[range])
            let cleaned = raw
                .components(separatedBy: "#").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned?.isEmpty == false ? cleaned : nil
        }
    }

    private func sanitizedPathComponent(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private func encodeJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func copyDroppedFile(from sourceURL: URL, to targetDirectoryPath: String? = nil) {
        let targetDirectory = URL(fileURLWithPath: targetDirectoryPath ?? projectRootPath, isDirectory: true)

        do {
            let copied: FileEntry = try bridge.call(
                "copy_entry",
                params: [
                    "path": sourceURL.path,
                    "target_directory_path": targetDirectory.path
                ],
                as: FileEntry.self
            )
            refreshFiles()
            status = "Copied \(copied.name)"
            endDraggingFile()
        } catch {
            errorMessage = error.localizedDescription
            status = "Copy failed"
            endDraggingFile()
        }
    }

    private func moveDroppedFile(from sourceURL: URL, to targetDirectoryPath: String? = nil) {
        let targetDirectory = URL(fileURLWithPath: targetDirectoryPath ?? projectRootPath, isDirectory: true)
        let source = sourceURL.standardizedFileURL
        let target = targetDirectory.standardizedFileURL
        let sourceParent = source.deletingLastPathComponent()

        guard sourceParent.path != target.path else {
            status = "Already in \(target.lastPathComponent)"
            endDraggingFile()
            return
        }

        if isDirectory(source), target.path.hasPrefix(source.path + "/") {
            errorMessage = "A folder cannot be moved into itself."
            status = "Move failed"
            endDraggingFile()
            return
        }

        do {
            let moved: FileEntry = try bridge.call(
                "move_entry",
                params: [
                    "path": sourceURL.path,
                    "target_directory_path": targetDirectory.path
                ],
                as: FileEntry.self
            )
            if selectedFile?.path == sourceURL.path || openedFile?.path == sourceURL.path {
            selectedFile = nil
            openedFile = nil
            activeTabPath = nil
            draftCells = []
                documentBlocks = []
                isDirty = false
            }
            refreshFiles()
            status = "Moved \(moved.name)"
            endDraggingFile()
        } catch {
            errorMessage = error.localizedDescription
            status = "Move failed"
            endDraggingFile()
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    nonisolated private static func string(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let url = item as? URL {
            return url.path
        }
        return nil
    }
}
