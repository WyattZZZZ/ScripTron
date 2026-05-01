import SwiftUI
import UniformTypeIdentifiers

struct ProjectStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewScript = false
    @State private var showingNewFolder = false
    @State private var renamingFile: FileEntry?
    @State private var explorerCollapsed = false
    @State private var dropTargeted = false

    private var activePanel: AppModel.ProjectPanel {
        if case .project(let panel) = model.screen { return panel }
        return .explorer
    }

    var body: some View {
        HStack(spacing: 0) {
            activityBar
            if !explorerCollapsed {
                explorerSidebar
            }
            VStack(spacing: 0) {
                titleBar
                if activePanel == .settings {
                    ProjectSettingsPanel()
                } else {
                    NotebookEditorView()
                }
                statusbar
            }
            .background(Color.editorBackground)
        }
        .sheet(isPresented: $showingNewScript) {
            NewScriptSheet(isPresented: $showingNewScript).environmentObject(model)
        }
        .sheet(isPresented: $showingNewFolder) {
            NewFolderSheet(isPresented: $showingNewFolder).environmentObject(model)
        }
        .sheet(item: $renamingFile) { file in
            RenameFileSheet(file: file, renamingFile: $renamingFile).environmentObject(model)
        }
    }

    private var activityBar: some View {
        VStack(spacing: 16) {
            Button { model.showWorkspace() } label: { Image(systemName: "chevron.left") }
            Divider().padding(.horizontal, 12)
            ActivityIcon(icon: "doc.text", active: activePanel == .explorer) { model.selectPanel(.explorer) }
            ActivityIcon(icon: "gearshape", active: activePanel == .settings) { model.selectPanel(.settings) }
            Spacer()
            Button { explorerCollapsed.toggle() } label: { Image(systemName: explorerCollapsed ? "sidebar.left" : "sidebar.leading") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.primaryGreen)
        .padding(.vertical, 12)
        .frame(width: 56)
        .background(Color.projectRail)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.hairline.opacity(0.55)), alignment: .trailing)
    }

    private var explorerSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXPLORER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showingNewScript = true } label: { Image(systemName: "plus") }
                Button { showingNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                Button { model.refreshFiles() } label: { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primaryGreen)
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.files.isEmpty {
                        Text("No files yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(14)
                    } else {
                        ForEach(model.files) { file in
                            FileTreeRow(file: file) {
                                renamingFile = file
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .overlay(alignment: .bottom) {
                if dropTargeted {
                    DropCopyHint()
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: 260)
        .background(Color.projectPanel)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Color.hairline.opacity(0.55)), alignment: .trailing)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            model.copyDroppedFiles(providers)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: dropTargeted)
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            if let name = model.selectedFile?.path.split(separator: "/").last.map(String.init) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                    Text(name)
                    if model.isDirty { Circle().frame(width: 7, height: 7).foregroundStyle(.orange) }
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.primaryGreen), alignment: .bottom)
            } else {
                Text("No script open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
            Spacer()
            Button("Run Paused") {}
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(true)
                .padding(.horizontal, 14)
            Button("Save") { model.saveSelectedFile() }
                .buttonStyle(.plain)
                .foregroundStyle(model.isDirty ? Color.primaryGreen : .secondary)
                .disabled(model.selectedFile == nil || !model.isDirty)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.white.opacity(0.78))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.hairline.opacity(0.7)), alignment: .bottom)
    }

    private var statusbar: some View {
        HStack(spacing: 18) {
            Text("SCRIPTRON")
            Text("RUST FFI")
            Text(model.status.uppercased())
            Spacer()
            Text("UTF-8")
            Text(".TRON")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.white.opacity(0.78))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.hairline.opacity(0.55)), alignment: .top)
    }
}

