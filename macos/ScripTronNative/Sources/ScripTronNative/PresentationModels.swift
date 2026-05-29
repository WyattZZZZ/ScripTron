import Foundation

struct WorkspaceProjectListPresentation {
    let archived: Bool
    let projects: [AppModel.ProjectItem]
    let language: String

    var visibleProjects: [AppModel.ProjectItem] {
        projects.filter { $0.archived == archived }
    }

    var title: String {
        localized("Projects", "项目", archived: "Archived Projects", "归档项目")
    }

    var subtitle: String {
        localized(
            "Manage, package, open, archive, or delete local automation projects.",
            "管理、打包、打开、归档或删除本地自动化项目。",
            archived: "Restore or delete archived local projects.",
            "恢复或删除已归档的本地项目。"
        )
    }

    var emptyTitle: String {
        localized("No projects", "暂无项目", archived: "No archived projects", "暂无归档项目")
    }

    var emptySubtitle: String {
        localize("Create a project from the sidebar.", "从侧边栏创建一个项目。")
    }

    var allowsZipDrop: Bool {
        !archived
    }

    private func localized(_ english: String, _ chinese: String, archived archivedEnglish: String, _ archivedChinese: String) -> String {
        archived ? localize(archivedEnglish, archivedChinese) : localize(english, chinese)
    }

    private func localize(_ english: String, _ chinese: String) -> String {
        language == "zh" ? chinese : english
    }
}

struct FileIconPresentation {
    static func iconName(path: String, isDirectory: Bool = false, isExpanded: Bool = false, isTron: Bool = false) -> String {
        if isDirectory { return isExpanded ? "folder.fill" : "folder" }
        if isTron { return "doc.richtext" }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "rs": return "shippingbox"
        case "py": return "curlybraces"
        case "js", "jsx", "ts", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "html", "css": return "globe"
        case "json", "toml", "yaml", "yml", "xml": return "curlybraces.square"
        case "md", "markdown": return "doc.text"
        case "csv": return "tablecells"
        case "xls", "xlsx", "numbers": return "tablecells.badge.ellipsis"
        case "doc", "docx", "pages": return "doc.text"
        case "pdf": return "doc.text.magnifyingglass"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg": return "photo"
        case "zip", "tar", "gz", "7z": return "archivebox"
        case "sh", "bash", "zsh": return "terminal"
        case "txt", "log": return "doc.plaintext"
        default: return "doc"
        }
    }
}

struct ProjectTabPresentation {
    let tab: FileEntry

    var iconName: String {
        FileIconPresentation.iconName(path: tab.path, isTron: tab.is_tron)
    }
}

struct EditorTabButtonPresentation {
    enum TextEmphasis: Equatable {
        case active
        case inactive
    }

    enum BackgroundState: Equatable {
        case clear
        case hovered
        case active
    }

    let tab: FileEntry
    let active: Bool
    let dirty: Bool
    let hovering: Bool

    var iconName: String {
        ProjectTabPresentation(tab: tab).iconName
    }

    var showsDirtyIndicator: Bool {
        dirty
    }

    var textEmphasis: TextEmphasis {
        active ? .active : .inactive
    }

    var backgroundState: BackgroundState {
        if active { return .active }
        if hovering { return .hovered }
        return .clear
    }

    var closeButtonHighlighted: Bool {
        hovering
    }

    var underlineHeight: Double {
        active ? 2 : 0
    }
}

struct ProjectStatusBarPresentation {
    let status: String
    let openedViewer: AppModel.ViewerKind?

    var statusText: String {
        status.uppercased()
    }

    var viewerText: String {
        openedViewer?.rawValue.uppercased() ?? ".TRON"
    }
}

struct ProjectRowPresentation {
    let project: AppModel.ProjectItem
    let archived: Bool

    var iconName: String {
        project.packaged ? "shippingbox.fill" : "folder"
    }

    var statusText: String {
        project.status.uppercased()
    }

    var actionsWidth: Double {
        archived ? 218 : 342
    }

    var disablesOpenAndPackage: Bool {
        archived
    }
}

