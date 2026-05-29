import AppKit
import AVKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct ProjectStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewScript = false
    @State private var showingNewFolder = false
    @State private var renamingFile: FileEntry?
    @State private var explorerCollapsed = false
    @State private var dropTargeted = false
    @State private var internalDropTargeted = false
    @State private var tabPendingClose: FileEntry?

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
                editorContent
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
        .alert(model.tr("Close unsaved file?", "关闭未保存文件？"), isPresented: Binding(
            get: { tabPendingClose != nil },
            set: { if !$0 { tabPendingClose = nil } }
        )) {
            Button(model.tr("Cancel", "取消"), role: .cancel) {
                tabPendingClose = nil
            }
            Button(model.tr("Discard Changes", "放弃更改"), role: .destructive) {
                if let tabPendingClose {
                    model.closeTab(tabPendingClose, discardChanges: true)
                }
                tabPendingClose = nil
            }
        } message: {
            Text(model.tr("This tab has unsaved changes. Closing it will discard those edits.", "这个标签页有未保存更改，关闭会丢弃这些编辑。"))
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
                Text(model.tr("EXPLORER", "文件"))
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
                        Text(model.tr("No files yet", "暂无文件"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(14)
                    } else {
                        ForEach(model.files) { file in
                            FileTreeNode(file: file, depth: 0) { target in
                                renamingFile = target
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
        .onDrop(of: [.text], isTargeted: $internalDropTargeted) { providers in
            model.finishDropInteraction()
            return model.moveTextDroppedFiles(providers)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: dropTargeted)
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            if model.openTabs.isEmpty {
                Text(model.tr("No file open", "未打开文件"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.openTabs) { tab in
                            EditorTabButton(
                                tab: tab,
                                active: model.activeTabPath == tab.path,
                                dirty: model.isTabDirty(tab),
                                requestClose: { target in
                                    if model.isTabDirty(target) {
                                        tabPendingClose = target
                                    } else {
                                        model.closeTab(target)
                                    }
                                }
                            )
                            .environmentObject(model)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer()
            Button(model.isRunningTask ? model.tr("Running...", "运行中...") : model.tr("Run", "运行")) { model.submitHermesPrompt() }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedFile == nil || model.isRunningTask ? .secondary : Color.primaryGreen)
                .disabled(model.selectedFile == nil || model.isRunningTask)
                .padding(.horizontal, 14)
            Button(model.tr("Save", "保存")) { model.saveSelectedFile() }
                .buttonStyle(.plain)
                .foregroundStyle(model.isDirty ? Color.primaryGreen : .secondary)
                .disabled((model.selectedFile == nil && model.openedFile == nil) || !model.isDirty)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color.surfaceSoft.opacity(0.72))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.hairline.opacity(0.7)), alignment: .bottom)
    }

    @ViewBuilder
    private var editorContent: some View {
        if activePanel == .settings {
            ProjectSettingsPanel()
        } else if model.openedFile != nil {
            FileViewerHost()
        } else {
            NotebookEditorView()
        }
    }

    private var statusbar: some View {
        HStack(spacing: 18) {
            Text("SCRIPTRON")
            Text("RUST FFI")
            Text(statusPresentation.statusText)
            Spacer()
            Text("UTF-8")
            Text(statusPresentation.viewerText)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.white.opacity(0.78))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.hairline.opacity(0.55)), alignment: .top)
    }

    private var statusPresentation: ProjectStatusBarPresentation {
        ProjectStatusBarPresentation(
            status: model.status,
            openedViewer: model.openedFile?.viewer
        )
    }
}

private struct EditorTabButton: View {
    @EnvironmentObject private var model: AppModel
    let tab: FileEntry
    let active: Bool
    let dirty: Bool
    let requestClose: (FileEntry) -> Void
    @State private var hovering = false