private struct ActivityIcon: View {
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 38, height: 34)
                .foregroundStyle(active ? Color.primaryGreen : .secondary)
                .background(active ? Color.primaryGreen.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct DropCopyHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
            Text("Drop to copy")
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Color.primaryGreen)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primaryGreen.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct FileTreeRow: View {
    @EnvironmentObject private var model: AppModel
    let file: FileEntry
    let rename: () -> Void

    private var selected: Bool { model.selectedFile?.path == file.path }

    var body: some View {
        Button { model.openFile(file) } label: {
            HStack(spacing: 8) {
                Image(systemName: file.is_dir ? "folder" : "doc.text")
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(file.name)
                    .lineLimit(1)
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(selected ? Color.primaryGreen : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(selected ? Color.primaryGreen.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .contextMenu {
            if file.is_tron {
                Button {
                    model.openFile(file)
                } label: {
                    Label("Open", systemImage: "doc.text.magnifyingglass")
                }
            }
            Button {
                rename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.deleteFile(file)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct NotebookEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.selectedFile == nil {
            EmptyNotebookState()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    documentToolbar
                    if model.documentBlocks.isEmpty {
                        EmptyDocumentCanvas()
                            .environmentObject(model)
                    } else {
                        ForEach(model.documentBlocks) { block in
                            DocumentFlowRow(block: block)
                                .environmentObject(model)
                        }
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 72)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.editorBackground)
        }
    }

    private var documentToolbar: some View {
        HStack(spacing: 10) {
            Text("Document")
                .font(.system(size: 20, weight: .bold))
            Text(model.isDirty ? "Unsaved" : "Saved")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(model.isDirty ? .orange : Color.primaryGreen)
            Spacer()
            Text("Hover a line and use the left + menu")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 14)
    }
}

private struct DocumentFlowRow: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @State private var hovering = false

    private var content: Binding<String> {
        Binding(
            get: { model.documentBlocks.first(where: { $0.id == block.id })?.content ?? "" },
            set: { model.updateDocumentBlock(block, content: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BlockPlusMenu(block: block, visible: hovering)
                .environmentObject(model)
                .padding(.top, block.kind == .markdownLine ? 4 : 16)

            HStack(alignment: .top, spacing: 0) {
                switch block.kind {
                case .markdownLine:
                    MarkdownLineView(block: block, text: content)
                        .environmentObject(model)
                case .table:
                    TableBlockView(block: block, markdown: content)
                        .environmentObject(model)
                case .run:
                    RunInlineBlock(block: block, text: content)
                        .environmentObject(model)
                case .gen:
                    GenInlineBlock(block: block, text: content)
                        .environmentObject(model)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: hovering)
    }
}

private struct BlockPlusMenu: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    let visible: Bool

    var body: some View {
        Menu {
            Button {
                model.insertDocumentBlock(after: block, kind: .gen)
            } label: {
                Label("Gen Cell", systemImage: "sparkles")
            }
            Button {
                model.insertDocumentBlock(after: block, kind: .run)
            } label: {
                Label("Run Cell", systemImage: "terminal")
            }
            Divider()
            Button {
                model.insertTable(after: block)
            } label: {
                Label("New Table", systemImage: "tablecells")
            }
            Button {
                model.setHeading(block, level: 1)
            } label: {
                Label("Set Title", systemImage: "textformat.size")
            }
            Button {
                model.setHeading(block, level: 2)
            } label: {
                Label("Set Heading", systemImage: "textformat")
            }
            Button {
                model.toggleOrderedList(block)
            } label: {
                Label("Numbered List", systemImage: "list.number")
            }
            Button {
                model.toggleBulletList(block)
            } label: {
                Label("Bullet List", systemImage: "list.bullet")
            }
            Button {
                model.insertDivider(after: block)
            } label: {
                Label("Divider", systemImage: "minus")
            }
            Divider()
            Button(role: .destructive) {
                model.deleteDocumentBlock(block)
            } label: {
                Label("Delete Block", systemImage: "trash")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primaryGreen.opacity(0.18), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }
}

private struct EmptyDocumentCanvas: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Start writing markdown...", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onSubmit(commitLine)
                .padding(.vertical, 8)

            HStack(spacing: 10) {
                Button { model.insertDocumentBlock(after: nil, kind: .gen) } label: { Label("Gen", systemImage: "sparkles") }
                Button { model.insertDocumentBlock(after: nil, kind: .run) } label: { Label("Run", systemImage: "terminal") }
                Button { model.insertTable(after: nil) } label: { Label("Table", systemImage: "tablecells") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.primaryGreen)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            DispatchQueue.main.async {
                focused = true
            }
        }
    }

    private func commitLine() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.insertDocumentBlock(after: nil, kind: .markdownLine)
        if let first = model.documentBlocks.first {
            model.updateDocumentBlock(first, content: text)
        }
        draft = ""
    }
}

private struct MarkdownLineView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String

    var body: some View {
        TextField("Markdown", text: $text)
            .textFieldStyle(.plain)
            .font(fontForLine(text))
            .onSubmit { model.insertDocumentBlock(after: block, kind: .markdownLine) }
        .padding(.vertical, lineVerticalPadding(text))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fontForLine(_ line: String) -> Font {
        if line.hasPrefix("# ") { return .system(size: 30, weight: .bold) }
        if line.hasPrefix("## ") { return .system(size: 23, weight: .bold) }
        if line.hasPrefix("### ") { return .system(size: 18, weight: .bold) }
        return .system(size: 15)
    }

    private func lineVerticalPadding(_ line: String) -> CGFloat {
        line.trimmingCharacters(in: .whitespaces).isEmpty ? 6 : 3
    }
}

private struct MarkdownLineRender: View {
    let text: String

    var body: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(size: 15))
                .frame(height: 20)
        } else if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(defaultFont)
                .lineSpacing(5)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(defaultFont)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
    }

    private var defaultFont: Font {
        if text.hasPrefix("# ") { return .system(size: 30, weight: .bold) }
        if text.hasPrefix("## ") { return .system(size: 23, weight: .bold) }
        if text.hasPrefix("### ") { return .system(size: 18, weight: .bold) }
        return .system(size: 15)
    }
}

private struct TableBlockView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var markdown: String

    var body: some View {
        EditableMarkdownTable(table: MarkdownTable(markdown: markdown)) { updated in
            markdown = updated.markdown
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct MarkdownTable {
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

    private static func cells(from line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct EditableMarkdownTable: View {
    @State private var table: MarkdownTable
    let onChange: (MarkdownTable) -> Void

    init(table: MarkdownTable, onChange: @escaping (MarkdownTable) -> Void) {
        self._table = State(initialValue: table)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        TableCellField(text: Binding(
                            get: { table.headers[column] },
                            set: { table.headers[column] = $0; onChange(table) }
                        ), header: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            TableCellField(text: Binding(
                                get: { column < table.rows[row].count ? table.rows[row][column] : "" },
                                set: { value in
                                    while table.rows[row].count <= column { table.rows[row].append("") }
                                    table.rows[row][column] = value
                                    onChange(table)
                                }
                            ), header: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.85), lineWidth: 1))

            HStack(spacing: 12) {
                Button { addRow() } label: { Label("Row", systemImage: "plus") }
                Button { addColumn() } label: { Label("Column", systemImage: "plus") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.primaryGreen)
        }
    }

    private func addRow() {
        table.rows.append(Array(repeating: "", count: table.headers.count))
        onChange(table)
    }

    private func addColumn() {
        table.headers.append("Column \(table.headers.count + 1)")
        for row in table.rows.indices {
            table.rows[row].append("")
        }
        onChange(table)
    }
}

private struct TableCellField: View {
    @Binding var text: String
    let header: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: header ? .bold : .regular))
            .padding(.horizontal, 10)
            .frame(minWidth: 130, minHeight: 36, alignment: .leading)
            .background(header ? Color.surfaceSoft : .white)
            .overlay(Rectangle().stroke(Color.hairline.opacity(0.45), lineWidth: 0.5))
    }
}

private struct RunInlineBlock: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Run Cell Paused", systemImage: "terminal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.deleteDocumentBlock(block) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.surfaceSoft)

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 110)
                .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.hairline.opacity(0.75), lineWidth: 1))
        .padding(.vertical, 8)
    }
}

