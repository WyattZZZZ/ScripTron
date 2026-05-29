import Foundation

enum HermesRunCommand: String, Codable, Equatable {
    case promptSubmit = "prompt.submit"
    case promptBackground = "prompt.background"
    case sessionSteer = "session.steer"
    case sessionInterrupt = "session.interrupt"
    case sessionCompress = "session.compress"
    case sessionBranch = "session.branch"
    case sessionStatus = "session.status"
    case sessionUsage = "session.usage"
}

enum HermesApprovalMode: String, Codable, Equatable {
    case interactive
    case allowOnce = "allow_once"
    case alwaysAllow = "always_allow"
    case deny
}

enum HermesClarifyMode: String, Codable, Equatable {
    case modal
}

struct HermesRunCellConfig: Codable, Equatable {
    let command: HermesRunCommand
    let approvalMode: HermesApprovalMode
    let clarifyMode: HermesClarifyMode
    let background: Bool
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case command
        case approvalMode = "approval_mode"
        case clarifyMode = "clarify_mode"
        case background
        case sessionID = "session_id"
    }

    static let `default` = HermesRunCellConfig(
        command: .promptSubmit,
        approvalMode: .interactive,
        clarifyMode: .modal,
        background: false,
        sessionID: nil
    )
}

enum TronRunCellMetadata {
    static let prefix = "[[scriptron:hermes]] "

    static func encode(_ config: HermesRunCellConfig) throws -> String {
        let data = try JSONEncoder().encode(config)
        return prefix + String(decoding: data, as: UTF8.self)
    }

    static func decode(_ line: String) -> HermesRunCellConfig? {
        guard line.hasPrefix(prefix) else { return nil }
        let json = String(line.dropFirst(prefix.count))
        return try? JSONDecoder().decode(HermesRunCellConfig.self, from: Data(json.utf8))
    }
}

enum TronDocumentBlockKind: Equatable {
    case text
    case run
}

struct TronDocumentBlock: Equatable {
    var kind: TronDocumentBlockKind
    var name: String
    var hermesConfig: HermesRunCellConfig
    var content: String
}

enum TronDocumentCodec {
    static func documentBlocks(from cells: [TronCell]) -> [TronDocumentBlock] {
        cells.map { cell in
            guard cell.run else {
                return TronDocumentBlock(kind: .text, name: "", hermesConfig: .default, content: cell.content)
            }

            var name = ""
            var config = HermesRunCellConfig.default
            var bodyLines: [String] = []

            for rawLine in cell.content.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[[scriptron:run-name]] ") {
                    name = String(line.dropFirst("[[scriptron:run-name]] ".count))
                } else if let decoded = TronRunCellMetadata.decode(line) {
                    config = decoded
                } else {
                    bodyLines.append(String(rawLine))
                }
            }

            return TronDocumentBlock(
                kind: .run,
                name: name,
                hermesConfig: config,
                content: bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func cells(from blocks: [TronDocumentBlock]) -> [TronCell] {
        blocks.map { block in
            guard block.kind == .run else {
                return TronCell(run: false, content: block.content)
            }

            var lines: [String] = []
            if !block.name.isEmpty {
                lines.append("[[scriptron:run-name]] \(block.name)")
            }
            if let metadata = try? TronRunCellMetadata.encode(block.hermesConfig) {
                lines.append(metadata)
            }
            lines.append(block.content)
            return TronCell(run: true, content: lines.joined(separator: "\n"))
        }
    }
}

struct HermesEvent {
    let type: String
    let content: AnyCodable?
    let sessionID: String?
    let runID: String?
    let tool: String?
    let args: AnyCodable?
    let approvalID: String?
    let clarifyID: String?
    let title: String?
    let details: AnyCodable?
    let placeholder: String?
}

enum HermesEventMapper {
    static func map(raw: [String: Any]) throws -> HermesEvent {
        let rawType = raw["type"] as? String ?? "unknown"
        let type = rawType.replacingOccurrences(of: ".", with: "_")
        let content = raw["delta"] ?? raw["message"] ?? raw["question"]
        return HermesEvent(
            type: type,
            content: content.map(AnyCodable.init),
            sessionID: raw["session_id"] as? String,
            runID: raw["run_id"] as? String,
            tool: raw["name"] as? String,
            args: (raw["args"]).map(AnyCodable.init),
            approvalID: raw["approval_id"] as? String,
            clarifyID: raw["clarify_id"] as? String,
            title: raw["title"] as? String,
            details: raw["details"].map(AnyCodable.init),
            placeholder: raw["placeholder"] as? String
        )
    }
}

struct HermesRunCommandItem: Equatable {
    let method: String
    let title: String
    let icon: String
}

struct HermesRunCommandCatalog {
    let commands: [HermesRunCommandItem]