enum CatalogActionPresentation {
    static func title(for action: ExtensionCatalogAction, language: String) -> String {
        let zh = language == "zh"
        switch action {
        case .installIntoHermes:
            return zh ? "安装到 Hermes" : "Install into Hermes"
        case .installIntoScripTron:
            return zh ? "安装到 ScripTron" : "Install into ScripTron"
        case .remove:
            return zh ? "移除" : "Remove"
        case .update:
            return zh ? "更新" : "Update"
        }
    }
}

struct ExtensionCatalogCardPresentation {
    let item: ExtensionCatalogItem
    let language: String

    var iconName: String {
        item.icon
    }

    var visibleBadges: [String] {
        Array(item.displayBadges.prefix(5))
    }

    var actionTitle: String {
        CatalogActionPresentation.title(for: item.primaryAction, language: language)
    }
}

struct RegistryItemPresentation {
    let kind: String

    var iconName: String {
        switch kind {
        case "model": return "cpu"
        case "software": return "app.connected.to.app.below.fill"
        default: return "terminal"
        }
    }
}

struct TronhubEntryPresentation {
    let kind: String

    var iconName: String {
        switch kind {
        case "skill": return "sparkles"
        case "model": return "cpu"
        default: return "terminal"
        }
    }
}

struct FileTreeRowPresentation {
    enum BackgroundState: Equatable {
        case clear
        case selected
        case draggedSource
        case dropTargeted
    }

    let file: FileEntry
    let depth: Int
    let selectedPath: String?
    let openedPath: String?
    let expandedPaths: Set<String>
    let childCount: Int
    let dropHoverPath: String?
    let draggedPath: String?

    var selected: Bool {
        selectedPath == file.path || openedPath == file.path
    }

    var expanded: Bool {
        expandedPaths.contains(file.path)
    }

    var dropTargeted: Bool {
        file.is_dir && dropHoverPath == file.path
    }

    var draggedSource: Bool {
        draggedPath == file.path
    }

    var showsChildren: Bool {
        file.is_dir && expanded && childCount > 0
    }

    var chevronIcon: String? {
        guard file.is_dir else { return nil }
        return expanded ? "chevron.down" : "chevron.right"
    }

    var iconName: String {
        FileIconPresentation.iconName(
            path: file.path,
            isDirectory: file.is_dir,
            isExpanded: expanded,
            isTron: file.is_tron
        )
    }

    var leadingPadding: Double {
        Double(depth) * 14 + 8
    }

    var backgroundState: BackgroundState {
        if dropTargeted { return .dropTargeted }
        if draggedSource { return .draggedSource }
        if selected { return .selected }
        return .clear
    }

    var opacity: Double {
        draggedSource ? 0.72 : 1
    }
}

struct DocumentBlockRowPresentation {
    enum IndicatorState: Equatable {
        case idle
        case hovered
        case selected
    }

    let kind: AppModel.DocumentBlockKind
    let selected: Bool
    let hovering: Bool

    var controlTopPadding: Double {
        kind == .markdownLine ? 3 : 16
    }

    var plusMenuTopPadding: Double {
        kind == .markdownLine ? 4 : 16
    }

    var indicatorState: IndicatorState {
        if selected { return .selected }
        if hovering { return .hovered }
        return .idle
    }
}

struct DocumentToolbarPresentation {
    enum StatusState: Equatable {
        case dirty
        case saved
    }

    let isDirty: Bool
    let selectedCount: Int
    let language: String

    var statusText: String {
        isDirty ? localize("Unsaved", "未保存") : localize("Saved", "已保存")
    }

    var statusState: StatusState {
        isDirty ? .dirty : .saved
    }

    var selectedText: String? {
        guard selectedCount > 0 else { return nil }
        return language == "zh" ? "已选择 \(selectedCount) 个" : "\(selectedCount) selected"
    }

    var showsBulkDelete: Bool {
        selectedCount > 0
    }

    private func localize(_ english: String, _ chinese: String) -> String {
        language == "zh" ? chinese : english
    }
}

