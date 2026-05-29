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

    func testExtensionCatalogPaginatesAndCarriesOfficialTagsAndIcons() throws {
        let items = (1...15).map { index in
            ExtensionCatalogItem(
                name: "official-skill-\(index)",
                kind: .skill,
                source: .hermesHub,
                category: index.isMultiple(of: 2) ? "Research" : "Software Dev",
                trustLevel: "official",
                description: "Official Hermes skill \(index)",
                installed: false,
                wrapsExternalCLI: index.isMultiple(of: 3),
                hermesCompatible: true,
                installRef: "official-skill-\(index)",
                tags: ["official", "hermes", index.isMultiple(of: 3) ? "cli" : "skill"],
                icon: index.isMultiple(of: 3) ? "terminal" : "sparkles"
            )
        }
        let catalog = ExtensionCatalogState(items: items, pageSize: 6)

        XCTAssertEqual(catalog.pageCount(source: .hermesHub, category: "All", query: ""), 3)
        XCTAssertEqual(
            catalog.page(source: .hermesHub, category: "All", query: "", page: 2).map(\.name),
            ["official-skill-15", "official-skill-2", "official-skill-3", "official-skill-4", "official-skill-5", "official-skill-6"]
        )
        XCTAssertEqual(items[2].tags, ["official", "hermes", "cli"])
        XCTAssertEqual(items[2].icon, "terminal")
        XCTAssertEqual(items[2].displayBadges, ["Hermes Official / Hub", "Software Dev", "official", "hermes", "cli"])
    }

    func testWorkspaceAndProjectPresentationModelsCoverViewStateFormatting() throws {
        let projects = [
            AppModel.ProjectItem(name: "active", path: "/tmp/active", status: "Ready", archived: false, packaged: false),
            AppModel.ProjectItem(name: "archived", path: "/tmp/archived", status: "Archived", archived: true, packaged: false)
        ]

        let activeList = WorkspaceProjectListPresentation(
            archived: false,
            projects: projects,
            language: "en"
        )
        XCTAssertEqual(activeList.title, "Projects")
        XCTAssertEqual(activeList.visibleProjects.map(\.name), ["active"])
        XCTAssertEqual(activeList.emptyTitle, "No projects")
        XCTAssertTrue(activeList.allowsZipDrop)

        let archivedList = WorkspaceProjectListPresentation(
            archived: true,
            projects: projects,
            language: "zh"
        )
        XCTAssertEqual(archivedList.title, "归档项目")
        XCTAssertEqual(archivedList.visibleProjects.map(\.name), ["archived"])
        XCTAssertEqual(archivedList.emptyTitle, "暂无归档项目")
        XCTAssertFalse(archivedList.allowsZipDrop)

        XCTAssertEqual(ProjectTabPresentation(tab: FileEntry(name: "main.tron", path: "/tmp/main.tron", is_dir: false, is_tron: true)).iconName, "doc.richtext")
        XCTAssertEqual(ProjectTabPresentation(tab: FileEntry(name: "notes.md", path: "/tmp/notes.md", is_dir: false, is_tron: false)).iconName, "doc.text")
        XCTAssertEqual(ProjectTabPresentation(tab: FileEntry(name: "data.csv", path: "/tmp/data.csv", is_dir: false, is_tron: false)).iconName, "tablecells")

        let status = ProjectStatusBarPresentation(status: "Saved main.tron", openedViewer: .csv)
        XCTAssertEqual(status.statusText, "SAVED MAIN.TRON")
        XCTAssertEqual(status.viewerText, "CSV")

        XCTAssertEqual(CatalogActionPresentation.title(for: .installIntoHermes, language: "en"), "Install into Hermes")
        XCTAssertEqual(CatalogActionPresentation.title(for: .installIntoScripTron, language: "zh"), "安装到 ScripTron")
        XCTAssertEqual(CatalogActionPresentation.title(for: .remove, language: "en"), "Remove")
        XCTAssertEqual(CatalogActionPresentation.title(for: .update, language: "zh"), "更新")

        XCTAssertEqual(FileIconPresentation.iconName(path: "/tmp/src/main.rs"), "shippingbox")
        XCTAssertEqual(FileIconPresentation.iconName(path: "/tmp/app.swift"), "swift")
        XCTAssertEqual(FileIconPresentation.iconName(path: "/tmp/archive.zip"), "archivebox")
        XCTAssertEqual(FileIconPresentation.iconName(path: "/tmp/folder", isDirectory: true), "folder")
        XCTAssertEqual(FileIconPresentation.iconName(path: "/tmp/folder", isDirectory: true, isExpanded: true), "folder.fill")

        XCTAssertEqual(RegistryItemPresentation(kind: "model").iconName, "cpu")
        XCTAssertEqual(RegistryItemPresentation(kind: "software").iconName, "app.connected.to.app.below.fill")
        XCTAssertEqual(RegistryItemPresentation(kind: "tool").iconName, "terminal")
        XCTAssertEqual(TronhubEntryPresentation(kind: "skill").iconName, "sparkles")
        XCTAssertEqual(TronhubEntryPresentation(kind: "model").iconName, "cpu")
        XCTAssertEqual(TronhubEntryPresentation(kind: "cli").iconName, "terminal")

        let file = FileEntry(name: "main.tron", path: "/tmp/main.tron", is_dir: false, is_tron: true)
        let selectedRow = FileTreeRowPresentation(
            file: file,
            depth: 2,
            selectedPath: "/tmp/main.tron",
            openedPath: nil,
            expandedPaths: [],
            childCount: 0,
            dropHoverPath: nil,
            draggedPath: nil
        )
        XCTAssertTrue(selectedRow.selected)
        XCTAssertEqual(selectedRow.iconName, "doc.richtext")
        XCTAssertEqual(selectedRow.leadingPadding, 36)
        XCTAssertEqual(selectedRow.backgroundState, .selected)
        XCTAssertEqual(selectedRow.opacity, 1)

        let folder = FileEntry(name: "Sources", path: "/tmp/Sources", is_dir: true, is_tron: false)
        let dropRow = FileTreeRowPresentation(
            file: folder,
            depth: 0,
            selectedPath: nil,
            openedPath: nil,
            expandedPaths: ["/tmp/Sources"],
            childCount: 3,
            dropHoverPath: "/tmp/Sources",
            draggedPath: "/tmp/Sources"
        )
        XCTAssertTrue(dropRow.expanded)
        XCTAssertTrue(dropRow.showsChildren)
        XCTAssertEqual(dropRow.chevronIcon, "chevron.down")
        XCTAssertEqual(dropRow.iconName, "folder.fill")
        XCTAssertEqual(dropRow.backgroundState, .dropTargeted)
        XCTAssertEqual(dropRow.opacity, 0.72)

        XCTAssertEqual(DocumentBlockRowPresentation(kind: .markdownLine, selected: false, hovering: false).controlTopPadding, 3)
        XCTAssertEqual(DocumentBlockRowPresentation(kind: .heading(2), selected: true, hovering: false).controlTopPadding, 16)
        XCTAssertEqual(DocumentBlockRowPresentation(kind: .run, selected: false, hovering: true).indicatorState, .hovered)
        XCTAssertEqual(DocumentBlockRowPresentation(kind: .quote, selected: true, hovering: true).indicatorState, .selected)

        let packagedProject = AppModel.ProjectItem(name: "deck", path: "/tmp/deck", status: "ready", archived: false, packaged: true)
        let projectRow = ProjectRowPresentation(project: packagedProject, archived: false)
        XCTAssertEqual(projectRow.iconName, "shippingbox.fill")
        XCTAssertEqual(projectRow.statusText, "READY")
        XCTAssertEqual(projectRow.actionsWidth, 342)
        XCTAssertFalse(projectRow.disablesOpenAndPackage)

        let archivedRow = ProjectRowPresentation(project: archivedList.visibleProjects[0], archived: true)
        XCTAssertEqual(archivedRow.iconName, "folder")
        XCTAssertEqual(archivedRow.actionsWidth, 218)
        XCTAssertTrue(archivedRow.disablesOpenAndPackage)

        let catalogItem = ExtensionCatalogItem(
            name: "browser",
            kind: .skill,
            source: .hermesHub,
            category: "Research",
            trustLevel: "official",
            description: "Browser automation",
            installed: false,
            wrapsExternalCLI: true,
            hermesCompatible: true,
            tags: ["official", "browser", "automation", "web", "cli", "extra"],
            icon: "globe"
        )
        let catalogCard = ExtensionCatalogCardPresentation(item: catalogItem, language: "zh")
        XCTAssertEqual(catalogCard.iconName, "globe")
        XCTAssertEqual(catalogCard.visibleBadges, ["Hermes Official / Hub", "Research", "official", "browser", "automation"])
        XCTAssertEqual(catalogCard.actionTitle, "安装到 Hermes")

        let activeTab = EditorTabButtonPresentation(tab: file, active: true, dirty: true, hovering: false)
        XCTAssertEqual(activeTab.iconName, "doc.richtext")
        XCTAssertTrue(activeTab.showsDirtyIndicator)
        XCTAssertEqual(activeTab.textEmphasis, .active)
        XCTAssertEqual(activeTab.backgroundState, .active)
        XCTAssertFalse(activeTab.closeButtonHighlighted)
        XCTAssertEqual(activeTab.underlineHeight, 2)

        let hoveredTab = EditorTabButtonPresentation(tab: FileEntry(name: "notes.md", path: "/tmp/notes.md", is_dir: false, is_tron: false), active: false, dirty: false, hovering: true)
        XCTAssertEqual(hoveredTab.iconName, "doc.text")
        XCTAssertFalse(hoveredTab.showsDirtyIndicator)
        XCTAssertEqual(hoveredTab.textEmphasis, .inactive)
        XCTAssertEqual(hoveredTab.backgroundState, .hovered)
        XCTAssertTrue(hoveredTab.closeButtonHighlighted)
        XCTAssertEqual(hoveredTab.underlineHeight, 0)

        let dirtyToolbar = DocumentToolbarPresentation(isDirty: true, selectedCount: 3, language: "zh")
        XCTAssertEqual(dirtyToolbar.statusText, "未保存")
        XCTAssertEqual(dirtyToolbar.selectedText, "已选择 3 个")
        XCTAssertTrue(dirtyToolbar.showsBulkDelete)
        XCTAssertEqual(dirtyToolbar.statusState, .dirty)

        let cleanToolbar = DocumentToolbarPresentation(isDirty: false, selectedCount: 0, language: "en")
        XCTAssertEqual(cleanToolbar.statusText, "Saved")
        XCTAssertNil(cleanToolbar.selectedText)
        XCTAssertFalse(cleanToolbar.showsBulkDelete)
        XCTAssertEqual(cleanToolbar.statusState, .saved)
    }

    func testDocumentBlockPresentationModelsFormatMarkdownListsAndTables() throws {
        let h1 = MarkdownLinePresentation(text: "# Title")
        XCTAssertEqual(h1.kind, .heading1)
        XCTAssertEqual(h1.fontSize, 30)
        XCTAssertEqual(h1.fontWeight, .bold)
        XCTAssertFalse(h1.hasInlineContainer)
        XCTAssertEqual(h1.verticalPadding, 3)

        let quote = MarkdownLinePresentation(text: "> quoted")
        XCTAssertEqual(quote.kind, .quote)
        XCTAssertEqual(quote.fontSize, 15)
        XCTAssertEqual(quote.fontDesign, .serif)
        XCTAssertEqual(quote.foregroundState, .secondary)
        XCTAssertEqual(quote.backgroundState, .quote)
        XCTAssertEqual(quote.horizontalPadding, 8)

        let code = MarkdownLinePresentation(text: "`code`")
        XCTAssertEqual(code.kind, .code)
        XCTAssertEqual(code.fontSize, 14)
        XCTAssertEqual(code.fontDesign, .monospaced)
        XCTAssertEqual(code.foregroundState, .accent)
        XCTAssertEqual(code.backgroundState, .code)
        XCTAssertEqual(code.horizontalPadding, 8)

        let empty = MarkdownLinePresentation(text: "   ")
        XCTAssertEqual(empty.kind, .plain)
        XCTAssertEqual(empty.verticalPadding, 6)
        XCTAssertTrue(MarkdownLinePresentation(text: "---").isDivider)

        let list = ListBlockPresentation(text: " First item \n\nSecond item", ordered: true)
        XCTAssertEqual(list.items, ["First item", "Second item"])
        XCTAssertEqual(list.marker(at: 0), "1.")
        XCTAssertEqual(list.marker(at: 1), "2.")
        XCTAssertEqual(list.deleteButtonOpacity, 0.75)
        XCTAssertEqual(list.markdown(afterSetting: "Updated", at: 0), "Updated\nSecond item")
        XCTAssertEqual(list.markdown(afterAddingItemAfter: 0), "First item\n\nSecond item")
        XCTAssertEqual(list.markdown(afterDeleting: 1), "First item")

        let singletonList = ListBlockPresentation(text: "", ordered: false)
        XCTAssertEqual(singletonList.items, [""])
        XCTAssertEqual(singletonList.marker(at: 0), "•")
        XCTAssertEqual(singletonList.deleteButtonOpacity, 0)
        XCTAssertEqual(singletonList.markdown(afterDeleting: 0), "")

        let table = MarkdownTablePresentation(markdown: """
        | Name | Score |
        | --- | --- |
        | Ada | 10 |
        """)
        XCTAssertEqual(table.headers, ["Name", "Score"])
        XCTAssertEqual(table.rows, [["Ada", "10"]])
        XCTAssertEqual(table.markdown, """
        | Name | Score |
        | --- | --- |
        | Ada | 10 |
        """)
        XCTAssertEqual(table.addedRow().rows, [["Ada", "10"], ["", ""]])
        XCTAssertEqual(table.addedColumn().headers, ["Name", "Score", "Column 3"])
        XCTAssertEqual(table.deletedColumn(0).headers, ["Score"])
        XCTAssertEqual(table.deletedRow(0).rows, [["", ""]])

        let checklist = ChecklistBlockPresentation(text: """
        [x] Draft outline
        [ ] Build deck
        Plain task
        """)
        XCTAssertEqual(checklist.items, [
            ChecklistItemPresentation(checked: true, text: "Draft outline"),
            ChecklistItemPresentation(checked: false, text: "Build deck"),
            ChecklistItemPresentation(checked: false, text: "Plain task")
        ])
        XCTAssertEqual(checklist.markdown, """
        [x] Draft outline
        [ ] Build deck
        [ ] Plain task
        """)
        XCTAssertEqual(checklist.deleteButtonOpacity, 0.75)
        XCTAssertEqual(checklist.markdown(afterSettingText: "Ship deck", at: 1), """
        [x] Draft outline
        [ ] Ship deck
        [ ] Plain task
        """)
        XCTAssertEqual(checklist.markdown(afterSettingChecked: true, at: 1), """
        [x] Draft outline
        [x] Build deck
        [ ] Plain task
        """)
        XCTAssertEqual(checklist.markdown(afterAddingItemAfter: 0), """
        [x] Draft outline
        [ ] 
        [ ] Build deck
        [ ] Plain task
        """)
        XCTAssertEqual(checklist.markdown(afterDeleting: 2), """
        [x] Draft outline
        [ ] Build deck
        """)

        let emptyChecklist = ChecklistBlockPresentation(text: "")
        XCTAssertEqual(emptyChecklist.items, [ChecklistItemPresentation(checked: false, text: "")])
        XCTAssertEqual(emptyChecklist.deleteButtonOpacity, 0)

        XCTAssertEqual(RunInlineMentionPresentation(text: "Use @browser").query, "browser")
        XCTAssertNil(RunInlineMentionPresentation(text: "Use @browser now").query)
        XCTAssertEqual(
            RunInlineMentionPresentation(text: "Use @browser").textAfterInserting(label: "browser", moduleName: "search"),
            "Use @browser#search "
        )
        XCTAssertEqual(
            RunInlineMentionPresentation(text: "Use ").textAfterInserting(label: "deck", moduleName: nil),
            "Use @deck "
        )

        let skill = MentionItem(id: "skill:browser", label: "browser", kind: "skill", path: "", detail: "Web agent", installed: true, modules: [])
        let cloud = MentionItem(id: "cloud:slides", label: "slides", kind: "cloud", path: "", detail: "Cloud skill", installed: false, modules: [])
        let fileMention = MentionItem(id: "file:brief", label: "brief.tron", kind: "tron", path: "/tmp/brief.tron", detail: "Brief", installed: true, modules: [])
        let function = MentionItem(
            id: "function:build_deck",
            label: "build_deck",
            kind: "function",
            path: "/tmp/brief.tron",
            detail: "Run block",
            installed: true,
            modules: [MentionModule(name: "build_deck", kind: "executable", injection: "function_call")]
        )
        let search = MentionSearchResult(tools: [skill], files: [fileMention], cloud_suggestions: [cloud])

        let projectSkills = MentionPickerPresentation(tab: "Skills", search: search, functionMentions: [function])
        XCTAssertEqual(projectSkills.items.map(\.label), ["browser", "slides"])
        XCTAssertEqual(projectSkills.iconName(for: skill), "sparkles")
        XCTAssertEqual(projectSkills.iconName(for: cloud), "icloud")
        XCTAssertNil(projectSkills.moduleForSelection(skill))

        let projectFunctions = MentionPickerPresentation(tab: "Functions", search: search, functionMentions: [function])
        XCTAssertEqual(projectFunctions.items.map(\.label), ["build_deck"])
        XCTAssertEqual(projectFunctions.iconName(for: function), "function")
        XCTAssertEqual(projectFunctions.moduleForSelection(function)?.name, "build_deck")

        let workspaceTools = MentionPickerPresentation(tab: "Tools", search: search, functionMentions: [])
        XCTAssertEqual(workspaceTools.items.map(\.label), ["browser", "slides"])
        XCTAssertTrue(workspaceTools.showsCloudBadge(for: cloud))
        XCTAssertFalse(workspaceTools.showsCloudBadge(for: skill))
        XCTAssertEqual(MentionPickerPresentation(tab: "Files", search: search, functionMentions: []).items.map(\.label), ["brief.tron"])
        XCTAssertEqual(MentionPickerPresentation(tab: "Files", search: search, functionMentions: []).iconName(for: fileMention), "doc.richtext")

        XCTAssertEqual(NewFileKindPresentation(kind: .tron).fileExtension(customExtension: ""), "tron")
        XCTAssertEqual(NewFileKindPresentation(kind: .word).fileExtension(customExtension: ""), "docx")
        XCTAssertEqual(NewFileKindPresentation(kind: .excel).placeholder, "metrics_table")
        XCTAssertEqual(NewFileKindPresentation(kind: .other).fileExtension(customExtension: " json "), "json")
        XCTAssertTrue(NewFileKindPresentation(kind: .other).requiresCustomExtension)
        XCTAssertFalse(NewFileKindPresentation(kind: .tron).requiresCustomExtension)
        XCTAssertEqual(NewFileKindPresentation(kind: .tron).extensionBadgeText(customExtension: ""), ".tron")
        XCTAssertNil(NewFileKindPresentation(kind: .other).extensionBadgeText(customExtension: "md"))

        let csv = CSVViewerPresentation(content: "name,score\nAda,10\nBob")
        XCTAssertEqual(csv.rows, [["name", "score"], ["Ada", "10"], ["Bob"]])
        XCTAssertEqual(csv.maxColumnCount, 2)
        XCTAssertEqual(csv.cellText(row: 2, column: 1), "")
        XCTAssertTrue(csv.isHeader(row: 0))
        XCTAssertFalse(csv.isHeader(row: 1))

        let quotedCSV = CSVViewerPresentation(content: "\"name, full\",score\n\"Ada, Lovelace\",10")
        XCTAssertEqual(quotedCSV.rows[0], ["name, full", "score"])
        XCTAssertEqual(quotedCSV.rows[1], ["Ada, Lovelace", "10"])

        let unsupported = UnsupportedViewerPresentation(fileName: "archive.bin", language: "zh")
        XCTAssertEqual(unsupported.title, "archive.bin 暂无可用预览")
        XCTAssertEqual(unsupported.subtitle, "安装轻量 viewer 插件以支持这种文件类型。")

        let settings = ProjectSettingsPresentation(
            activeProjectPath: "/tmp/project",
            language: "en"
        )
        XCTAssertEqual(settings.lines(" one \n\n two "), ["one", "two"])
        XCTAssertEqual(settings.runtimeRows.map(\.title), ["Project Path", "Execution", "Storage", "CLI Safety"])
        XCTAssertEqual(settings.runtimeRows.first?.value, "/tmp/project")
        XCTAssertEqual(ProjectSettingsPresentation(activeProjectPath: nil, language: "zh").runtimeRows.first?.value, "暂无项目")
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

    func testRunEventPresentationFormatsContentAndLogRows() throws {
        let textEvent = RunEvent.local(type: "message_delta", content: "Drafting outline")
        XCTAssertEqual(RunEventPresentation.displayText(for: textEvent), "Drafting outline")

        let objectEvent = RunEvent(
            type: "message_delta",
            content: AnyCodable(["summary": "Done"]),
            tool: nil,
            args: nil,
            output: nil,
            success: nil,
            step_id: nil,
            attempt: nil,
            decision: nil,
            reason: nil,
            error: nil,
            skills: nil
        )
        XCTAssertTrue(RunEventPresentation.displayText(for: objectEvent)?.contains("\"summary\" : \"Done\"") == true)

        let toolCall = RunEvent(
            type: "tool_call",
            content: nil,
            tool: "write_file",
            args: AnyCodable(["path": "deck.md"]),
            output: nil,
            success: nil,
            step_id: nil,
            attempt: nil,
            decision: nil,
            reason: nil,
            error: nil,
            skills: nil
        )
        XCTAssertEqual(RunEventPresentation.logText(for: toolCall), "TOOL write_file\nARGS {\"path\":\"deck.md\"}")

        let failedTool = RunEvent(
            type: "tool_result",
            content: AnyCodable("fallback"),
            tool: "write_file",
            args: nil,
            output: nil,
            success: false,
            step_id: nil,
            attempt: nil,
            decision: nil,
            reason: nil,
            error: nil,
            skills: nil
        )
        XCTAssertEqual(RunEventPresentation.logText(for: failedTool), "FAILED write_file\nfallback")

        let retry = RunEvent(
            type: "step_retried",
            content: nil,
            tool: nil,
            args: nil,
            output: nil,
            success: nil,
            step_id: "s1",
            attempt: 2,
            decision: "retry",
            reason: "transient",
            error: nil,
            skills: nil
        )
        XCTAssertEqual(RunEventPresentation.logText(for: retry), "STEP RETRY s1 attempt 2\nretry: transient")
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
}
