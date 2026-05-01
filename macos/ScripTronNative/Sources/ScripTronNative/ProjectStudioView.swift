import SwiftUI

struct ProjectStudioView: View {
    @EnvironmentObject private var model: AppModel

    private var activePanel: AppModel.ProjectPanel {
        if case .project(let panel) = model.screen { return panel }
        return .explorer
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topbar
                content
                statusbar
            }
            .background(Color.appBackground)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            Button {
                model.showWorkspace()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.primaryGreen, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading) {
                        Text("Project Alpha").font(.system(size: 17, weight: .bold))
                        Text("/SRC/SCRIPTS").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                model.selectPanel(.explorer)
            } label: {
                Label("New Script", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppModel.ProjectPanel.allCases) { panel in
                    SidebarButton(
                        title: panel.rawValue,
                        icon: icon(for: panel),
                        active: panel == activePanel
                    ) {
                        model.selectPanel(panel)
                    }
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(width: 306)
        .background(Color.sidebarBackground)
    }

    private var topbar: some View {
        HStack(spacing: 24) {
            Text("Scriptron")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primaryGreen)
            Text(model.selectedFile?.path.split(separator: "/").last.map(String.init) ?? "Main.script")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {} label: { Image(systemName: "square.and.arrow.up") }
            Button { model.selectPanel(.settings) } label: { Image(systemName: "gearshape") }
            Button("Debug") { model.selectPanel(.history) }
                .buttonStyle(.plain)
            Button {
                model.selectPanel(.history)
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 30)
        .frame(height: 68)
    }

    @ViewBuilder
    private var content: some View {
        switch activePanel {
        case .explorer:
            ExplorerPanel()
        case .toolNodes, .ragNodes:
            NodeLibraryPanel()
        case .history:
            PlaceholderPanel(title: "History", subtitle: "Run archive and live execution log will stream from Rust callbacks next.")
        case .extensions:
            PlaceholderPanel(title: "Extensions", subtitle: "Installed CLI tools are already available through the Rust bridge.")
        case .settings:
            PlaceholderPanel(title: "Settings", subtitle: "Provider configuration is exposed through get_active_config and auth APIs.")
        case .search:
            PlaceholderPanel(title: "Search", subtitle: "Native search will cover files, scripts, tools, and blackboard entries.")
        }
    }

    private var statusbar: some View {
        HStack(spacing: 22) {
            Label("RUST FFI", systemImage: "shippingbox")
            Label("UTF-8", systemImage: "doc")
            Label(model.status.uppercased(), systemImage: "cloud")
            Spacer()
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.primaryGreen)
        .padding(.horizontal, 28)
        .frame(height: 30)
        .background(.white.opacity(0.9))
    }

    private func icon(for panel: AppModel.ProjectPanel) -> String {
        switch panel {
        case .explorer: "folder"
        case .search: "magnifyingglass"
        case .toolNodes: "wrench.and.screwdriver"
        case .ragNodes: "cylinder.split.1x2"
        case .history: "clock.arrow.circlepath"
        case .extensions: "puzzlepiece.extension"
        case .settings: "gearshape"
        }
    }
}

private struct ExplorerPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Project Files")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                if model.files.isEmpty {
                    Text("No files yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.files) { file in
                        Button {
                            model.openFile(file)
                        } label: {
                            Label(file.name, systemImage: file.is_dir ? "folder" : "doc.text")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(width: 300, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 18) {
                Text(model.selectedFile?.path.split(separator: "/").last.map(String.init) ?? "Native Editor")
                    .font(.system(size: 28, weight: .bold))
                if let file = model.selectedFile {
                    ForEach(file.cells) { cell in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cell.run ? "RUN" : "NOTE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.primaryGreen)
                            Text(cell.content.isEmpty ? "Empty cell" : cell.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(18)
                        .background(cell.run ? Color.primaryGreen.opacity(0.08) : Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    Text("Select a .tron file from the Rust-backed file tree.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(34)
    }
}

private struct NodeLibraryPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration Hub")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(Color.primaryGreen)
                    Text("Node Library")
                        .font(.system(size: 42, weight: .bold))
                    Text("Reference and configure automation building blocks through the Rust registry.")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                    NodeCard(title: "Web Search", icon: "magnifyingglass", tags: ["API-V3", "LATENCY-LOW"])
                    NodeCard(title: "REST API", icon: "arrow.triangle.branch", tags: ["JSON", "AUTH-ENABLED"])
                    NodeCard(title: "Notification", icon: "envelope", tags: ["SMTP", "HTML-READY"])
                }
            }
            .padding(42)
        }
    }
}

private struct NodeCard: View {
    let title: String
    let icon: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 58, height: 58)
                .background(Color.mint.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.system(size: 22, weight: .bold))
            Text("Native SwiftUI card backed by the existing Rust registry layer.")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.surfaceSoft, in: Capsule())
                }
            }
        }
        .padding(28)
        .frame(minHeight: 280)
        .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct PlaceholderPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 42, weight: .bold))
            Text(subtitle)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