struct MarkdownLinePresentation {
    enum Kind: Equatable {
        case plain
        case heading1
        case heading2
        case heading3
        case quote
        case code
    }

    enum FontWeight: Equatable {
        case regular
        case bold
    }

    enum FontDesign: Equatable {
        case standard
        case serif
        case monospaced
    }

    enum ForegroundState: Equatable {
        case primary
        case secondary
        case accent
    }

    enum BackgroundState: Equatable {
        case clear
        case quote
        case code
    }

    let text: String

    var kind: Kind {
        if text.hasPrefix("# ") { return .heading1 }
        if text.hasPrefix("## ") { return .heading2 }
        if text.hasPrefix("### ") { return .heading3 }
        if text.hasPrefix("> ") { return .quote }
        if text.hasPrefix("`") { return .code }
        return .plain
    }

    var isDivider: Bool {
        text.trimmingCharacters(in: .whitespaces) == "---"
    }

    var fontSize: Double {
        switch kind {
        case .heading1: return 30
        case .heading2: return 23
        case .heading3: return 18
        case .quote: return 15
        case .code: return 14
        case .plain: return 15
        }
    }

    var fontWeight: FontWeight {
        switch kind {
        case .heading1, .heading2, .heading3: return .bold
        case .plain, .quote, .code: return .regular
        }
    }

    var fontDesign: FontDesign {
        switch kind {
        case .quote: return .serif
        case .code: return .monospaced
        case .plain, .heading1, .heading2, .heading3: return .standard
        }
    }

    var foregroundState: ForegroundState {
        switch kind {
        case .quote: return .secondary
        case .code: return .accent
        case .plain, .heading1, .heading2, .heading3: return .primary
        }
    }

    var backgroundState: BackgroundState {
        switch kind {
        case .quote: return .quote
        case .code: return .code
        case .plain, .heading1, .heading2, .heading3: return .clear
        }
    }

    var horizontalPadding: Double {
        hasInlineContainer ? 8 : 0
    }

    var verticalPadding: Double {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 6 : 3
    }

    var hasInlineContainer: Bool {
        kind == .quote || kind == .code
    }
}

struct ListBlockPresentation {
    let text: String
    let ordered: Bool

    var items: [String] {
        let parsed = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? [""] : parsed
    }

    var deleteButtonOpacity: Double {
        items.count > 1 ? 0.75 : 0
    }

    func marker(at index: Int) -> String {
        ordered ? "\(index + 1)." : "•"
    }

    func markdown(afterSetting value: String, at index: Int) -> String {
        var updated = items
        guard updated.indices.contains(index) else { return markdown(from: updated) }
        updated[index] = value
        return markdown(from: updated)
    }

    func markdown(afterAddingItemAfter index: Int) -> String {
        var updated = items
        updated.insert("", at: min(index + 1, updated.count))
        return markdown(from: updated)
    }

    func markdown(afterDeleting index: Int) -> String {
        var updated = items
        guard updated.indices.contains(index), updated.count > 1 else { return markdown(from: updated) }
        updated.remove(at: index)
        return markdown(from: updated)
    }

    private func markdown(from items: [String]) -> String {
        items.joined(separator: "\n")
    }
}

struct MarkdownTablePresentation: Equatable {
    var headers: [String]
    var rows: [[String]]

    init(markdown: String) {
        let lines = markdown.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        headers = Self.cells(from: lines.first ?? "| Column 1 | Column 2 | Column 3 |")
        rows = lines.dropFirst(2).map { Self.cells(from: $0) }
        if rows.isEmpty {
            rows = [Array(repeating: "", count: max(headers.count, 1))]
        }
    }