    private var presentation: EditorTabButtonPresentation {
        EditorTabButtonPresentation(tab: tab, active: active, dirty: dirty, hovering: hovering)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 12))
            Text(tab.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150)
            if presentation.showsDirtyIndicator {
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.orange)
            }
            Button {
                requestClose(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(presentation.closeButtonHighlighted ? Color.hairline.opacity(0.45) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: tabFontWeight))
        .foregroundStyle(tabForeground)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            tabBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: CGFloat(presentation.underlineHeight))
                .foregroundStyle(Color.primaryGreen)
                .padding(.horizontal, 10)
        }
        .onTapGesture {
            model.activateTab(tab)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private var tabFontWeight: Font.Weight {
        presentation.textEmphasis == .active ? .bold : .medium
    }

    private var tabForeground: Color {
        presentation.textEmphasis == .active ? Color.appText : Color.appSecondaryText
    }

    private var tabBackground: Color {
        switch presentation.backgroundState {
        case .active:
            return .white
        case .hovered:
            return Color.primaryGreen.opacity(0.06)
        case .clear:
            return Color.clear
        }
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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
            Text(model.tr("Drop to copy", "松开复制"))
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

private struct FileTreeNode: View {
    @EnvironmentObject private var model: AppModel
    let file: FileEntry
    let depth: Int
    let rename: (FileEntry) -> Void

    private var children: [FileEntry] { model.folderChildren[file.path] ?? [] }
    private var presentation: FileTreeRowPresentation {
        FileTreeRowPresentation(
            file: file,
            depth: depth,
            selectedPath: model.selectedFile?.path,
            openedPath: model.openedFile?.path,
            expandedPaths: model.expandedFolders,
            childCount: children.count,
            dropHoverPath: model.dropHoverFolderPath,
            draggedPath: model.draggedFilePath
        )
    }
    private var selected: Bool { presentation.selected }
    private var expanded: Bool { presentation.expanded }
    private var dropTargeted: Bool { presentation.dropTargeted }
    private var draggedSource: Bool { presentation.draggedSource }
    private var rowBackground: Color {
        switch presentation.backgroundState {
        case .dropTargeted: return Color.primaryGreen.opacity(0.20)
        case .draggedSource: return Color.primaryGreen.opacity(0.06)
        case .selected: return Color.primaryGreen.opacity(0.10)
        case .clear: return Color.clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
                .padding(.horizontal, 8)

            if presentation.showsChildren {
                ForEach(children) { child in
                    FileTreeNode(file: child, depth: depth + 1, rename: rename)
                        .environmentObject(model)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 7) {
            if file.is_dir {
                Image(systemName: presentation.chevronIcon ?? "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }
            Image(systemName: iconName)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(file.name)
                .lineLimit(1)
            Spacer()
            if dropTargeted {
                Text(model.tr("Drop", "拖入"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.72), in: Capsule())
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(selected ? Color.primaryGreen : Color.appText)
        .padding(.leading, CGFloat(presentation.leadingPadding))
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dropTargeted ? Color.primaryGreen.opacity(0.38) : Color.clear, lineWidth: 1)
        )
        .opacity(presentation.opacity)
        .onTapGesture { model.openFile(file) }
        .contextMenu {
            Button { model.openFile(file) } label: {
                Label(file.is_dir ? model.tr("Expand", "展开") : model.tr("Open", "打开"), systemImage: file.is_dir ? "folder" : "doc.text.magnifyingglass")
            }
            Button { rename(file) } label: {
                Label(model.tr("Rename", "重命名"), systemImage: "pencil")
            }
            Button(role: .destructive) { model.deleteFile(file) } label: {
                Label(model.tr("Delete", "删除"), systemImage: "trash")
            }
        }
        .onDrag {
            model.beginDraggingFile(file.path)
            let provider = NSItemProvider()
            provider.suggestedName = file.name
            provider.registerObject(file.path as NSString, visibility: .all)
            return provider
        }
        .onDrop(
            of: [.fileURL, .text],
            delegate: FileTreeDropDelegate(file: file, model: model)
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.86), value: dropTargeted)
        .animation(.easeOut(duration: 0.12), value: draggedSource)
    }

    private var iconName: String {
        presentation.iconName
    }
}

private struct FileTreeDropDelegate: DropDelegate {
    let file: FileEntry
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool {
        file.is_dir && (
            info.hasItemsConforming(to: [UTType.fileURL]) ||
            info.hasItemsConforming(to: [UTType.text])
        )
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        model.hoverDropFolder(file.path)
        if !model.expandedFolders.contains(file.path) {
            model.toggleFolder(file)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        model.hoverDropFolder(file.path)
        return DropProposal(operation: info.hasItemsConforming(to: [UTType.fileURL]) ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        if model.dropHoverFolderPath == file.path {
            model.hoverDropFolder(nil)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        model.finishDropInteraction()
        guard file.is_dir else { return false }

        if info.hasItemsConforming(to: [UTType.text]) {
            return model.moveTextDroppedFiles(
                info.itemProviders(for: [UTType.text]),
                to: file.path
            )
        }

        if info.hasItemsConforming(to: [UTType.fileURL]) {
            return model.copyDroppedFiles(
                info.itemProviders(for: [UTType.fileURL]),
                to: file.path
            )
        }

        return false
    }
}

private struct FileViewerHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let file = model.openedFile {
            switch file.viewer {
            case .csv:
                CSVViewer(file: file)
                    .environmentObject(model)
                    .id(file.path)
            case .pdf, .word, .excel, .quickLook:
                QuickLookDocumentViewer(file: file)
                    .id(file.path)
            case .code, .text:
                CodeViewer(file: file)
                    .environmentObject(model)
                    .id(file.path)
            case .unsupported:
                UnsupportedViewer(file: file)
            }
        } else {
            EmptyNotebookState()
        }
    }
}

private struct CodeViewer: View {
    @EnvironmentObject private var model: AppModel
    let file: AppModel.OpenedFile

    private var content: Binding<String> {
        Binding(
            get: { model.openedFile?.content ?? file.content },
            set: { model.updateOpenedFileContent($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerToolbar(title: file.language, subtitle: file.path) {
                EmptyView()
            }
            HighlightedCodeEditor(text: content, language: file.language)
                .clipShape(Rectangle())
        }
    }
}

private struct HighlightedCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let language: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .white

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(Color.appText)
        textView.backgroundColor = .white
        textView.insertionPointColor = NSColor(Color.primaryGreen)
        textView.textContainerInset = NSSize(width: 14, height: 16)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = ruler
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.applyHighlighting(to: textView, text: text, language: language)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.applyHighlighting(to: textView, text: text, language: language)
        }
        context.coordinator.ruler?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedCodeEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        private var applyingHighlight = false

        init(_ parent: HighlightedCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView, text: textView.string, language: parent.language)
            ruler?.needsDisplay = true
        }

        func applyHighlighting(to textView: NSTextView, text: String, language: String) {
            guard !applyingHighlight else { return }
            applyingHighlight = true
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(AppKitSyntaxHighlighter.highlight(text, language: language))
            textView.selectedRanges = selectedRanges
            applyingHighlight = false
        }
    }
}

private final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 52
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(Color.surfaceSoft.opacity(0.72)).setFill()
        bounds.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let text = textView.string as NSString
        let prefixLength = min(glyphRange.location, text.length)
        var lineNumber = text.substring(to: prefixLength).filter { $0 == "\n" }.count + 1
        var glyphIndex = glyphRange.location
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(Color.appSecondaryText).withAlphaComponent(0.72)
        ]

        while glyphIndex < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let y = lineRect.minY + textView.textContainerOrigin.y - visibleRect.minY + 2
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: y), withAttributes: attributes)

            glyphIndex = NSMaxRange(effectiveRange)
            lineNumber += 1
        }
    }
}

