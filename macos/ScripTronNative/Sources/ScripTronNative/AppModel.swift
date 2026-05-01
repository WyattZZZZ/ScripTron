import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Screen {
        case workspace
        case project(ProjectPanel)
    }

    enum WorkspacePanel: String, CaseIterable, Identifiable {
        case allProjects = "All Projects"
        case archived = "Archived"
        case cliMarket = "CLI Market"
        case cliManagement = "CLI Management"
        case modelManagement = "Model Management"

        var id: String { rawValue }
    }

    enum ProjectPanel: String, CaseIterable, Identifiable {
        case explorer = "Explorer"
        case settings = "Settings"

        var id: String { rawValue }
    }

    struct ProjectItem: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var path: String
        var status: String
        var archived: Bool = false
        var packaged: Bool = false
    }

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        let content: String
    }

    enum DocumentBlockKind: Equatable {
        case markdownLine
        case table
        case run
        case gen
    }

    struct DocumentBlock: Identifiable, Equatable {
        let id = UUID()
        var kind: DocumentBlockKind
        var content: String
    }

    @Published var screen: Screen = .workspace
    @Published var workspacePanel: WorkspacePanel = .allProjects
    @Published var workspacePath = "Loading..."
    @Published var activeProjectPath: String?
    @Published var activeProjectName = ""
    @Published var files: [FileEntry] = []
    @Published var projects: [ProjectItem] = []
    @Published var selectedFile: TronFile?
    @Published var draftCells: [TronCell] = []
    @Published var documentBlocks: [DocumentBlock] = []
    @Published var isDirty = false
    @Published var newScriptName = "untitled"
    @Published var runEvents: [RunEvent] = []
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: "system", content: "Workspace Agent is scoped to project planning, file organization, CLI setup, and model configuration. It should not promise sharing or cloud collaboration features.")
    ]
    @Published var status = "Starting"
    @Published var errorMessage: String?

    private let bridge = RustBridge.shared

    private var projectRootPath: String {
        activeProjectPath ?? workspacePath
    }

    func boot() {
        do {
            try bridge.initialize()
            workspacePath = try bridge.call("get_workspace_path", as: String.self)
            files = try bridge.call("list_workspace_files", as: [FileEntry].self)
            rebuildProjects()
            status = "Connected"
        } catch {
            errorMessage = error.localizedDescription
            status = "Rust bridge error"
        }
    }

    func openProject(panel: ProjectPanel = .explorer) {
        screen = .project(panel)
        loadProjectFiles()
    }

    func openProject(_ project: ProjectItem, panel: ProjectPanel = .explorer) {
        activeProjectPath = project.path
        activeProjectName = project.name
        selectedFile = nil
        draftCells = []
        documentBlocks = []
        isDirty = false
        screen = .project(panel)
        loadProjectFiles()
    }

    func showWorkspace() {
        screen = .workspace
        activeProjectPath = nil
        activeProjectName = ""
        selectedFile = nil
        draftCells = []
        documentBlocks = []
        isDirty = false
        refreshFiles()
    }

    func selectPanel(_ panel: ProjectPanel) {
        screen = .project(panel)
    }

    func refreshFiles() {
        do {
            if activeProjectPath != nil, case .project = screen {
                files = try bridge.call("list_dir_files", params: ["path": projectRootPath], as: [FileEntry].self)
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
            status = activeProjectName.isEmpty ? "Project opened" : "Opened \(activeProjectName)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Project open failed"
        }
    }

    func selectWorkspacePanel(_ panel: WorkspacePanel) {
        workspacePanel = panel
    }

    func createProject(named rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Project name cannot be empty."
            return
        }
        let directoryName = sanitizedPathComponent(trimmed.replacingOccurrences(of: " ", with: "-").lowercased())
        let targetDirectory = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let projectURL = uniqueDestinationURL(for: directoryName, in: targetDirectory)

        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
            refreshFiles()
            workspacePanel = .allProjects
            status = "Created project \(trimmed)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Create project failed"
        }
    }

    func archiveProject(_ project: ProjectItem) {
        updateProject(project) { item in
            item.archived = true
            item.status = "Archived"
        }
    }

    func restoreProject(_ project: ProjectItem) {
        updateProject(project) { item in
            item.archived = false
            item.status = "Ready"
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
            try FileManager.default.removeItem(at: URL(fileURLWithPath: project.path))
            projects.removeAll { $0.path == project.path }
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
        chatMessages.append(ChatMessage(role: "agent", content: "Plan noted. I can help organize projects, scripts, CLI tools, and model settings inside this local workspace."))
    }

    func openFile(_ file: FileEntry) {
        guard file.is_tron else { return }
        do {
            selectedFile = try bridge.call("open_tron_file", params: ["path": file.path], as: TronFile.self)
            draftCells = selectedFile?.cells ?? []
            documentBlocks = Self.documentBlocks(from: draftCells)
            isDirty = false
            screen = .project(.explorer)
            status = "Opened \(file.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
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

        let targetDirectory = URL(fileURLWithPath: projectRootPath, isDirectory: true)
        let destinationURL = uniqueDestinationURL(for: trimmed, in: targetDirectory)

        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            refreshFiles()
            status = "Created folder \(destinationURL.lastPathComponent)"
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

        let sourceURL = URL(fileURLWithPath: file.path)
        let targetURL = uniqueDestinationURL(for: trimmed, in: sourceURL.deletingLastPathComponent())

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            if selectedFile?.path == file.path {
                selectedFile = nil
                draftCells = []
                documentBlocks = []
                isDirty = false
            }
            refreshFiles()
            status = "Renamed to \(targetURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Rename failed"
        }
    }

    func deleteFile(_ file: FileEntry) {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: file.path))
            if selectedFile?.path == file.path {
                selectedFile = nil
                draftCells = []
                documentBlocks = []
                isDirty = false
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
        let manager = FileManager.default
        let requestedURL = URL(fileURLWithPath: path)
        let destinationURL = uniqueDestinationURL(for: requestedURL.lastPathComponent, in: requestedURL.deletingLastPathComponent())

        do {
            try manager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard manager.createFile(atPath: destinationURL.path, contents: Data()) else {
                errorMessage = "Could not create \(fileName)."
                status = "Create failed"
                return
            }
            refreshFiles()
            selectedFile = nil
            draftCells = []
            documentBlocks = []
            isDirty = false
            screen = .project(.explorer)
            status = "Created \(destinationURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Create failed"
        }
    }

    func copyDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
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
                    self?.copyDroppedFile(from: sourceURL)
                }
            }
        }

        return true
    }

    func updateCell(_ cell: TronCell, content: String) {
        guard let index = draftCells.firstIndex(where: { $0.id == cell.id }) else { return }
        draftCells[index].content = content
        isDirty = true
    }

    func updateDocumentBlock(_ block: DocumentBlock, content: String) {
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks[index].content = content
        isDirty = true
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
        insertDocumentBlocks([DocumentBlock(kind: .markdownLine, content: "---")], after: block)
    }

    func setHeading(_ block: DocumentBlock, level: Int) {
        guard block.kind == .markdownLine else { return }
        let clean = block.content
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        updateDocumentBlock(block, content: "\(String(repeating: "#", count: max(1, min(level, 3)))) \(clean)")
    }

    func toggleOrderedList(_ block: DocumentBlock) {
        guard block.kind == .markdownLine else { return }
        let clean = block.content
            .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        updateDocumentBlock(block, content: "1. \(clean)")
    }

    func toggleBulletList(_ block: DocumentBlock) {
        guard block.kind == .markdownLine else { return }
        let clean = block.content
            .replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        updateDocumentBlock(block, content: "- \(clean)")
    }

    private func insertDocumentBlocks(_ newBlocks: [DocumentBlock], after block: DocumentBlock?) {
        guard !newBlocks.isEmpty else { return }
        guard let block, let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else {
            documentBlocks.insert(contentsOf: newBlocks, at: 0)
            isDirty = true
            return
        }
        documentBlocks.insert(contentsOf: newBlocks, at: documentBlocks.index(after: index))
        isDirty = true
    }

    func deleteDocumentBlock(_ block: DocumentBlock) {
        guard documentBlocks.count > 1 else {
            updateDocumentBlock(block, content: "")
            return
        }
        documentBlocks.removeAll { $0.id == block.id }
        isDirty = true
    }

    func generateMarkdown(from block: DocumentBlock) {
        let markdown = Self.markdownFromNaturalLanguage(block.content)
        let lines = Self.markdownLineBlocks(from: markdown)
        guard let index = documentBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        documentBlocks.remove(at: index)
        documentBlocks.insert(contentsOf: lines, at: index)
        isDirty = true
        status = "Generated markdown"
    }

    private func defaultContent(for kind: DocumentBlockKind) -> String {
        switch kind {
        case .markdownLine: ""
        case .table:
            """
            | Column 1 | Column 2 | Column 3 |
            | --- | --- | --- |
            |  |  |  |
            """
        case .run: ""
        case .gen: ""
        }
    }

    func toggleCell(_ cell: TronCell) {
        guard let index = draftCells.firstIndex(where: { $0.id == cell.id }) else { return }
        draftCells[index].run.toggle()
        isDirty = true
    }

    func addCell(run: Bool) {
        draftCells.append(TronCell(run: run, content: ""))
        isDirty = true
    }

    func insertCell(after cell: TronCell?, run: Bool) {
        let newCell = TronCell(run: run, content: "")
        guard let cell, let index = draftCells.firstIndex(where: { $0.id == cell.id }) else {
            draftCells.insert(newCell, at: 0)
            isDirty = true
            return
        }
        draftCells.insert(newCell, at: draftCells.index(after: index))
        isDirty = true
    }

    func insertGenCell(after cell: TronCell?) {
        let newCell = TronCell(run: true, content: "\(Self.genCellPrefix)\n")
        guard let cell, let index = draftCells.firstIndex(where: { $0.id == cell.id }) else {
            draftCells.insert(newCell, at: 0)
            isDirty = true
            return
        }
        draftCells.insert(newCell, at: draftCells.index(after: index))
        isDirty = true
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
        isDirty = true
        status = "Generated markdown"
    }

    func deleteCell(_ cell: TronCell) {
        guard draftCells.count > 1 else { return }
        draftCells.removeAll { $0.id == cell.id }
        isDirty = true
    }

    func saveSelectedFile() {
        guard let file = selectedFile else {
            errorMessage = "No script is open."
            return
        }
        do {
            try bridge.callVoid("save_tron_file", params: [
                "path": file.path,
                "cells": Self.cells(from: documentBlocks).map { ["run": $0.run, "content": $0.content] },
                "blackboard": file.blackboard.value
            ])
            selectedFile = try bridge.call("open_tron_file", params: ["path": file.path], as: TronFile.self)
            draftCells = selectedFile?.cells ?? []
            documentBlocks = Self.documentBlocks(from: draftCells)
            isDirty = false
            status = "Saved \(file.path.split(separator: "/").last ?? "script")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runPreview() {
        do {
            try bridge.callVoid("run_task_preview", params: [
                "cells": Self.cells(from: documentBlocks).map { ["run": $0.run, "content": $0.content] },
                "project_path": projectRootPath
            ])
            runEvents = try bridge.call("poll_events", as: [RunEvent].self)
            status = "Run preview complete"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildProjects() {
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let directoryURLs = (try? FileManager.default.contentsOfDirectory(
            at: workspaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        projects = directoryURLs.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { return nil }
            return ProjectItem(name: url.lastPathComponent, path: url.path, status: "Ready")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateProject(_ project: ProjectItem, mutate: (inout ProjectItem) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        mutate(&projects[index])
        status = "\(projects[index].name): \(projects[index].status)"
    }

    private static let genCellPrefix = "[[scriptron:gen-markdown]]"

    private static func documentBlocks(from cells: [TronCell]) -> [DocumentBlock] {
        let blocks = cells.flatMap { cell -> [DocumentBlock] in
            if cell.run && cell.content.hasPrefix(genCellPrefix) {
                let prompt = String(cell.content.dropFirst(genCellPrefix.count)).trimmingCharacters(in: .newlines)
                return [DocumentBlock(kind: .gen, content: prompt)]
            }
            if cell.run {
                return [DocumentBlock(kind: .run, content: cell.content)]
            }
            return markdownLineBlocks(from: cell.content)
        }
        return blocks
    }

    private static func markdownLineBlocks(from markdown: String) -> [DocumentBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [DocumentBlock] = []
        var index = 0

        while index < lines.count {
            if index + 1 < lines.count, isMarkdownTableSeparator(lines[index + 1]), lines[index].contains("|") {
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

    private static func cells(from blocks: [DocumentBlock]) -> [TronCell] {
        var cells: [TronCell] = []
        var markdownBuffer: [String] = []

        func flushMarkdown() {
            guard !markdownBuffer.isEmpty else { return }
            cells.append(TronCell(run: false, content: markdownBuffer.joined(separator: "\n")))
            markdownBuffer.removeAll()
        }

        for block in blocks {
            switch block.kind {
            case .markdownLine:
                markdownBuffer.append(block.content)
            case .table:
                markdownBuffer.append(block.content)
            case .run:
                flushMarkdown()
                cells.append(TronCell(run: true, content: block.content))
            case .gen:
                flushMarkdown()
                cells.append(TronCell(run: true, content: "\(genCellPrefix)\n\(block.content)"))
            }
        }

        flushMarkdown()
        return cells
    }

    private static func markdownFromNaturalLanguage(_ prompt: String) -> String {
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

    private static func titleFromPrompt(_ prompt: String) -> String {
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

    private func fileNameForCreation(baseName: String, fileExtension: String) -> String {
        let sanitizedBaseName = sanitizedPathComponent(baseName)
        let suffix = ".\(fileExtension)"
        if sanitizedBaseName.lowercased().hasSuffix(suffix) {
            return sanitizedBaseName
        }
        return "\(sanitizedBaseName)\(suffix)"
    }

    private func sanitizedPathComponent(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private func copyDroppedFile(from sourceURL: URL) {
        let manager = FileManager.default
        let targetDirectory = URL(fileURLWithPath: projectRootPath, isDirectory: true)

        do {
            try manager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent, in: targetDirectory)
            try manager.copyItem(at: sourceURL, to: destinationURL)
            refreshFiles()
            status = "Copied \(destinationURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
            status = "Copy failed"
        }
    }

    private func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let manager = FileManager.default
        let originalURL = directory.appendingPathComponent(fileName)
        guard manager.fileExists(atPath: originalURL.path) else { return originalURL }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension

        for suffix in 2...999 {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !manager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
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
}
