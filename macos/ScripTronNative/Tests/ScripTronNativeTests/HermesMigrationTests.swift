import XCTest
@testable import ScripTronNative

final class HermesMigrationTests: XCTestCase {
    func testRunCellConfigDefaultsToPromptSubmitWithInteractiveApprovals() throws {
        let config = HermesRunCellConfig.default

        XCTAssertEqual(config.command, .promptSubmit)
        XCTAssertEqual(config.approvalMode, .interactive)
        XCTAssertEqual(config.clarifyMode, .modal)
        XCTAssertFalse(config.background)
        XCTAssertNil(config.sessionID)
    }

    func testRunCellConfigSerializesIntoTronMetadataPrefix() throws {
        let config = HermesRunCellConfig(
            command: .promptBackground,
            approvalMode: .allowOnce,
            clarifyMode: .modal,
            background: true,
            sessionID: "session-123"
        )
        let encoded = try TronRunCellMetadata.encode(config)

        XCTAssertTrue(encoded.hasPrefix("[[scriptron:hermes]] "))
        XCTAssertTrue(encoded.contains("\"command\":\"prompt.background\""))
        XCTAssertTrue(encoded.contains("\"approval_mode\":\"allow_once\""))
        XCTAssertTrue(encoded.contains("\"session_id\":\"session-123\""))
    }

    func testDocumentCodecRoundTripsRunCellNameHermesMetadataAndBody() throws {
        let cells = [
            TronCell(
                run: false,
                content: "# Quarterly Report\nUse local files only."
            ),
            TronCell(
                run: true,
                content: """
                [[scriptron:run-name]] build_deck
                [[scriptron:hermes]] {"command":"prompt.submit","approval_mode":"interactive","clarify_mode":"modal","background":false}
                Create a PowerPoint summary from the CSV files.
                """
            )
        ]

        let blocks = TronDocumentCodec.documentBlocks(from: cells)
        let runBlock = try XCTUnwrap(blocks.first { $0.kind == .run })

        XCTAssertEqual(runBlock.name, "build_deck")
        XCTAssertEqual(runBlock.hermesConfig.command, .promptSubmit)
        XCTAssertEqual(runBlock.hermesConfig.approvalMode, .interactive)
        XCTAssertEqual(runBlock.content, "Create a PowerPoint summary from the CSV files.")

        let roundTripped = TronDocumentCodec.cells(from: blocks)
        XCTAssertEqual(roundTripped.first?.run, false)
        XCTAssertEqual(roundTripped.last?.run, true)
        XCTAssertTrue(roundTripped.last?.content.contains("[[scriptron:run-name]] build_deck") == true)
        XCTAssertTrue(roundTripped.last?.content.contains("[[scriptron:hermes]]") == true)
        XCTAssertTrue(roundTripped.last?.content.contains("Create a PowerPoint summary") == true)
    }

    func testHermesEventMapperMapsStreamingToolApprovalAndClarifyEvents() throws {
        let delta = try HermesEventMapper.map(raw: [
            "type": "message.delta",
            "session_id": "s1",
            "run_id": "r1",
            "delta": "Hello"
        ])
        XCTAssertEqual(delta.type, "message_delta")
        XCTAssertEqual(delta.content?.value as? String, "Hello")
        XCTAssertEqual(delta.sessionID, "s1")
        XCTAssertEqual(delta.runID, "r1")

        let toolStart = try HermesEventMapper.map(raw: [
            "type": "tool.start",
            "name": "write_file",
            "args": ["path": "deck.md"]
        ])
        XCTAssertEqual(toolStart.type, "tool_start")
        XCTAssertEqual(toolStart.tool, "write_file")

        let approval = try HermesEventMapper.map(raw: [
            "type": "approval.request",
            "approval_id": "approval-1",
            "title": "Write file?",
            "message": "Hermes wants to create deck.md."
        ])
        XCTAssertEqual(approval.type, "approval_request")
        XCTAssertEqual(approval.approvalID, "approval-1")
        XCTAssertEqual(approval.content?.value as? String, "Hermes wants to create deck.md.")

        let clarify = try HermesEventMapper.map(raw: [
            "type": "clarify.request",
            "clarify_id": "clarify-1",
            "question": "Which audience is this deck for?"
        ])
        XCTAssertEqual(clarify.type, "clarify_request")
        XCTAssertEqual(clarify.clarifyID, "clarify-1")
        XCTAssertEqual(clarify.content?.value as? String, "Which audience is this deck for?")
    }

    func testRunCellCommandCatalogExposesCommonHermesActionsInsteadOfSlashCommands() throws {
        let commands = HermesRunCommandCatalog.default.commands

        XCTAssertEqual(commands.map(\.method), [
            "prompt.submit",
            "prompt.background",
            "session.steer",
            "session.interrupt",
            "session.compress",
            "session.branch",
            "session.status",
            "session.usage"
        ])
        XCTAssertEqual(commands.first?.title, "Run prompt")
        XCTAssertTrue(commands.allSatisfy { !$0.title.contains("/") })
        XCTAssertTrue(commands.contains { $0.icon == "play.fill" && $0.method == "prompt.submit" })
        XCTAssertTrue(commands.contains { $0.icon == "pause.circle" && $0.method == "session.interrupt" })
    }