    static let `default` = HermesRunCommandCatalog(commands: [
        HermesRunCommandItem(method: "prompt.submit", title: "Run prompt", icon: "play.fill"),
        HermesRunCommandItem(method: "prompt.background", title: "Background task", icon: "clock"),
        HermesRunCommandItem(method: "session.steer", title: "Steer session", icon: "arrow.triangle.turn.up.right.diamond"),
        HermesRunCommandItem(method: "session.interrupt", title: "Interrupt session", icon: "pause.circle"),
        HermesRunCommandItem(method: "session.compress", title: "Compress session", icon: "archivebox"),
        HermesRunCommandItem(method: "session.branch", title: "Branch session", icon: "arrow.branch"),
        HermesRunCommandItem(method: "session.status", title: "Show status", icon: "waveform.path.ecg"),
        HermesRunCommandItem(method: "session.usage", title: "Show usage", icon: "chart.bar")
    ])
}

struct RunCellActionMenuModel {
    let items: [HermesRunCommandItem]

    var primary: HermesRunCommandItem {
        items.first { $0.method == "prompt.submit" } ?? items[0]
    }

    static let `default` = RunCellActionMenuModel(items: HermesRunCommandCatalog.default.commands)
}

enum ExtensionCatalogSource: String, CaseIterable, Equatable, Identifiable {
    case hermesHub = "Hermes Official / Hub"
    case tronHub = "TronHub"

    var id: String { rawValue }
}

enum ExtensionCatalogKind: String, Equatable {
    case cli
    case skill
}

enum ExtensionCatalogAction: Equatable {
    case installIntoHermes
    case installIntoScripTron
    case remove
    case update
}

struct ExtensionCatalogItem: Identifiable, Equatable {
    var id: String { "\(source.rawValue):\(kind.rawValue):\(name)" }
    let name: String
    let kind: ExtensionCatalogKind
    let source: ExtensionCatalogSource
    let category: String
    let trustLevel: String
    let description: String
    let installed: Bool
    let wrapsExternalCLI: Bool
    let hermesCompatible: Bool
    let installRef: String?
    let tags: [String]
    let icon: String

    init(
        name: String,
        kind: ExtensionCatalogKind,
        source: ExtensionCatalogSource,
        category: String,
        trustLevel: String,
        description: String,
        installed: Bool,
        wrapsExternalCLI: Bool,
        hermesCompatible: Bool,
        installRef: String? = nil,
        tags: [String] = [],
        icon: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.source = source
        self.category = category
        self.trustLevel = trustLevel
        self.description = description
        self.installed = installed
        self.wrapsExternalCLI = wrapsExternalCLI
        self.hermesCompatible = hermesCompatible
        self.installRef = installRef
        self.tags = tags
        self.icon = icon ?? Self.defaultIcon(kind: kind, wrapsExternalCLI: wrapsExternalCLI)
    }

    var primaryAction: ExtensionCatalogAction {
        if installed { return .remove }
        if hermesCompatible { return .installIntoHermes }
        return .installIntoScripTron
    }

    var displayBadges: [String] {
        var badges: [String] = []
        appendBadge(source.rawValue, to: &badges)
        appendBadge(category, to: &badges)
        appendBadge(trustLevel, to: &badges)
        tags.forEach { appendBadge($0, to: &badges) }
        if wrapsExternalCLI {
            appendBadge("cli", to: &badges)
        }
        return badges
    }