    init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows.isEmpty ? [Array(repeating: "", count: max(headers.count, 1))] : rows
    }

    var markdown: String {
        let safeHeaders = headers.isEmpty ? ["Column 1"] : headers
        let separator = "| " + safeHeaders.map { _ in "---" }.joined(separator: " | ") + " |"
        let header = "| " + safeHeaders.joined(separator: " | ") + " |"
        let body = rows.map { row in
            let padded = row + Array(repeating: "", count: max(0, safeHeaders.count - row.count))
            return "| " + padded.prefix(safeHeaders.count).joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return [header, separator, body].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func withHeader(_ value: String, at column: Int) -> MarkdownTablePresentation {
        var updated = self
        guard updated.headers.indices.contains(column) else { return updated }
        updated.headers[column] = value
        return updated
    }

    func withCell(_ value: String, row: Int, column: Int) -> MarkdownTablePresentation {
        var updated = self
        guard updated.rows.indices.contains(row) else { return updated }
        while updated.rows[row].count <= column { updated.rows[row].append("") }
        updated.rows[row][column] = value
        return updated
    }

    func addedRow() -> MarkdownTablePresentation {
        var updated = self
        updated.rows.append(Array(repeating: "", count: updated.headers.count))
        return updated
    }

    func deletedRow(_ row: Int) -> MarkdownTablePresentation {
        var updated = self
        guard updated.rows.indices.contains(row) else { return updated }
        updated.rows.remove(at: row)
        if updated.rows.isEmpty {
            updated.rows.append(Array(repeating: "", count: updated.headers.count))
        }
        return updated
    }

    func addedColumn() -> MarkdownTablePresentation {
        var updated = self
        updated.headers.append("Column \(updated.headers.count + 1)")
        for row in updated.rows.indices {
            updated.rows[row].append("")
        }
        return updated
    }

    func deletedColumn(_ column: Int) -> MarkdownTablePresentation {
        var updated = self
        guard updated.headers.indices.contains(column), updated.headers.count > 1 else { return updated }
        updated.headers.remove(at: column)
        for row in updated.rows.indices where updated.rows[row].indices.contains(column) {
            updated.rows[row].remove(at: column)
        }
        return updated
    }

    private static func cells(from line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct ChecklistItemPresentation: Equatable {
    var checked: Bool
    var text: String
}

struct ChecklistBlockPresentation {
    let text: String

    var items: [ChecklistItemPresentation] {
        let parsed = text.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]") {
                return ChecklistItemPresentation(
                    checked: true,
                    text: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                )
            }
            if trimmed.hasPrefix("[ ]") {
                return ChecklistItemPresentation(
                    checked: false,
                    text: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                )
            }
            return ChecklistItemPresentation(checked: false, text: trimmed)
        }
        .filter { !$0.text.isEmpty }
        return parsed.isEmpty ? [ChecklistItemPresentation(checked: false, text: "")] : parsed
    }

    var markdown: String {
        Self.markdown(from: items)
    }

    var deleteButtonOpacity: Double {
        items.count > 1 ? 0.75 : 0
    }

    func markdown(afterSettingText value: String, at index: Int) -> String {
        var updated = items
        guard updated.indices.contains(index) else { return Self.markdown(from: updated) }
        updated[index].text = value
        return Self.markdown(from: updated)
    }

    func markdown(afterSettingChecked value: Bool, at index: Int) -> String {
        var updated = items
        guard updated.indices.contains(index) else { return Self.markdown(from: updated) }
        updated[index].checked = value
        return Self.markdown(from: updated)
    }

    func markdown(afterAddingItemAfter index: Int) -> String {
        var updated = items
        updated.insert(ChecklistItemPresentation(checked: false, text: ""), at: min(index + 1, updated.count))
        return Self.markdown(from: updated)
    }

    func markdown(afterDeleting index: Int) -> String {
        var updated = items
        guard updated.indices.contains(index), updated.count > 1 else { return Self.markdown(from: updated) }
        updated.remove(at: index)
        return Self.markdown(from: updated)
    }

    static func markdown(from items: [ChecklistItemPresentation]) -> String {
        items.map { "\($0.checked ? "[x]" : "[ ]") \($0.text)" }.joined(separator: "\n")
    }
}

struct RunInlineMentionPresentation {
    let text: String