private struct GenInlineBlock: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Gen Markdown", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                Spacer()
                Button("Generate") { model.generateMarkdown(from: block) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                Button { model.deleteDocumentBlock(block) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 118)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primaryGreen.opacity(0.18), lineWidth: 1))
        }
        .padding(16)
        .background(Color.primaryGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primaryGreen.opacity(0.20), lineWidth: 1))
        .padding(.vertical, 8)
    }
}

private struct EmptyNotebookState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(Color.primaryGreen)
            Text("Open or create a .tron script")
                .font(.system(size: 24, weight: .bold))
            Text("The editor uses a document-first markdown canvas with inline Run and Gen blocks.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NewScriptSheet: View {
    private enum NewFileKind: String, CaseIterable, Identifiable {
        case tron = "Tron"
        case word = "Word"
        case excel = "Excel"
        case other = "Other"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .tron: "tron"
            case .word: "docx"
            case .excel: "xlsx"
            case .other: ""
            }
        }

        var placeholder: String {
            switch self {
            case .tron: "customer_onboarding"
            case .word: "project_brief"
            case .excel: "metrics_table"
            case .other: "notes"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var scriptName = ""
    @State private var fileKind: NewFileKind = .tron
    @State private var customExtension = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New File").font(.system(size: 28, weight: .bold))

            Picker("File Type", selection: $fileKind) {
                ForEach(NewFileKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField(fileKind.placeholder, text: $scriptName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createScript)

            if fileKind == .other {
                TextField("custom extension, for example: json", text: $customExtension)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createScript)
            } else {
                Text(".\(fileKind.fileExtension)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primaryGreen.opacity(0.10), in: Capsule())
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button("Create") {
                    createScript()
                }
                .buttonStyle(SheetActionButtonStyle(primary: true))
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear {
            DispatchQueue.main.async {
                nameFocused = true
            }
        }
    }

    private func createScript() {
        let fileExtension = fileKind == .other ? customExtension : fileKind.fileExtension
        model.createFile(named: scriptName, fileExtension: fileExtension)
        isPresented = false
    }
}

private struct NewFolderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var folderName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Folder").font(.system(size: 28, weight: .bold))
            TextField("assets", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createFolder)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button("Create") {
                    createFolder()
                }
                .buttonStyle(SheetActionButtonStyle(primary: true))
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear {
            DispatchQueue.main.async {
                nameFocused = true
            }
        }
    }

    private func createFolder() {
        model.createFolder(named: folderName)
        isPresented = false
    }
}

private struct RenameFileSheet: View {
    @EnvironmentObject private var model: AppModel
    let file: FileEntry
    @Binding var renamingFile: FileEntry?
    @State private var fileName: String
    @FocusState private var nameFocused: Bool

    init(file: FileEntry, renamingFile: Binding<FileEntry?>) {
        self.file = file
        self._renamingFile = renamingFile
        self._fileName = State(initialValue: file.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename").font(.system(size: 28, weight: .bold))
            TextField("Name", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(renameFile)
            HStack {
                Spacer()
                Button("Cancel") { renamingFile = nil }
                    .buttonStyle(SheetActionButtonStyle())
                Button("Rename") {
                    renameFile()
                }
                .buttonStyle(SheetActionButtonStyle(primary: true))
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear {
            DispatchQueue.main.async {
                nameFocused = true
            }
        }
    }

    private func renameFile() {
        model.renameFile(file, to: fileName)
        renamingFile = nil
    }
}

private struct ProjectSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
                .padding(18)
            Divider()
            SettingsRow(title: "Project Path", value: "Local workspace")
            SettingsRow(title: "Execution", value: "Rust FFI")
            SettingsRow(title: "Storage", value: ".tron files")
            Spacer()
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .bold))
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(.white)
        Divider()
    }
}