    func testApprovalRequestBuildsModalViewModelWithExpectedActions() throws {
        let event = try HermesEventMapper.map(raw: [
            "type": "approval.request",
            "approval_id": "approval-42",
            "title": "Allow file write?",
            "message": "Hermes wants to write report.pptx.",
            "details": [
                "tool": "write_file",
                "path": "report.pptx"
            ]
        ])

        let modal = try HermesApprovalModalViewModel(event: event)

        XCTAssertEqual(modal.id, "approval-42")
        XCTAssertEqual(modal.title, "Allow file write?")
        XCTAssertEqual(modal.message, "Hermes wants to write report.pptx.")
        XCTAssertEqual(modal.actions.map(\.response), [.allowOnce, .alwaysAllow, .deny])
        XCTAssertEqual(modal.actions.map(\.title), ["Allow once", "Always allow", "Deny"])
        XCTAssertTrue(modal.details.contains("report.pptx"))
    }

    func testClarifyRequestBuildsModalInputViewModel() throws {
        let event = try HermesEventMapper.map(raw: [
            "type": "clarify.request",
            "clarify_id": "clarify-77",
            "question": "Who is the target audience for the deck?",
            "placeholder": "Executives, sales team, finance team..."
        ])

        let modal = try HermesClarifyModalViewModel(event: event)

        XCTAssertEqual(modal.id, "clarify-77")
        XCTAssertEqual(modal.question, "Who is the target audience for the deck?")
        XCTAssertEqual(modal.placeholder, "Executives, sales team, finance team...")
        XCTAssertTrue(modal.requiresTextResponse)
    }

    func testTronContextBuilderIncludesDocumentCellsBlackboardAndReferencedRunOutputs() throws {
        let cells = [
            TronCell(run: false, content: "# Client Context\nACME prefers concise executive summaries."),
            TronCell(run: true, content: """
            [[scriptron:run-name]] research
            Summarize revenue.csv.
            """),
            TronCell(run: true, content: """
            [[scriptron:run-name]] build_deck
            Use [[scriptron:run-name]] research and create a PPT outline.
            """)
        ]
        let blackboard: [String: Any] = [
            "notes": [
                ["source": "last_run", "summary": "Use internal files only."]
            ]
        ]
        let previousOutputs = [
            "research": "Revenue grew 14% QoQ."
        ]

        let request = try TronContextBuilder.buildHermesPrompt(
            cells: cells,
            selectedRunName: "build_deck",
            projectPath: "/tmp/ScripTron/ACME",
            blackboard: blackboard,
            previousOutputs: previousOutputs
        )

        XCTAssertEqual(request.method, "prompt.submit")
        XCTAssertEqual(request.projectPath, "/tmp/ScripTron/ACME")
        XCTAssertTrue(request.prompt.contains("create a PPT outline"))
        XCTAssertTrue(request.context.contains("ACME prefers concise executive summaries."))
        XCTAssertTrue(request.context.contains("Revenue grew 14% QoQ."))
        XCTAssertTrue(request.context.contains("Use internal files only."))
    }

    func testWorkspaceNavigationKeepsDashboardAndProjectStudioAsPrimaryLayers() {
        let navigation = ScripTronNavigationModel.default

        XCTAssertEqual(navigation.primaryLayers.map(\.id), ["workspace", "project_studio"])
        XCTAssertEqual(navigation.workspacePanels.map(\.id), [
            "all_projects",
            "archived",
            "model_management",
            "settings"
        ])
        XCTAssertEqual(navigation.projectPanels.map(\.id), [
            "explorer",
            "history",
            "settings"
        ])
        XCTAssertTrue(navigation.primaryActionIDs.contains("new_project"))
        XCTAssertTrue(navigation.projectActionIDs.contains("new_script"))
        XCTAssertTrue(navigation.projectActionIDs.contains("run"))
    }

    func testRunEventSectionsPreserveResponseLogAndAgentDelegations() throws {
        let events = [
            try HermesEventMapper.map(raw: ["type": "message.delta", "delta": "Drafting outline"]),
            try HermesEventMapper.map(raw: ["type": "tool.start", "name": "write_file"]),
            try HermesEventMapper.map(raw: [
                "type": "delegation.status",
                "agent_id": "agent-1",
                "label": "Slides researcher",
                "status": "running"
            ]),
            try HermesEventMapper.map(raw: [
                "type": "approval.request",
                "approval_id": "approval-1",
                "message": "Write report.pptx?"
            ])
        ]

        let sections = HermesRunEventSections(events: events)

        XCTAssertEqual(sections.response.map(\.type), ["message_delta"])
        XCTAssertEqual(sections.log.map(\.type), ["tool_start"])
        XCTAssertEqual(sections.delegations.map(\.type), ["delegation_status"])
        XCTAssertEqual(sections.pendingApprovals.map(\.approvalID), ["approval-1"])
    }

    func testHermesModelManagementStateReplacesProviderCardsWithGatewayStatus() {
        let state = HermesModelManagementState(
            installStatus: .installed(version: "0.4.0"),
            gatewayStatus: .running(portDescription: "stdio json-rpc"),
            activeProvider: "nous",
            activeModel: "Hermes 4",
            availableActions: [.checkInstall, .login, .selectModel, .showGatewayStatus, .openDoctor]
        )

        XCTAssertEqual(state.summaryPills.map(\.label), [
            "Hermes",
            "Gateway",
            "Provider",
            "Model"
        ])
        XCTAssertEqual(state.summaryPills.map(\.value), [
            "0.4.0",
            "stdio json-rpc",
            "nous",
            "Hermes 4"
        ])
        XCTAssertFalse(state.shouldShowLegacyProviderCards)
        XCTAssertEqual(state.availableActions, [.checkInstall, .login, .selectModel, .showGatewayStatus, .openDoctor])
    }

    func testRustBridgeHermesMethodCatalogMatchesPhaseTwoPlan() {
        let methods = HermesBridgeMethodCatalog.default.methodNames

        XCTAssertEqual(methods, [
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
            "hermes_command_dispatch"
        ])
    }
}