    var query: String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let suffix = String(text[text.index(after: at)...])
        if suffix.contains(where: { $0.isWhitespace }) { return nil }
        return suffix
    }

    func textAfterInserting(label: String, moduleName: String?) -> String {
        let token = moduleName.map { "@\(label)#\($0)" } ?? "@\(label)"
        if let at = text.lastIndex(of: "@") {
            var updated = text
            updated.replaceSubrange(at..<updated.endIndex, with: token + " ")
            return updated
        }
        return text + token + " "
    }
}

struct MentionPickerPresentation {
    let tab: String
    let search: MentionSearchResult
    let functionMentions: [MentionItem]

    var items: [MentionItem] {
        switch tab {
        case "Skills", "Tools":
            return search.tools + search.cloud_suggestions
        case "Functions":
            return functionMentions
        default:
            return search.files
        }
    }

    func iconName(for item: MentionItem) -> String {
        switch item.kind {
        case "skill": return "sparkles"
        case "function": return "function"
        case "tool", "software", "model": return "terminal"
        case "tron": return "doc.richtext"
        case "cloud": return "icloud"
        default: return "doc"
        }
    }

    func moduleForSelection(_ item: MentionItem) -> MentionModule? {
        item.kind == "function" ? item.modules.first : nil
    }

    func showsCloudBadge(for item: MentionItem) -> Bool {
        !item.installed
    }
}

enum NewFileKind: String, CaseIterable, Identifiable {
    case tron = "Tron"
    case word = "Word"
    case excel = "Excel"
    case other = "Other"

    var id: String { rawValue }
}

struct NewFileKindPresentation {
    let kind: NewFileKind

    var placeholder: String {
        switch kind {
        case .tron: return "customer_onboarding"
        case .word: return "project_brief"
        case .excel: return "metrics_table"
        case .other: return "notes"
        }
    }

    var requiresCustomExtension: Bool {
        kind == .other
    }

    func fileExtension(customExtension: String) -> String {
        switch kind {
        case .tron:
            return "tron"
        case .word:
            return "docx"
        case .excel:
            return "xlsx"
        case .other:
            return customExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func extensionBadgeText(customExtension: String) -> String? {
        guard !requiresCustomExtension else { return nil }
        return ".\(fileExtension(customExtension: customExtension))"
    }
}

struct CSVViewerPresentation {
    let content: String

    var rows: [[String]] {
        Self.parse(content)
    }

    var maxColumnCount: Int {
        max(rows.map(\.count).max() ?? 1, 1)
    }

    func cellText(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    func isHeader(row: Int) -> Bool {
        row == 0
    }

    private static func parse(_ source: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        for character in source {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n" && !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows.isEmpty ? [[""]] : rows
    }
}

struct UnsupportedViewerPresentation {
    let fileName: String
    let language: String

    var title: String {
        language == "zh" ? "\(fileName) 暂无可用预览" : "No viewer for \(fileName)"
    }

    var subtitle: String {
        language == "zh"
            ? "安装轻量 viewer 插件以支持这种文件类型。"
            : "Install a lightweight viewer plugin to support this file type."
    }
}

struct ProjectSettingsRuntimeRow: Equatable {
    let title: String
    let value: String
}

struct ProjectSettingsPresentation {
    let activeProjectPath: String?
    let language: String

    var runtimeRows: [ProjectSettingsRuntimeRow] {
        [
            ProjectSettingsRuntimeRow(title: localize("Project Path", "项目路径"), value: activeProjectPath ?? localize("No project", "暂无项目")),
            ProjectSettingsRuntimeRow(title: localize("Execution", "执行"), value: "Rust FFI + Local scriptron CLI"),
            ProjectSettingsRuntimeRow(title: localize("Storage", "存储"), value: ".tron files, .troner.json, .register"),
            ProjectSettingsRuntimeRow(
                title: localize("CLI Safety", "CLI 安全"),
                value: localize("Writes limited to ~/Documents or SCRIPTRON_PROJECT", "写入限制在 ~/Documents 或 SCRIPTRON_PROJECT")
            )
        ]
    }

    func lines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func localize(_ english: String, _ chinese: String) -> String {
        language == "zh" ? chinese : english
    }
}