private enum AppKitSyntaxHighlighter {
    static func highlight(_ source: String, language: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: source)
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(Color.appText)
        ], range: fullRange)

        color(pattern: #"(?m)//.*$|#.*$"#, in: attributed, color: .systemGray)
        color(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, in: attributed, color: NSColor(red: 0.66, green: 0.24, blue: 0.18, alpha: 1))
        color(pattern: #"\b(import|from|class|struct|enum|func|function|let|var|const|if|else|for|while|return|switch|case|break|continue|async|await|try|catch|throw|throws|public|private|static|mut|fn|impl|use|mod|pub|def|lambda|package|interface|extends|type|protocol)\b"#, in: attributed, color: NSColor(Color.primaryGreen))
        color(pattern: #"\b(true|false|null|nil|None|Some|Ok|Err)\b"#, in: attributed, color: .systemPurple)
        color(pattern: #"\b\d+(\.\d+)?\b"#, in: attributed, color: .systemBlue)
        return attributed
    }

    private static func color(pattern: String, in attributed: NSMutableAttributedString, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        for match in regex.matches(in: attributed.string, range: range) {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private struct QuickLookDocumentViewer: View {
    let file: AppModel.OpenedFile

    var body: some View {
        VStack(spacing: 0) {
            ViewerToolbar(title: file.viewer.rawValue, subtitle: file.path) {
                EmptyView()
            }
            QuickLookPreview(url: URL(fileURLWithPath: file.path))
                .background(.white)
                .id(file.path)
        }
        .background(.white)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.autostarts = true
        preview.previewItem = context.coordinator
        return preview
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        context.coordinator.url = url
        preview.previewItem = context.coordinator
        preview.refreshPreviewItem()
    }

    final class Coordinator: NSObject, QLPreviewItem {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        var previewItemURL: URL? { url }
        var previewItemTitle: String? { url.lastPathComponent }
    }
}

private struct CSVViewer: View {
    @EnvironmentObject private var model: AppModel
    let file: AppModel.OpenedFile

    private var presentation: CSVViewerPresentation {
        CSVViewerPresentation(content: file.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerToolbar(title: "CSV", subtitle: file.path) {
                EmptyView()
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(presentation.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach((0..<presentation.maxColumnCount), id: \.self) { column in
                                Text(presentation.cellText(row: row, column: column))
                                    .font(.system(size: 12, weight: presentation.isHeader(row: row) ? .bold : .regular))
                                    .foregroundStyle(Color.appText)
                                    .padding(.horizontal, 10)
                                    .frame(minWidth: 130, minHeight: 34, alignment: .leading)
                                    .background(presentation.isHeader(row: row) ? Color.surfaceSoft : .white)
                                    .overlay(Rectangle().stroke(Color.hairline.opacity(0.45), lineWidth: 0.5))
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(.white)
        }
        .background(.white)
    }
}

private struct UnsupportedViewer: View {
    @EnvironmentObject private var model: AppModel
    let file: AppModel.OpenedFile
    private var presentation: UnsupportedViewerPresentation {
        UnsupportedViewerPresentation(fileName: file.name, language: model.appLanguage)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.app")
                .font(.system(size: 42))
                .foregroundStyle(Color.primaryGreen)
            Text(presentation.title)
                .font(.system(size: 22, weight: .bold))
            Text(presentation.subtitle)
                .foregroundStyle(Color.appSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ViewerToolbar<Action: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
            Spacer()
            action
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.surfaceSoft.opacity(0.96))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.hairline.opacity(0.7)), alignment: .bottom)
    }
}

private enum SyntaxHighlighter {
    static func highlight(_ source: String, language: String) -> AttributedString {
        var attributed = AttributedString(source)
        attributed.foregroundColor = Color.appText

        color(pattern: #"(?m)//.*$|#.*$"#, in: &attributed, source: source, color: .gray)
        color(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, in: &attributed, source: source, color: Color(red: 0.66, green: 0.24, blue: 0.18))
        color(pattern: #"\b(import|from|class|struct|enum|func|function|let|var|const|if|else|for|while|return|switch|case|break|continue|async|await|try|catch|throw|throws|public|private|static|mut|fn|impl|use|mod|pub|def|lambda|package|interface|extends|type|interface)\b"#, in: &attributed, source: source, color: Color.primaryGreen)
        color(pattern: #"\b(true|false|null|nil|None|Some|Ok|Err)\b"#, in: &attributed, source: source, color: .purple)
        color(pattern: #"\b\d+(\.\d+)?\b"#, in: &attributed, source: source, color: .blue)
        return attributed
    }

    private static func color(pattern: String, in attributed: inout AttributedString, source: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: nsRange) {
            guard let range = Range(match.range, in: source),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].foregroundColor = color
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
                        ForEach(Array(model.documentBlocks.enumerated()), id: \.element.id) { index, block in
                            DocumentFlowRow(block: block, blockIndex: index)
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
            Text(model.tr("Document", "文档"))
                .font(.system(size: 20, weight: .bold))
            Text(documentToolbarPresentation.statusText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(documentToolbarPresentation.statusState == .dirty ? .orange : Color.primaryGreen)
            Spacer()
            Text(model.tr("Hover a line and use the left + menu", "悬停到一行，使用左侧 + 菜单"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if documentToolbarPresentation.showsBulkDelete {
                Text(documentToolbarPresentation.selectedText ?? "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                Button(role: .destructive) {
                    model.deleteSelectedDocumentBlocks()
                } label: {
                    Label(model.tr("Delete", "删除"), systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
            }
        }
        .padding(.bottom, 14)
    }

    private var documentToolbarPresentation: DocumentToolbarPresentation {
        DocumentToolbarPresentation(
            isDirty: model.isDirty,
            selectedCount: model.selectedDocumentBlockIDs.count,
            language: model.appLanguage
        )
    }
}

private struct DocumentFlowRow: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    let blockIndex: Int
    @State private var hovering = false

    private var selected: Bool {
        model.selectedDocumentBlockIDs.contains(block.id)
    }

    private var presentation: DocumentBlockRowPresentation {
        DocumentBlockRowPresentation(kind: block.kind, selected: selected, hovering: hovering)
    }

    private var indicatorFill: Color {
        switch presentation.indicatorState {
        case .selected:
            return Color.primaryGreen
        case .hovered:
            return Color.primaryGreen.opacity(0.25)
        case .idle:
            return Color.hairline.opacity(0.45)
        }
    }

    private var indicatorStrokeOpacity: Double {
        presentation.indicatorState == .selected ? 0.35 : 0
    }

    private var content: Binding<String> {
        Binding(
            get: { model.documentBlocks.first(where: { $0.id == block.id })?.content ?? "" },
            set: { model.updateDocumentBlock(block, content: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                let flags = NSEvent.modifierFlags
                model.selectDocumentBlock(
                    block,
                    toggling: flags.contains(.command),
                    extending: flags.contains(.shift)
                )
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(indicatorFill)
                    .frame(width: 10, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primaryGreen.opacity(indicatorStrokeOpacity), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, CGFloat(presentation.controlTopPadding))

            BlockPlusMenu(block: block, visible: hovering)
                .environmentObject(model)
                .padding(.top, CGFloat(presentation.plusMenuTopPadding))

            HStack(alignment: .top, spacing: 0) {
                switch block.kind {
                case .markdownLine:
                    MarkdownLineView(block: block, text: content, blockIndex: blockIndex)
                        .environmentObject(model)
                case .heading(let level):
                    HeadingBlockView(block: block, text: content, level: level)
                        .environmentObject(model)
                case .list(let ordered):
                    ListBlockView(block: block, text: content, ordered: ordered)
                        .environmentObject(model)
                case .table:
                    TableBlockView(block: block, markdown: content)
                        .environmentObject(model)
                case .quote:
                    QuoteBlockView(block: block, text: content)
                        .environmentObject(model)
                case .code:
                    CodeBlockView(text: content)
                case .checklist:
                    ChecklistBlockView(text: content)
                        .environmentObject(model)
                case .divider:
                    DividerBlockView()
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
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(selected ? Color.primaryGreen.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.primaryGreen.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
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
                Label(model.tr("Gen Cell", "生成块"), systemImage: "sparkles")
            }
            Button {
                model.insertDocumentBlock(after: block, kind: .run)
            } label: {
                Label(model.tr("Run Cell", "运行块"), systemImage: "terminal")
            }
            Divider()
            Button {
                model.insertTable(after: block)
            } label: {
                Label(model.tr("New Table", "新建表格"), systemImage: "tablecells")
            }
            Button {
                model.setHeading(block, level: 1)
            } label: {
                Label(model.tr("Heading 1", "一级标题"), systemImage: "textformat.size")
            }
            Button {
                model.setHeading(block, level: 2)
            } label: {
                Label(model.tr("Heading 2", "二级标题"), systemImage: "textformat")
            }
            Button {
                model.setHeading(block, level: 3)
            } label: {
                Label(model.tr("Heading 3", "三级标题"), systemImage: "textformat")
            }
            Button {
                model.toggleOrderedList(block)
            } label: {
                Label(model.tr("Numbered List", "有序列表"), systemImage: "list.number")
            }
            Button {
                model.toggleBulletList(block)
            } label: {
                Label(model.tr("Bullet List", "无序列表"), systemImage: "list.bullet")
            }
            Button {
                model.insertDivider(after: block)
            } label: {
                Label(model.tr("Divider", "分割线"), systemImage: "minus")
            }
            Button {
                model.convertBlock(block, to: .quote)
            } label: {
                Label(model.tr("Quote", "引用块"), systemImage: "quote.opening")
            }
            Button {
                model.convertBlock(block, to: .code)
            } label: {
                Label(model.tr("Code Block", "代码块"), systemImage: "curlybraces")
            }
            Button {
                model.convertBlock(block, to: .checklist)
            } label: {
                Label(model.tr("Checkboxes", "复选框"), systemImage: "checklist")
            }
            Divider()
            Button(role: .destructive) {
                model.deleteDocumentBlock(block)
            } label: {
                Label(model.tr("Delete Block", "删除块"), systemImage: "trash")
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
            TextField(model.tr("Start writing markdown...", "开始写 Markdown..."), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onSubmit(commitLine)
                .padding(.vertical, 8)

            HStack(spacing: 10) {
                Button { model.insertDocumentBlock(after: nil, kind: .gen) } label: { Label(model.tr("Gen", "生成"), systemImage: "sparkles") }
                Button { model.insertDocumentBlock(after: nil, kind: .run) } label: { Label(model.tr("Run", "运行"), systemImage: "terminal") }
                Button { model.insertTable(after: nil) } label: { Label(model.tr("Table", "表格"), systemImage: "tablecells") }
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
    let blockIndex: Int

    private var isFocusTarget: Bool { model.focusedBlockID == block.id }
    private var presentation: MarkdownLinePresentation {
        MarkdownLinePresentation(text: text)
    }

    private func moveUp() {
        guard blockIndex > 0 else { return }
        model.focusedBlockID = model.documentBlocks[blockIndex - 1].id
    }

    private func moveDown() {
        guard blockIndex < model.documentBlocks.count - 1 else { return }
        model.focusedBlockID = model.documentBlocks[blockIndex + 1].id
    }

    var body: some View {
        if presentation.isDivider {
            HStack(spacing: 10) {
                Rectangle().frame(height: 1).foregroundStyle(Color.hairline)
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(width: 42)
                    .onSubmit { model.continueMarkdownLine(after: block) }
                Rectangle().frame(height: 1).foregroundStyle(Color.hairline)
            }
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            BackspaceAwareTextField(
                placeholder: model.tr("Markdown", "Markdown"),
                text: $text,
                font: nsFontForLine,
                textColor: NSColor(foregroundForLine),
                isFocusTarget: isFocusTarget,
                onSubmit: { model.continueMarkdownLine(after: block) },
                onEmptyBackspace: { model.deleteEmptyMarkdownBlockBefore(block) },
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                onDidFocus: { model.focusedBlockID = nil }
            )
                .padding(.vertical, CGFloat(presentation.verticalPadding))
                .padding(.horizontal, CGFloat(presentation.horizontalPadding))
                .background(backgroundForLine, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nsFontForLine: NSFont {
        switch presentation.fontDesign {
        case .monospaced:
            return .monospacedSystemFont(ofSize: presentation.fontSize, weight: nsFontWeight)
        case .standard, .serif:
            return .systemFont(ofSize: presentation.fontSize, weight: nsFontWeight)
        }
    }

    private var nsFontWeight: NSFont.Weight {
        presentation.fontWeight == .bold ? .bold : .regular
    }

    private var foregroundForLine: Color {
        switch presentation.foregroundState {
        case .primary:
            return Color.appText
        case .secondary:
            return Color.appSecondaryText
        case .accent:
            return Color.primaryGreen
        }
    }

    private var backgroundForLine: Color {
        switch presentation.backgroundState {
        case .code:
            return Color.primaryGreen.opacity(0.07)
        case .quote:
            return Color.surfaceSoft.opacity(0.72)
        case .clear:
            return Color.clear
        }
    }
}

private struct HeadingBlockView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String
    let level: Int

    var body: some View {
        TextField(model.tr("Heading", "标题"), text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Color.appText)
            .onSubmit { model.continueMarkdownLine(after: block) }
            .padding(.vertical, level == 1 ? 8 : 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var font: Font {
        switch level {
        case 1: .system(size: 30, weight: .bold)
        case 2: .system(size: 23, weight: .bold)
        default: .system(size: 18, weight: .bold)
        }
    }
}

private struct ListBlockView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String
    let ordered: Bool
    @State private var lines: [String] = []
    @FocusState private var focusedIndex: Int?

    private var presentation: ListBlockPresentation {
        ListBlockPresentation(text: text, ordered: ordered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.marker(at: index))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primaryGreen)
                        .frame(width: 24, alignment: .trailing)
                    TextField(model.tr("List item", "列表项"), text: Binding(
                        get: { lines.indices.contains(index) ? lines[index] : "" },
                        set: { value in
                            guard lines.indices.contains(index) else { return }
                            lines[index] = value
                            commit()
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focusedIndex, equals: index)
                    .onSubmit { addItem(after: index) }
                    Button { deleteItem(index) } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(presentation.deleteButtonOpacity)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncFromText() }
        .onChange(of: text) { _ in
            if text != lines.joined(separator: "\n") {
                syncFromText()
            }
        }
    }

    private func syncFromText() {
        lines = presentation.items
    }

    private func commit() {
        text = lines.joined(separator: "\n")
    }

    private func addItem(after index: Int) {
        lines.insert("", at: min(index + 1, lines.count))
        commit()
        DispatchQueue.main.async { focusedIndex = index + 1 }
    }

    private func deleteItem(_ index: Int) {
        guard lines.indices.contains(index), lines.count > 1 else { return }
        lines.remove(at: index)
        commit()
        DispatchQueue.main.async { focusedIndex = min(index, lines.count - 1) }
    }
}

private struct QuoteBlockView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color.primaryGreen.opacity(0.65)).frame(width: 3)
            TextEditor(text: $text)
                .font(.system(size: 15, design: .serif))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 46)
        }
        .padding(10)
        .background(Color.surfaceSoft.opacity(0.68), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodeBlockView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Color.appText)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: 118)
            .background(Color.surfaceSoft.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChecklistBlockView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var text: String
    @State private var items: [ChecklistItemPresentation] = []
    @FocusState private var focusedIndex: Int?

    private var presentation: ChecklistBlockPresentation {
        ChecklistBlockPresentation(text: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { items.indices.contains(index) && items[index].checked },
                        set: { value in
                            guard items.indices.contains(index) else { return }
                            items[index].checked = value
                            commit()
                        }
                    ))
                    .toggleStyle(.checkbox)
                    TextField(model.tr("Task", "任务"), text: Binding(
                        get: { items.indices.contains(index) ? items[index].text : "" },
                        set: { value in
                            guard items.indices.contains(index) else { return }
                            items[index].text = value
                            commit()
                        }
                    ))
                    .textFieldStyle(.plain)
                    .focused($focusedIndex, equals: index)
                    .onSubmit { addItem(after: index) }
                    Button { deleteItem(index) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(presentation.deleteButtonOpacity)
                }
            }
        }
        .padding(.vertical, 5)
        .onAppear { syncFromText() }
        .onChange(of: text) { _ in
            if text != markdown { syncFromText() }
        }
    }

    private var markdown: String {
        ChecklistBlockPresentation.markdown(from: items)
    }

    private func syncFromText() {
        items = presentation.items
    }

    private func commit() { text = markdown }

    private func addItem(after index: Int) {
        items.insert(ChecklistItemPresentation(checked: false, text: ""), at: min(index + 1, items.count))
        commit()
        DispatchQueue.main.async { focusedIndex = index + 1 }
    }

    private func deleteItem(_ index: Int) {
        guard items.indices.contains(index), items.count > 1 else { return }
        items.remove(at: index)
        commit()
    }
}

private struct DividerBlockView: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
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

private struct BackspaceAwareTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    var isFocusTarget: Bool = false
    let onSubmit: () -> Void
    let onEmptyBackspace: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onDidFocus: () -> Void = {}

    func makeNSView(context: Context) -> KeyAwareNSTextField {
        let field = KeyAwareNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.onEmptyBackspace = onEmptyBackspace
        field.onSubmitKey = onSubmit
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onDidFocus = onDidFocus
        return field
    }

    func updateNSView(_ nsView: KeyAwareNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.font = font
        nsView.textColor = textColor
        nsView.onEmptyBackspace = onEmptyBackspace
        nsView.onSubmitKey = onSubmit
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onDidFocus = onDidFocus

        if isFocusTarget {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
    }
}

private final class KeyAwareNSTextField: NSTextField {
    var onEmptyBackspace: () -> Void = {}
    var onSubmitKey: () -> Void = {}
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onDidFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onDidFocus() }
        return result
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51:  // Backspace
            if stringValue.isEmpty { onEmptyBackspace() }
            else { super.keyDown(with: event) }
        case 36, 76:  // Return / Enter
            if stringValue.isEmpty { onEmptyBackspace() }
            else { onSubmitKey() }
        case 126:  // Up arrow
            onMoveUp()
        case 125:  // Down arrow
            onMoveDown()
        default:
            super.keyDown(with: event)
        }
    }
}

private struct TableBlockView: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var markdown: String

    var body: some View {
        EditableMarkdownTable(table: MarkdownTablePresentation(markdown: markdown)) { updated in
            markdown = updated.markdown
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct EditableMarkdownTable: View {
    @EnvironmentObject private var model: AppModel
    @State private var table: MarkdownTablePresentation
    let onChange: (MarkdownTablePresentation) -> Void

    init(table: MarkdownTablePresentation, onChange: @escaping (MarkdownTablePresentation) -> Void) {
        self._table = State(initialValue: table)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        Button { deleteColumn(column) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.red.opacity(0.72))
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(.plain)
                        .background(Color.surfaceSoft.opacity(0.65))
                        .disabled(table.headers.count <= 1)
                        .opacity(table.headers.count > 1 ? 1 : 0.35)
                    }
                    Color.clear.frame(width: 32, height: 24)
                }
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { column in
                        TableCellField(text: Binding(
                            get: { table.headers[column] },
                            set: { table = table.withHeader($0, at: column); onChange(table) }
                        ), header: true)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { column in
                            TableCellField(text: Binding(
                            get: { column < table.rows[row].count ? table.rows[row][column] : "" },
                            set: { value in
                                    table = table.withCell(value, row: row, column: column)
                                    onChange(table)
                                }
                            ), header: false)
                        }
                        Button { deleteRow(row) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.red.opacity(0.78))
                                .frame(width: 32, height: 36)
                                .background(.white)
                                .overlay(Rectangle().stroke(Color.hairline.opacity(0.45), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.85), lineWidth: 1))

            HStack(spacing: 12) {
                Button { addRow() } label: { Label(model.tr("Row", "行"), systemImage: "plus") }
                Button { addColumn() } label: { Label(model.tr("Column", "列"), systemImage: "plus") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.primaryGreen)
        }
    }

    private func addRow() {
        table = table.addedRow()
        onChange(table)
    }

    private func deleteRow(_ row: Int) {
        table = table.deletedRow(row)
        onChange(table)
    }

    private func addColumn() {
        table = table.addedColumn()
        onChange(table)
    }

    private func deleteColumn(_ column: Int) {
        table = table.deletedColumn(column)
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
    @State private var mentionTab = "Skills"
    @State private var moduleItem: MentionItem?
    @State private var runName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.tr("Run", "运行"), systemImage: "terminal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                TextField("function_name", text: $runName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.appText)
                    .padding(.horizontal, 8)
                    .frame(width: 180, height: 24)
                    .background(.white.opacity(0.72), in: Capsule())
                    .onSubmit { model.updateRunBlockName(block, name: runName) }
                    .onChange(of: runName) { model.updateRunBlockName(block, name: $0) }
                Spacer()
                Button { model.submitHermesPrompt(block: block) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primaryGreen)
                    .disabled(model.isRunningTask)
                RunCellActionMenu(block: block)
                    .environmentObject(model)
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
                .onChange(of: text) { _ in updateMentionSearch() }
            if mentionQuery != nil {
                ProjectMentionPicker(tab: $mentionTab, moduleItem: $moduleItem, onSelect: insertMention)
                    .environmentObject(model)
                    .padding(10)
                    .background(Color.surfaceSoft.opacity(0.58))
            }
            if !model.runEvents(for: block).isEmpty {
                RunEventsPanel(block: block)
                    .environmentObject(model)
                    .padding(12)
                    .background(Color.surfaceSoft.opacity(0.40))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.hairline.opacity(0.75), lineWidth: 1))
        .padding(.vertical, 8)
        .onAppear { runName = block.name }
    }

    private var mentionQuery: String? {
        RunInlineMentionPresentation(text: text).query
    }

    private func updateMentionSearch() {
        guard let mentionQuery else {
            moduleItem = nil
            return
        }
        model.searchMentions(query: mentionQuery)
    }

    private func insertMention(_ item: MentionItem, _ module: MentionModule?) {
        model.selectMention(item, module: module)
        text = RunInlineMentionPresentation(text: text).textAfterInserting(label: item.label, moduleName: module?.name)
        moduleItem = nil
    }
}

private struct RunCellActionMenu: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    private let menu = RunCellActionMenuModel.default

    var body: some View {
        Menu {
            ForEach(menu.items, id: \.method) { item in
                Button {
                    dispatch(item)
                } label: {
                    Label(item.title, systemImage: item.icon)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .foregroundStyle(Color.appSecondaryText)
        .disabled(model.isRunningTask)
    }

    private func dispatch(_ item: HermesRunCommandItem) {
        switch item.method {
        case "prompt.submit":
            model.submitHermesPrompt(block: block)
        case "prompt.background":
            model.status = model.tr("Hermes background task dispatch is pending.", "Hermes 后台任务分发尚未接入。")
        case "session.steer":
            model.status = model.tr("Hermes session steering is pending.", "Hermes 会话引导尚未接入。")
        case "session.interrupt":
            model.status = model.tr("Hermes session interrupt is pending.", "Hermes 会话中断尚未接入。")
        case "session.compress":
            model.status = model.tr("Hermes session compression is pending.", "Hermes 会话压缩尚未接入。")
        case "session.branch":
            model.status = model.tr("Hermes session branching is pending.", "Hermes 会话分支尚未接入。")
        case "session.status":
            model.status = model.tr("Hermes gateway status is pending.", "Hermes 网关状态尚未接入。")
        case "session.usage":
            model.status = model.tr("Hermes usage reporting is pending.", "Hermes 用量报告尚未接入。")
        default:
            model.status = item.title
        }
    }
}

private struct RunEventsPanel: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @State private var showLog = false

    private var events: [RunEvent] {
        model.runEvents(for: block)
    }

    private var responseEvents: [RunEvent] {
        RunEventPresentation.sections(for: events).response
    }

    private var logEvents: [RunEvent] {
        RunEventPresentation.sections(for: events).log
    }

    private var delegationEvents: [RunEvent] {
        RunEventPresentation.sections(for: events).delegations
    }

    private var approvalEvents: [RunEvent] {
        RunEventPresentation.sections(for: events).approvals
    }

    var body: some View {
        if !responseEvents.isEmpty || !logEvents.isEmpty || !delegationEvents.isEmpty || !approvalEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.tr("Response", "响应"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.appSecondaryText)
                    Spacer()
                    Button {
                        showLog.toggle()
                    } label: {
                        Label(model.tr("Run Log", "运行日志"), systemImage: showLog ? "chevron.up" : "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                }
                if !responseEvents.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(responseEvents) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(model.tr("RESPONSE", "响应"))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.primaryGreen)
                                        Spacer()
                                    }
                                    if let text = RunEventPresentation.displayText(for: event) {
                                        RunResponseMarkdownView(
                                            markdown: text,
                                            basePath: model.activeProjectPath ?? model.workspacePath
                                        )
                                    }
                                }
                                .padding(10)
                                .background(Color.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
                if !delegationEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.tr("Agents", "Agents"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.appSecondaryText)
                        ForEach(delegationEvents) { event in
                            Text(RunEventPresentation.displayText(for: event) ?? event.type)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                if !approvalEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.tr("Needs Input", "需要输入"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.appSecondaryText)
                        ForEach(approvalEvents) { event in
                            Text(RunEventPresentation.displayText(for: event) ?? event.type)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.appText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.primaryGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                if showLog {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(logEvents) { event in
                                Text(RunEventPresentation.logText(for: event))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.appSecondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct RunResponseMarkdownView: View {
    let markdown: String
    let basePath: String

    private var segments: [RunResponseSegment] {
        RunResponseSegment.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .markdown(let text):
                    RunResponseText(markdown: text)
                case .media(let media):
                    RunResponseMediaView(media: media, basePath: basePath)
                }
            }
        }
    }
}

private enum RunResponseSegment {
    case markdown(String)
    case media(RunResponseMedia)

    static func parse(_ markdown: String) -> [RunResponseSegment] {
        var segments: [RunResponseSegment] = []
        var textLines: [String] = []

        func flushText() {
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.markdown(text))
            }
            textLines = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            if let media = RunResponseMedia.parse(line.trimmingCharacters(in: .whitespaces)) {
                flushText()
                segments.append(.media(media))
            } else {
                textLines.append(line)
            }
        }
        flushText()
        return segments.isEmpty ? [.markdown(markdown)] : segments
    }
}

private struct RunResponseMedia {
    enum Kind {
        case image
        case video
    }

    let alt: String
    let source: String
    let kind: Kind

    static func parse(_ line: String) -> RunResponseMedia? {
        if let pair = parseMarkdownPair(line, prefix: "![") {
            let kind: Kind = isVideoSource(pair.source) || pair.alt.localizedCaseInsensitiveContains("video") ? .video : .image
            return RunResponseMedia(alt: pair.alt, source: pair.source, kind: kind)
        }
        if let pair = parseMarkdownPair(line, prefix: "["), isVideoSource(pair.source) {
            return RunResponseMedia(alt: pair.alt, source: pair.source, kind: .video)
        }
        return nil
    }

    private static func parseMarkdownPair(_ line: String, prefix: String) -> (alt: String, source: String)? {
        guard line.hasPrefix(prefix), line.hasSuffix(")") else { return nil }
        let marker = "]("
        guard let markerRange = line.range(of: marker) else { return nil }
        let altStart = line.index(line.startIndex, offsetBy: prefix.count)
        let alt = String(line[altStart..<markerRange.lowerBound])
        let sourceStart = markerRange.upperBound
        let sourceEnd = line.index(before: line.endIndex)
        let source = String(line[sourceStart..<sourceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        return (alt, source)
    }

    private static func isVideoSource(_ source: String) -> Bool {
        let clean = source.split(separator: "?").first.map(String.init) ?? source
        let ext = URL(fileURLWithPath: clean).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm"].contains(ext)
    }
}

private struct RunResponseText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .font(.system(size: 13))
                .foregroundStyle(Color.appText)
                .lineSpacing(5)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(.system(size: 13))
                .foregroundStyle(Color.appText)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
    }
}

private struct RunResponseMediaView: View {
    let media: RunResponseMedia
    let basePath: String

    var body: some View {
        switch media.kind {
        case .image:
            RunResponseImage(source: media.source, alt: media.alt, basePath: basePath)
        case .video:
            RunResponseVideo(source: media.source, alt: media.alt, basePath: basePath)
        }
    }
}

private struct RunResponseImage: View {
    let source: String
    let alt: String
    let basePath: String

    var body: some View {
        if let url = resolvedURL {
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 320, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        mediaFallback
                    case .empty:
                        ProgressView()
                            .frame(width: 220, height: 120)
                    @unknown default:
                        mediaFallback
                    }
                }
                .frame(maxWidth: 520, maxHeight: 320, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            mediaFallback
        }
    }

    private var resolvedURL: URL? {
        resolveMarkdownURL(source, basePath: basePath)
    }

    private var mediaFallback: some View {
        Label(alt.isEmpty ? source : alt, systemImage: "photo")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.appSecondaryText)
            .padding(10)
            .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct RunResponseVideo: View {
    let source: String
    let alt: String
    let basePath: String

    var body: some View {
        if let url = resolveMarkdownURL(source, basePath: basePath) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: 560, minHeight: 260, maxHeight: 320, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Label(alt.isEmpty ? source : alt, systemImage: "play.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
                .padding(10)
                .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

private func resolveMarkdownURL(_ source: String, basePath: String) -> URL? {
    if source.hasPrefix("http://") || source.hasPrefix("https://") {
        return URL(string: source)
    }
    if source.hasPrefix("file://") {
        return URL(string: source)
    }
    if source.hasPrefix("/") {
        return URL(fileURLWithPath: source)
    }
    return URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent(source)
}

private struct ProjectMentionPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: String
    @Binding var moduleItem: MentionItem?
    let onSelect: (MentionItem, MentionModule?) -> Void

    private var presentation: MentionPickerPresentation {
        MentionPickerPresentation(
            tab: tab,
            search: model.mentionSearch,
            functionMentions: model.functionMentions
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text(model.tr("Skills", "Skills")).tag("Skills")
                    Text(model.tr("Files", "文件")).tag("Files")
                    Text(model.tr("Functions", "函数")).tag("Functions")
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(presentation.items) { item in
                            Button {
                                moduleItem = nil
                                onSelect(item, presentation.moduleForSelection(item))
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: presentation.iconName(for: item)).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                        Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.32), lineWidth: 1))
    }
}

private struct GenInlineBlock: View {
    @EnvironmentObject private var model: AppModel
    let block: AppModel.DocumentBlock
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.tr("Gen Markdown", "生成 Markdown"), systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                Spacer()
                Button(model.tr("Generate", "生成")) { model.generateMarkdown(from: block) }
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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(Color.primaryGreen)
            Text(model.tr("Open or create a .tron script", "打开或创建一个 .tron 脚本"))
                .font(.system(size: 24, weight: .bold))
            Text(model.tr("The editor uses a document-first markdown canvas with inline Run and Gen blocks.", "编辑器使用文档优先的 Markdown 画布，并支持行内 Run 和 Gen 块。"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NewScriptSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var scriptName = ""
    @State private var fileKind: NewFileKind = .tron
    @State private var customExtension = ""
    @FocusState private var nameFocused: Bool

    private var fileKindPresentation: NewFileKindPresentation {
        NewFileKindPresentation(kind: fileKind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.tr("New File", "新建文件")).font(.system(size: 28, weight: .bold))

            Picker(model.tr("File Type", "文件类型"), selection: $fileKind) {
                ForEach(NewFileKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField(fileKindPresentation.placeholder, text: $scriptName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createScript)

            if fileKindPresentation.requiresCustomExtension {
                TextField(model.tr("custom extension, for example: json", "自定义后缀，例如 json"), text: $customExtension)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createScript)
            } else if let badge = fileKindPresentation.extensionBadgeText(customExtension: customExtension) {
                Text(badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primaryGreen.opacity(0.10), in: Capsule())
            }

            HStack {
                Spacer()
                Button(model.tr("Cancel", "取消")) { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button(model.tr("Create", "创建")) {
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
        let fileExtension = fileKindPresentation.fileExtension(customExtension: customExtension)
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
            Text(model.tr("New Folder", "新建文件夹")).font(.system(size: 28, weight: .bold))
            TextField("assets", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createFolder)
            HStack {
                Spacer()
                Button(model.tr("Cancel", "取消")) { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button(model.tr("Create", "创建")) {
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
            Text(model.tr("Rename", "重命名")).font(.system(size: 28, weight: .bold))
            TextField(model.tr("Name", "名称"), text: $fileName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(renameFile)
            HStack {
                Spacer()
                Button(model.tr("Cancel", "取消")) { renamingFile = nil }
                    .buttonStyle(SheetActionButtonStyle())
                Button(model.tr("Rename", "重命名")) {
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
    @EnvironmentObject private var model: AppModel
    @State private var globalUserName = ""
    @State private var globalStyle = ""
    @State private var globalRules = ""
    @State private var projectFormatRules = ""
    @State private var projectConstraints = ""
    @State private var selectedSection = "Memory"
    private var presentation: ProjectSettingsPresentation {
        ProjectSettingsPresentation(
            activeProjectPath: model.activeProjectPath,
            language: model.appLanguage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(model.tr("Settings", "设置"))
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Picker("", selection: $selectedSection) {
                    Text(model.tr("Memory", "记忆")).tag("Memory")
                    Text(model.tr("Runtime", "运行时")).tag("Runtime")
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(18)
            Divider()

            ScrollView {
                if selectedSection == "Memory" {
                    memorySettings
                } else {
                    runtimeSettings
                }
            }
        }
        .onAppear {
            model.loadMemorySnapshot()
            syncDrafts()
        }
        .onChange(of: model.memorySnapshot?.effective_prompt ?? "") { _ in
            syncDrafts()
        }
    }

    private var memorySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: model.tr("Global Memory", "全局记忆"), subtitle: model.tr("Applies across every ScripTron project.", "应用于所有 ScripTron 项目。")) {
                LabeledTextField(model.tr("User name preference", "用户名称偏好"), text: $globalUserName)
                LabeledTextEditor(model.tr("Agent style preference", "Agent 风格偏好"), text: $globalStyle, height: 74)
                LabeledTextEditor(model.tr("Execution rules, one per line", "执行规则，每行一条"), text: $globalRules, height: 96)
                Button(model.tr("Save Global Memory", "保存全局记忆")) { saveGlobalMemory() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }

            SettingsSection(title: model.tr("Project Memory", "项目记忆"), subtitle: model.tr("Loaded only for this project.", "只在当前项目中加载。")) {
                LabeledTextEditor(model.tr("Format rules, one per line", "格式规则，每行一条"), text: $projectFormatRules, height: 96)
                LabeledTextEditor(model.tr("Task constraints, one per line", "任务约束，每行一条"), text: $projectConstraints, height: 96)
                Button(model.tr("Save Project Memory", "保存项目记忆")) { saveProjectMemory() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }

            if let prompt = model.memorySnapshot?.effective_prompt {
                SettingsSection(title: model.tr("Effective Prompt Context", "生效 Prompt 上下文"), subtitle: model.tr("Auditable memory summary sent to project agents.", "发送给项目 agent 的可审计记忆摘要。")) {
                    Text(prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(18)
    }

    private var runtimeSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(presentation.runtimeRows, id: \.title) { row in
                SettingsRow(title: row.title, value: row.value)
            }
            Spacer()
        }
    }

    private func syncDrafts() {
        guard let snapshot = model.memorySnapshot else { return }
        globalUserName = snapshot.global_memory.user_name_preference
        globalStyle = snapshot.global_memory.agent_style_preference
        globalRules = snapshot.global_memory.execution_rules.joined(separator: "\n")
        projectFormatRules = snapshot.project_memory.format_rules.joined(separator: "\n")
        projectConstraints = snapshot.project_memory.task_constraints.joined(separator: "\n")
    }

    private func saveGlobalMemory() {
        guard var memory = model.memorySnapshot?.global_memory else { return }
        memory.user_name_preference = globalUserName
        memory.agent_style_preference = globalStyle
        memory.execution_rules = presentation.lines(globalRules)
        model.saveGlobalMemory(memory)
    }

    private func saveProjectMemory() {
        guard var memory = model.memorySnapshot?.project_memory else { return }
        memory.format_rules = presentation.lines(projectFormatRules)
        memory.task_constraints = presentation.lines(projectConstraints)
        model.saveProjectMemory(memory)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.appSecondaryText)
            }
            content
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.65), lineWidth: 1))
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.appSecondaryText)
            TextField(title, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let height: CGFloat

    init(_ title: String, text: Binding<String>, height: CGFloat) {
        self.title = title
        self._text = text
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.appSecondaryText)
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: height)
                .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