    private static func defaultIcon(kind: ExtensionCatalogKind, wrapsExternalCLI: Bool) -> String {
        if wrapsExternalCLI { return "terminal" }
        switch kind {
        case .cli: return "terminal"
        case .skill: return "sparkles"
        }
    }

    private func appendBadge(_ badge: String, to badges: inout [String]) {
        let trimmed = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !badges.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        badges.append(trimmed)
    }
}

struct ExtensionCatalogState {
    let items: [ExtensionCatalogItem]
    let pageSize: Int

    init(items: [ExtensionCatalogItem], pageSize: Int = 24) {
        self.items = items
        self.pageSize = max(1, pageSize)
    }

    var sources: [ExtensionCatalogSource] {
        ExtensionCatalogSource.allCases.filter { source in
            items.contains { $0.source == source }
        }
    }

    var categories: [String] {
        Array(Set(items.map(\.category))).sorted()
    }

    func filtered(source: ExtensionCatalogSource, category: String, query: String) -> [ExtensionCatalogItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items
            .filter { $0.source == source }
            .filter { category == "All" || $0.category == category }
            .filter { item in
                normalizedQuery.isEmpty
                    || item.name.lowercased().contains(normalizedQuery)
                    || item.description.lowercased().contains(normalizedQuery)
                    || item.category.lowercased().contains(normalizedQuery)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func pageCount(source: ExtensionCatalogSource, category: String, query: String) -> Int {
        let count = filtered(source: source, category: category, query: query).count
        return max(1, Int(ceil(Double(count) / Double(pageSize))))
    }

    func page(source: ExtensionCatalogSource, category: String, query: String, page: Int) -> [ExtensionCatalogItem] {
        let filteredItems = filtered(source: source, category: category, query: query)
        let pageIndex = max(1, page) - 1
        let start = pageIndex * pageSize
        guard start < filteredItems.count else { return [] }
        let end = min(start + pageSize, filteredItems.count)
        return Array(filteredItems[start..<end])
    }
}

enum ExtensionCatalogFixtures {
    static let hermesSkillItems = [
        ExtensionCatalogItem(
            name: "github-pr-review",
            kind: .skill,
            source: .hermesHub,
            category: "Software Dev",
            trustLevel: "official",
            description: "Review pull requests and summarize actionable changes.",
            installed: false,
            wrapsExternalCLI: false,
            hermesCompatible: true,
            installRef: "github-pr-review"
        ),
        ExtensionCatalogItem(
            name: "research-brief",
            kind: .skill,
            source: .hermesHub,
            category: "Research",
            trustLevel: "trusted",
            description: "Collect sources and draft concise research briefs.",
            installed: false,
            wrapsExternalCLI: false,
            hermesCompatible: true,
            installRef: "research-brief"
        )
    ]

    static let hermesCLIItems = [
        ExtensionCatalogItem(
            name: "shell-command-runner",
            kind: .cli,
            source: .hermesHub,
            category: "DevOps",
            trustLevel: "official",
            description: "Hermes-managed wrapper for local shell tools and command approval.",
            installed: false,
            wrapsExternalCLI: true,
            hermesCompatible: true,
            installRef: "shell-command-runner"
        ),
        ExtensionCatalogItem(
            name: "code-search",
            kind: .cli,
            source: .hermesHub,
            category: "Software Dev",
            trustLevel: "trusted",
            description: "Hermes skill wrapper for source search workflows.",
            installed: false,
            wrapsExternalCLI: true,
            hermesCompatible: true,
            installRef: "code-search"
        )
    ]

    static func fromTronhub(_ entry: TronhubEntry) -> ExtensionCatalogItem {
        ExtensionCatalogItem(
            name: entry.name,
            kind: entry.kind == "skill" ? .skill : .cli,
            source: .tronHub,
            category: entry.kind == "skill" ? "AI Agents" : "Productivity",
            trustLevel: "workspace",
            description: entry.description,
            installed: entry.installed,
            wrapsExternalCLI: entry.kind != "skill",
            hermesCompatible: entry.kind == "skill",
            installRef: entry.source_path
        )
    }
}

struct RunEventSectionGroups {
    let response: [RunEvent]
    let log: [RunEvent]
    let delegations: [RunEvent]
    let approvals: [RunEvent]
}

enum RunEventPresentation {
    static func sections(for events: [RunEvent]) -> RunEventSectionGroups {
        RunEventSectionGroups(
            response: events.filter { $0.type == "text" || $0.type == "message_delta" || $0.type == "message_complete" },
            log: events.filter { $0.type.hasPrefix("tool_") || legacyLogTypes.contains($0.type) },
            delegations: events.filter { $0.type == "delegation_status" },
            approvals: events.filter { $0.type == "approval_request" || $0.type == "clarify_request" || $0.type == "secret_request" }
        )
    }

    static func displayText(for event: RunEvent) -> String? {
        guard let value = event.content?.value else { return nil }
        if let string = value as? String { return string }
        guard !(value is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func logText(for event: RunEvent) -> String {
        switch event.type {
        case "plan":
            return "PLAN\n\(displayText(for: event) ?? "")"
        case "skill_selected":
            return "SKILLS \(event.skills?.joined(separator: ", ") ?? "")"
        case "tool_call":
            return "TOOL \(event.tool ?? "")\nARGS \(jsonText(event.args?.value))"
        case "tool_result":
            return "\(event.success == false ? "FAILED" : "RESULT") \(event.tool ?? "")\n\(event.output ?? displayText(for: event) ?? "")"
        case "step_started":
            return "STEP START \(event.step_id ?? "") \(event.tool ?? "")\nARGS \(jsonText(event.args?.value))"
        case "step_retried":
            return "STEP RETRY \(event.step_id ?? "") attempt \(event.attempt ?? 0)\n\(event.decision ?? ""): \(event.reason ?? "")"
        case "step_completed":
            return "STEP DONE \(event.step_id ?? "") \(event.tool ?? "")\n\(event.output ?? "")"
        case "step_failed":
            return "STEP FAILED \(event.step_id ?? "") \(event.tool ?? "")\n\(event.error ?? "")"
        case "thinking":
            return "THINKING\n\(displayText(for: event) ?? "")"
        case "error":
            return "ERROR\n\(event.error ?? displayText(for: event) ?? "")"
        default:
            return "\(event.type)\n\(displayText(for: event) ?? "")"
        }
    }

    private static let legacyLogTypes: Set<String> = [
        "warning",
        "plan",
        "skill_selected",
        "tool_call",
        "tool_result",
        "step_started",
        "step_retried",
        "step_completed",
        "step_failed",
        "thinking",
        "error"
    ]

    private static func jsonText(_ value: Any?) -> String {
        guard let value, !(value is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

struct HermesApprovalAction: Equatable {
    let response: HermesApprovalMode
    let title: String
}

struct HermesApprovalModalViewModel {
    let id: String
    let title: String
    let message: String
    let details: String
    let actions: [HermesApprovalAction]

    init(event: HermesEvent) throws {
        id = event.approvalID ?? ""
        title = event.title ?? "Approval required"
        message = event.content?.value as? String ?? ""
        details = String(describing: event.details?.value ?? "")
        actions = [
            HermesApprovalAction(response: .allowOnce, title: "Allow once"),
            HermesApprovalAction(response: .alwaysAllow, title: "Always allow"),
            HermesApprovalAction(response: .deny, title: "Deny")
        ]
    }
}

struct HermesClarifyModalViewModel {
    let id: String
    let question: String
    let placeholder: String
    let requiresTextResponse: Bool

    init(event: HermesEvent) throws {
        id = event.clarifyID ?? ""
        question = event.content?.value as? String ?? ""
        placeholder = event.placeholder ?? ""
        requiresTextResponse = true
    }
}

struct HermesPromptRequest {
    let method: String
    let projectPath: String
    let prompt: String
    let context: String
}

enum TronContextBuilder {
    static func buildHermesPrompt(
        cells: [TronCell],
        selectedRunName: String,
        projectPath: String,
        blackboard: [String: Any],
        previousOutputs: [String: String]
    ) throws -> HermesPromptRequest {
        let blocks = TronDocumentCodec.documentBlocks(from: cells)
        let prompt = blocks.first { $0.kind == .run && $0.name == selectedRunName }?.content ?? ""
        let documentContext = blocks.filter { $0.kind != .run }.map(\.content)
        let outputContext = previousOutputs.map { "\($0.key): \($0.value)" }
        let blackboardContext = String(describing: blackboard)
        return HermesPromptRequest(
            method: "prompt.submit",
            projectPath: projectPath,
            prompt: prompt,
            context: (documentContext + outputContext + [blackboardContext]).joined(separator: "\n\n")
        )
    }
}

struct NavigationItem {
    let id: String
}

struct ScripTronNavigationModel {
    let primaryLayers: [NavigationItem]
    let workspacePanels: [NavigationItem]
    let projectPanels: [NavigationItem]
    let primaryActionIDs: [String]
    let projectActionIDs: [String]

    static let `default` = ScripTronNavigationModel(
        primaryLayers: [NavigationItem(id: "workspace"), NavigationItem(id: "project_studio")],
        workspacePanels: [
            NavigationItem(id: "all_projects"),
            NavigationItem(id: "archived"),
            NavigationItem(id: "model_management"),
            NavigationItem(id: "settings")
        ],
        projectPanels: [
            NavigationItem(id: "explorer"),
            NavigationItem(id: "history"),
            NavigationItem(id: "settings")
        ],
        primaryActionIDs: ["new_project"],
        projectActionIDs: ["new_script", "run"]
    )
}

struct HermesRunEventSections {
    let response: [HermesEvent]
    let log: [HermesEvent]
    let delegations: [HermesEvent]
    let pendingApprovals: [HermesEvent]

    init(events: [HermesEvent]) {
        response = events.filter { $0.type == "message_delta" || $0.type == "message_complete" }
        log = events.filter { $0.type.hasPrefix("tool_") }
        delegations = events.filter { $0.type == "delegation_status" }
        pendingApprovals = events.filter { $0.type == "approval_request" }
    }
}

enum HermesInstallStatus {
    case installed(version: String)
}

enum HermesGatewayStatus {
    case running(portDescription: String)
}

enum HermesModelAction: Equatable {
    case checkInstall
    case login
    case selectModel
    case showGatewayStatus
    case openDoctor
}

struct SummaryPill {
    let label: String
    let value: String
}

struct HermesModelManagementState {
    let installStatus: HermesInstallStatus
    let gatewayStatus: HermesGatewayStatus
    let activeProvider: String
    let activeModel: String
    let availableActions: [HermesModelAction]
    let shouldShowLegacyProviderCards = false

    var summaryPills: [SummaryPill] {
        let version: String
        switch installStatus {
        case .installed(let installedVersion): version = installedVersion
        }
        let gateway: String
        switch gatewayStatus {
        case .running(let portDescription): gateway = portDescription
        }
        return [
            SummaryPill(label: "Hermes", value: version),
            SummaryPill(label: "Gateway", value: gateway),
            SummaryPill(label: "Provider", value: activeProvider),
            SummaryPill(label: "Model", value: activeModel)
        ]
    }
}

struct HermesBridgeMethodCatalog {
    let methodNames: [String]

    static let `default` = HermesBridgeMethodCatalog(methodNames: [
        "hermes_status",
        "hermes_install_check",
        "hermes_start_gateway",
        "hermes_stop_gateway",
        "hermes_session_create",
        "hermes_session_list",
        "hermes_session_resume",
        "hermes_session_interrupt",
        "hermes_session_compress",
        "hermes_session_branch",
        "hermes_prompt_submit",
        "hermes_prompt_background",
        "hermes_session_steer",
        "hermes_poll_events",
        "hermes_approval_respond",
        "hermes_clarify_respond",
        "hermes_secret_respond",
        "hermes_command_catalog",
        "hermes_command_dispatch",
        "sync_hermes_workspace_bridge",
        "hermes_skills_browse",
        "hermes_skills_search",
        "hermes_skills_install",
        "hermes_skills_remove",
        "hermes_skills_update",
        "hermes_skill_sources"
    ])
}
