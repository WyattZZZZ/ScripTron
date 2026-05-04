import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewProject = false
    @State private var chatExpanded = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                WorkspaceSidebar(showingNewProject: $showingNewProject)
                VStack(spacing: 0) {
                    WorkspaceTopBar()
                    workspaceContent
                }
                .background(Color.appBackground)
            }

            FloatingAgentChat(expanded: $chatExpanded)
                .environmentObject(model)
                .padding(.trailing, 28)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(isPresented: $showingNewProject)
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch model.workspacePanel {
        case .allProjects:
            ProjectsListView(archived: false)
        case .archived:
            ProjectsListView(archived: true)
        case .cliMarket:
            CLIMarketView()
        case .cliManagement:
            CLIManagementView()
        case .skillMarket:
            SkillMarketView()
        case .skillManagement:
            SkillManagementView()
        case .modelManagement:
            ModelManagementView()
        case .settings:
            WorkspaceSettingsView()
        }
    }
}

private struct WorkspaceSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingNewProject: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.primaryGreen, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scriptron")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Color.primaryGreen)
                    Text("Automation Studio")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                }
            }

            Button {
                showingNewProject = true
            } label: {
                Label(model.tr("New Project", "新建项目"), systemImage: "plus")
            }
            .buttonStyle(WorkspacePrimaryActionStyle())
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                WorkspaceNavButton(panel: .allProjects, icon: "folder")
                WorkspaceNavButton(panel: .archived, icon: "archivebox")
                Divider().padding(.vertical, 6)
                WorkspaceNavButton(panel: .cliMarket, icon: "shippingbox")
                WorkspaceNavButton(panel: .cliManagement, icon: "terminal")
                WorkspaceNavButton(panel: .skillMarket, icon: "sparkles")
                WorkspaceNavButton(panel: .skillManagement, icon: "wrench.and.screwdriver")
                WorkspaceNavButton(panel: .modelManagement, icon: "cpu")
                Divider().padding(.vertical, 6)
                WorkspaceNavButton(panel: .settings, icon: "gearshape")
            }

            Spacer()

            Text(model.workspacePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(model.status)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.primaryGreen)
        }
        .padding(28)
        .frame(width: 306)
        .background(Color.sidebarBackground)
    }
}

private struct WorkspaceNavButton: View {
    @EnvironmentObject private var model: AppModel
    let panel: AppModel.WorkspacePanel
    let icon: String

    var body: some View {
        SidebarButton(title: model.workspacePanelTitle(panel), icon: icon, active: model.workspacePanel == panel) {
            model.selectWorkspacePanel(panel)
        }
    }
}

private struct WorkspaceTopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Label(model.tr("Local Workspace", "本地工作区"), systemImage: "internaldrive")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            HoverToolbarButton(title: model.tr("Refresh", "刷新"), icon: "arrow.clockwise") {
                model.refreshFiles()
            }
        }
        .padding(.horizontal, 40)
        .frame(height: 72)
        .background(.white.opacity(0.75))
    }
}

private struct WorkspacePrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WorkspacePrimaryActionLabel(configuration: configuration)
    }
}

private struct WorkspacePrimaryActionLabel: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(
                Color.primaryGreen.opacity(configuration.isPressed ? 0.78 : (hovering ? 0.92 : 1)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(hovering ? 0.36 : 0), lineWidth: 1)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct HoverToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(hovering ? Color.primaryGreen : Color.appSecondaryText)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(
                    hovering ? Color.primaryGreen.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ProjectsListView: View {
    @EnvironmentObject private var model: AppModel
    let archived: Bool
    @State private var zipDropTargeted = false

    private var visibleProjects: [AppModel.ProjectItem] {
        model.projects.filter { $0.archived == archived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(archived ? model.tr("Archived Projects", "归档项目") : model.tr("Projects", "项目"))
                    .font(.system(size: 38, weight: .bold))
                Text(archived ? model.tr("Restore or delete archived local projects.", "恢复或删除已归档的本地项目。") : model.tr("Manage, package, open, archive, or delete local automation projects.", "管理、打包、打开、归档或删除本地自动化项目。"))
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ProjectTableHeader(archived: archived)
                ForEach(visibleProjects) { project in
                    ProjectRow(project: project, archived: archived)
                    Divider()
                }
                if visibleProjects.isEmpty {
                    EmptyListView(title: archived ? model.tr("No archived projects", "暂无归档项目") : model.tr("No projects", "暂无项目"), subtitle: model.tr("Create a project from the sidebar.", "从侧边栏创建一个项目。"))
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(zipDropTargeted ? Color.primaryGreen : Color.hairline.opacity(0.7), style: StrokeStyle(lineWidth: zipDropTargeted ? 2 : 1, dash: zipDropTargeted ? [7, 5] : []))
            )
            .shadow(color: zipDropTargeted ? Color.primaryGreen.opacity(0.14) : Color.clear, radius: 18, y: 10)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $zipDropTargeted) { providers in
                guard !archived else { return false }
                return model.importProjectZipDrops(providers)
            }
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProjectTableHeader: View {
    @EnvironmentObject private var model: AppModel
    let archived: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(model.tr("Name", "名称")).frame(maxWidth: .infinity, alignment: .leading)
            Text(model.tr("Status", "状态")).frame(width: 82, alignment: .leading)
            Text(model.tr("Actions", "操作")).frame(width: archived ? 218 : 342, alignment: .leading)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(Color.surfaceSoft)
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var model: AppModel
    let project: AppModel.ProjectItem
    let archived: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: project.packaged ? "shippingbox.fill" : "folder")
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.system(size: 14, weight: .semibold))
                Text(project.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(project.status.uppercased())
                .font(.system(size: 10, weight: .bold))
                .frame(width: 82, alignment: .leading)
                .foregroundStyle(Color.primaryGreen)

            HStack(spacing: 8) {
                WorkspaceActionButton(model.tr("Open", "打开"), icon: "arrow.up.right.square", disabled: archived) { model.openProject(project) }
                WorkspaceActionButton(model.tr("Package", "打包"), icon: "shippingbox", disabled: archived) { model.packageProject(project) }
                if archived {
                    WorkspaceActionButton(model.tr("Restore", "恢复"), icon: "arrow.uturn.backward") { model.restoreProject(project) }
                } else {
                    WorkspaceActionButton(model.tr("Archive", "归档"), icon: "archivebox") { model.archiveProject(project) }
                }
                WorkspaceActionButton(model.tr("Delete", "删除"), icon: "trash", role: .destructive) { model.deleteProject(project) }
            }
            .frame(width: archived ? 218 : 342, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .contentShape(Rectangle())
        .background(hovering ? Color.primaryGreen.opacity(0.045) : Color.clear)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct WorkspaceActionButton: View {
    let title: String
    let icon: String
    let role: ButtonRole?
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, icon: String, role: ButtonRole? = nil, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 9)
                .frame(minWidth: minWidth, minHeight: 30)
                .contentShape(Capsule())
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 && !disabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        if disabled { return Color.appSecondaryText.opacity(0.45) }
        if role == .destructive { return hovering ? .white : .red }
        return hovering ? Color.primaryGreen : Color.appSecondaryText
    }

    private var background: Color {
        if disabled { return Color.clear }
        if role == .destructive { return hovering ? .red.opacity(0.82) : .red.opacity(0.08) }
        return hovering ? Color.primaryGreen.opacity(0.10) : Color.clear
    }

    private var minWidth: CGFloat {
        switch title {
        case "Package", "Archive", "Restore", "打包", "归档", "恢复": 82
        case "Delete", "删除": 70
        default: 62
        }
    }
}

private struct CLIMarketView: View {
    @EnvironmentObject private var model: AppModel

    private var items: [TronhubEntry] { model.tronhubClis }

    var body: some View {
        ManagementPage(title: model.tr("CLI Market", "CLI 市场"), subtitle: model.tr("Install tool and software CLIs from TronHub. Model providers are managed separately in Model Management.", "从 TronHub 安装工具和软件 CLI。模型 Provider 在模型管理中单独管理。")) {
            HStack {
                ManagementPill(model.tr("Remote", "远程仓库"), value: "ScripTron_Extension")
                ManagementPill(model.tr("Available", "可用"), value: "\(items.count)")
                Spacer()
                Button { model.syncTronhub() } label: { Label(model.tr("Sync TronHub", "同步 TronHub"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    TronhubCard(entry: item) {
                        model.installTronhub(item)
                    }
                }
            }
        }
        .onAppear { model.loadWorkspaceManagementData() }
    }
}

private struct CLIManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingInstaller = false

    private var toolCLIs: [CLIManifest] {
        model.cliRegistry.filter { $0.kind != "model" }
    }

    var body: some View {
        ManagementPage(title: model.tr("CLI Management", "CLI 管理"), subtitle: model.tr("Everything here is loaded from the workspace .register folder.", "这里的所有内容都从工作区 .register 文件夹加载。")) {
            HStack {
                ManagementPill(model.tr("Registry", "注册表"), value: model.tr("\(toolCLIs.count) installed", "已安装 \(toolCLIs.count) 个"))
                ManagementPill("Path", value: "\(model.workspacePath)/.register")
                Spacer()
                Button { model.refreshRegistry() } label: { Label(model.tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }
                    .buttonStyle(ManagementButtonStyle())
                Button { showingInstaller.toggle() } label: { Label(model.tr("Install JSON", "安装 JSON"), systemImage: "plus") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }

            if showingInstaller {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.tr("Manifest JSON", "Manifest JSON")).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appSecondaryText)
                    TextEditor(text: $model.installManifestDraft)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 220)
                        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
                    HStack {
                        Spacer()
                        Button(model.tr("Cancel", "取消")) { showingInstaller = false }
                            .buttonStyle(ManagementButtonStyle())
                        Button(model.tr("Install", "安装")) {
                            model.installCLIManifest(model.installManifestDraft)
                            showingInstaller = false
                        }
                        .buttonStyle(ManagementButtonStyle(primary: true))
                    }
                }
                .padding(16)
                .background(Color.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            RegistryListView(items: toolCLIs, activeModel: model.activeConfig?.model, onRemove: model.removeCLI, onActivateModel: model.activateModelCLI)
        }
        .onAppear { model.loadWorkspaceManagementData() }
    }
}

private struct SkillMarketView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ManagementPage(title: model.tr("Skill Market", "Skill 市场"), subtitle: model.tr("Install agent skills from TronHub into the workspace .skills folder.", "从 TronHub 安装 agent skills 到工作区 .skills 文件夹。")) {
            HStack {
                ManagementPill(model.tr("Remote", "远程仓库"), value: "ScripTron_Extension")
                ManagementPill(model.tr("Available", "可用"), value: "\(model.tronhubSkills.count)")
                Spacer()
                Button { model.syncTronhub() } label: { Label(model.tr("Sync TronHub", "同步 TronHub"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(model.tronhubSkills) { item in
                    TronhubCard(entry: item) {
                        model.installTronhub(item)
                    }
                }
            }
        }
        .onAppear { model.loadWorkspaceManagementData() }
    }
}

private struct SkillManagementView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ManagementPage(title: model.tr("Skill Management", "Skill 管理"), subtitle: model.tr("Installed skills live under the workspace .skills folder and can be used by Troner Agent.", "已安装的 skills 位于工作区 .skills 文件夹，可被 Troner Agent 使用。")) {
            HStack {
                ManagementPill(model.tr("Installed", "已安装"), value: "\(model.installedSkills.count)")
                ManagementPill("Path", value: "\(model.workspacePath)/.skills")
                Spacer()
                Button { model.refreshSkills() } label: { Label(model.tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }
                    .buttonStyle(ManagementButtonStyle())
            }
            if model.installedSkills.isEmpty {
                EmptyListView(title: model.tr("No skills installed", "暂无已安装 Skill"), subtitle: model.tr("Install a skill from Skill Market.", "从 Skill 市场安装一个 skill。"))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.installedSkills) { skill in
                        SkillRow(skill: skill) { model.removeSkill(skill) }
                    }
                }
            }
        }
        .onAppear { model.loadWorkspaceManagementData() }
    }
}

private struct ModelManagementView: View {
    @EnvironmentObject private var model: AppModel

    private var connectedCount: Int {
        model.providerStatuses.filter(\.connected).count
    }

    private var installedCliModels: [CLIManifest] {
        model.cliRegistry.filter { $0.kind == "model" }
    }

    var body: some View {
        ManagementPage(title: model.tr("Model Management", "模型管理"), subtitle: model.tr("Connect API providers or install CLI model packages from TronHub.", "连接 API Provider 或从 TronHub 安装 CLI 模型插件。")) {
            HStack {
                ManagementPill(model.tr("Provider", "Provider"), value: model.activeConfig?.provider ?? model.tr("Not loaded", "未加载"))
                ManagementPill(model.tr("Active Model", "当前模型"), value: model.activeConfig?.model ?? model.tr("Not selected", "未选择"))
                ManagementPill(model.tr("Connected", "已连接"), value: "\(connectedCount)/\(model.providerStatuses.count)")
                Spacer()
                Button { model.syncTronhub() } label: { Label(model.tr("Sync TronHub", "同步 TronHub"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
                Button { model.loadWorkspaceManagementData() } label: { Label(model.tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }
                    .buttonStyle(ManagementButtonStyle())
            }

            // ── API Providers ─────────────────────────────────────────────────
            Text(model.tr("API Providers", "API Provider"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.appSecondaryText)

            if model.providerStatuses.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(model.providerStatuses) { status in
                        ProviderCard(status: status)
                    }
                }
            }

            // ── Installed CLI Models ──────────────────────────────────────────
            if !installedCliModels.isEmpty {
                Text(model.tr("Installed CLI Models", "已安装的 CLI 模型"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appSecondaryText)
                VStack(spacing: 10) {
                    ForEach(installedCliModels) { manifest in
                        InstalledCliModelRow(manifest: manifest)
                    }
                }
            }

            // ── TronHub CLI Models Market ─────────────────────────────────────
            if !model.tronhubModels.isEmpty {
                Text(model.tr("CLI Model Plugins", "CLI 模型插件市场"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appSecondaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(model.tronhubModels) { item in
                        TronhubCard(entry: item) { model.installTronhub(item) }
                    }
                }
            }
        }
        .onAppear { model.loadWorkspaceManagementData() }
        .sheet(isPresented: Binding(
            get: { model.pluginLoginOutput != nil },
            set: { if !$0 { model.pluginLoginOutput = nil } }
        )) {
            PluginLoginOutputSheet()
        }
    }
}

private struct InstalledCliModelRow: View {
    @EnvironmentObject private var model: AppModel
    let manifest: CLIManifest
    @State private var hovering = false

    private var isActive: Bool {
        model.activeConfig?.model == manifest.name
    }

    private var supportsLogin: Bool {
        manifest.args_schema.contains { $0.name == "action" }
    }

    private var isLoggingIn: Bool {
        model.pluginLoginRunning == manifest.name
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 42, height: 42)
                .background(Color.primaryGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(manifest.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.appText)
                    if isActive {
                        Text(model.tr("Active", "当前"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primaryGreen, in: Capsule())
                    }
                }
                Text(manifest.description).font(.system(size: 13)).foregroundStyle(Color.appSecondaryText).lineLimit(2)
                Text(manifest.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.appSecondaryText.opacity(0.75)).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    model.runPluginInstallScript(kind: "model", name: manifest.name)
                } label: {
                    if isLoggingIn {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(model.tr("Working…", "执行中…"))
                        }
                    } else {
                        Label(model.tr("Install Deps", "安装依赖"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(ManagementButtonStyle())
                .disabled(isLoggingIn)
                if supportsLogin {
                    Button {
                        model.runPluginLogin(manifest.name)
                    } label: {
                        Label(model.tr("Login", "登录"), systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(ManagementButtonStyle())
                    .disabled(isLoggingIn)
                }
                Button(model.tr("Set Active", "设为当前")) {
                    model.activateModelCLI(manifest)
                }
                .buttonStyle(ManagementButtonStyle(primary: !isActive))
                .disabled(isActive)
                Button {
                    model.removeCLI(manifest)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(ManagementButtonStyle(role: .destructive))
            }
        }
        .padding(16)
        .background(hovering ? Color.primaryGreen.opacity(0.07) : .white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.primaryGreen.opacity(0.5) : Color.hairline.opacity(0.7), lineWidth: isActive ? 1.5 : 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PluginLoginOutputSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.primaryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tr("Login Output", "登录结果"))
                        .font(.system(size: 16, weight: .bold))
                    if let pair = model.pluginLoginOutput {
                        Text(pair.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appSecondaryText)
            }
            ScrollView {
                Text(model.pluginLoginOutput?.output ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 200, maxHeight: 400)
            .background(Color.surfaceSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Spacer()
                Button(model.tr("Close", "关闭")) { dismiss() }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 320)
    }
}

private struct ProviderCard: View {
    @EnvironmentObject private var model: AppModel
    let status: ProviderStatus

    @State private var selectedModel: String = ""
    @State private var showingApiKeyInput = false
    @State private var apiKeyDraft = ""

    private var isActive: Bool {
        model.activeConfig?.provider == status.provider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 10) {
                Image(systemName: providerIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(providerColor)
                    .frame(width: 44, height: 44)
                    .background(providerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.display_name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.appText)
                    Text(status.provider)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appSecondaryText.opacity(0.7))
                }
                Spacer()
                // Active badge
                if isActive {
                    Text(model.tr("Active", "当前"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primaryGreen, in: Capsule())
                }
                // Connection badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.connected ? Color.primaryGreen : Color.appSecondaryText.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(status.connected ? model.tr("Connected", "已连接") : model.tr("Not connected", "未连接"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.connected ? Color.primaryGreen : Color.appSecondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (status.connected ? Color.primaryGreen : Color.appSecondaryText).opacity(0.09),
                    in: Capsule()
                )
            }

            // Model picker
            if status.connected || isActive {
                HStack(spacing: 8) {
                    Text(model.tr("Model", "模型"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appSecondaryText)
                    Picker("", selection: $selectedModel) {
                        ForEach(status.available_models, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // API key input (inline)
            if showingApiKeyInput {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.tr("API Key", "API Key"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                    SecureField("sk-...", text: $apiKeyDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hairline, lineWidth: 1))
                    HStack {
                        Button(model.tr("Cancel", "取消")) {
                            showingApiKeyInput = false
                            apiKeyDraft = ""
                        }
                        .buttonStyle(ManagementButtonStyle())
                        Button(model.tr("Save", "保存")) {
                            model.storeApiKey(apiKeyDraft, for: status.provider)
                            showingApiKeyInput = false
                            apiKeyDraft = ""
                        }
                        .buttonStyle(ManagementButtonStyle(primary: true))
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 8) {
                if status.connected {
                    Button(model.tr("Set Active", "设为当前")) {
                        model.setActiveConfig(provider: status.provider, model: selectedModel)
                    }
                    .buttonStyle(ManagementButtonStyle(primary: !isActive))
                    .disabled(isActive && model.activeConfig?.model == selectedModel)

                    Button(model.tr("Disconnect", "断开")) {
                        model.disconnectProvider(status.provider)
                    }
                    .buttonStyle(ManagementButtonStyle(role: .destructive))
                } else {
                    Button(model.tr("Connect", "连接")) {
                        showingApiKeyInput.toggle()
                    }
                    .buttonStyle(ManagementButtonStyle(primary: true))
                }
            }
        }
        .padding(18)
        .frame(minHeight: 180, alignment: .topLeading)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.primaryGreen.opacity(0.5) : Color.hairline.opacity(0.7), lineWidth: isActive ? 1.5 : 1)
        )
        .onAppear {
            selectedModel = (isActive ? model.activeConfig?.model : nil) ?? status.default_model
        }
        .onChange(of: model.activeConfig?.model) { newModel in
            if isActive, let m = newModel { selectedModel = m }
        }
    }

    private var providerIcon: String {
        switch status.provider {
        case "anthropic": return "brain"
        case "gemini": return "sparkles"
        case "openai": return "circle.hexagongrid"
        case "deepseek": return "waveform"
        case "openrouter": return "arrow.triangle.branch"
        default: return "cpu"
        }
    }

    private var providerColor: Color {
        switch status.provider {
        case "anthropic": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "gemini": return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "openai": return Color(red: 0.07, green: 0.73, blue: 0.50)
        case "deepseek": return Color(red: 0.45, green: 0.3, blue: 0.95)
        case "openrouter": return Color(red: 0.55, green: 0.35, blue: 0.75)
        default: return Color.primaryGreen
        }
    }
}

private struct WorkspaceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var language = "en"
    @State private var globalUserName = ""
    @State private var globalStyle = ""
    @State private var globalRules = ""
    @State private var confirmFactoryReset = false

    var body: some View {
        ManagementPage(title: model.tr("Settings", "设置"), subtitle: model.tr("Configure app-wide behavior and Troner global memory.", "配置整个应用的行为和 Troner 全局记忆。")) {
            WorkspaceSettingsSection(title: model.tr("Application", "应用"), subtitle: model.tr("Preferences that apply to the whole app.", "应用于整个软件的偏好设置。")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.tr("Language", "语言"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appSecondaryText)
                    Picker("", selection: $language) {
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .onChange(of: language) { model.setAppLanguage($0) }
                }
            }

            WorkspaceSettingsSection(title: model.tr("Global Memory", "全局记忆"), subtitle: model.tr("This memory is included in Troner prompts across all projects.", "这部分记忆会注入所有项目中的 Troner prompt。")) {
                WorkspaceLabeledTextField(model.tr("User name preference", "用户名称偏好"), text: $globalUserName)
                WorkspaceLabeledTextEditor(model.tr("Agent style preference", "Agent 风格偏好"), text: $globalStyle, height: 78)
                WorkspaceLabeledTextEditor(model.tr("Execution rules, one per line", "执行规则，每行一条"), text: $globalRules, height: 106)
                HStack {
                    Button(model.tr("Save Global Memory", "保存全局记忆")) { saveGlobalMemory() }
                        .buttonStyle(ManagementButtonStyle(primary: true))
                    Button { syncDrafts() } label: { Label(model.tr("Reload", "重新载入"), systemImage: "arrow.clockwise") }
                        .buttonStyle(ManagementButtonStyle())
                }
            }

            WorkspaceSettingsSection(title: model.tr("Factory Reset", "恢复出厂设置"), subtitle: model.tr("Resets app configuration, global memory, installed CLIs, skills, and TronHub cache. Project folders are preserved.", "重置应用配置、全局记忆、已安装 CLI、skills 和 TronHub 缓存。项目文件夹会保留。")) {
                Button(role: .destructive) {
                    confirmFactoryReset = true
                } label: {
                    Label(model.tr("Restore Factory Settings", "恢复出厂设置"), systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(ManagementButtonStyle())
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            language = model.appLanguage
            model.loadMemorySnapshot()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                syncDrafts()
            }
        }
        .alert(model.tr("Restore factory settings?", "确认恢复出厂设置？"), isPresented: $confirmFactoryReset) {
            Button(model.tr("Cancel", "取消"), role: .cancel) {}
            Button(model.tr("Restore", "恢复"), role: .destructive) {
                model.factoryResetAppState()
                language = "en"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    syncDrafts()
                }
            }
        } message: {
            Text(model.tr("This resets app configuration, global memory, installed CLIs, skills, and TronHub cache. Your project folders will not be deleted.", "这会重置应用配置、全局记忆、已安装 CLI、skills 和 TronHub 缓存。你的项目文件夹不会被删除。"))
        }
    }

    private func syncDrafts() {
        guard let memory = model.memorySnapshot?.global_memory else { return }
        globalUserName = memory.user_name_preference
        globalStyle = memory.agent_style_preference
        globalRules = memory.execution_rules.joined(separator: "\n")
    }

    private func saveGlobalMemory() {
        guard var memory = model.memorySnapshot?.global_memory else { return }
        memory.user_name_preference = globalUserName
        memory.agent_style_preference = globalStyle
        memory.execution_rules = globalRules
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        model.saveGlobalMemory(memory)
    }
}

private struct WorkspaceSettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.appText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
            }
            content
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.65), lineWidth: 1))
    }
}

private struct WorkspaceLabeledTextField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appSecondaryText)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)
        }
    }
}

private struct WorkspaceLabeledTextEditor: View {
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
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appSecondaryText)
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: 620)
                .frame(height: height)
                .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct ManagementPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.appText)
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(42)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RegistryListView: View {
    let items: [CLIManifest]
    let activeModel: String?
    let onRemove: (CLIManifest) -> Void
    let onActivateModel: (CLIManifest) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                RegistryRow(item: item, active: activeModel == item.name, onRemove: { onRemove(item) }, onActivateModel: { onActivateModel(item) })
            }
        }
    }
}

private struct RegistryRow: View {
    @EnvironmentObject private var model: AppModel
    let item: CLIManifest
    let active: Bool
    let onRemove: () -> Void
    let onActivateModel: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primaryGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.primaryGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.appText)
                        KindBadge(kind: item.kind)
                        if active { KindBadge(kind: "active") }
                    }
                    Text(item.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appSecondaryText.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer()

                if item.kind == "model" {
                    Button(active ? model.tr("Active", "当前") : model.tr("Use Model", "使用模型")) { onActivateModel() }
                        .buttonStyle(ManagementButtonStyle(primary: !active))
                        .disabled(active)
                }
                Button(role: .destructive) { onRemove() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(hovering ? .red : Color.appSecondaryText)
            }

            if !item.args_schema.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.args_schema) { arg in
                        Text("\(arg.name):\(arg.type)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.surfaceSoft, in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(hovering ? Color.primaryGreen.opacity(0.07) : .white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(active ? Color.primaryGreen.opacity(0.35) : Color.hairline.opacity(0.7), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var icon: String {
        switch item.kind {
        case "model": return "cpu"
        case "software": return "app.connected.to.app.below.fill"
        default: return "terminal"
        }
    }
}

private struct TronhubCard: View {
    @EnvironmentObject private var model: AppModel
    let entry: TronhubEntry
    let install: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primaryGreen)
                    .frame(width: 44, height: 44)
                    .background(Color.primaryGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                KindBadge(kind: entry.kind)
            }
            Text(entry.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color.appText)
            Text(entry.description)
                .font(.system(size: 13))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.source_path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.appSecondaryText.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 6)
            Button(entry.installed ? model.tr("Installed", "已安装") : model.tr("Install", "安装")) { install() }
                .buttonStyle(ManagementButtonStyle(primary: !entry.installed))
                .disabled(entry.installed)
        }
        .padding(18)
        .frame(minHeight: 220, alignment: .topLeading)
        .background(hovering ? Color.primaryGreen.opacity(0.07) : .white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var icon: String {
        switch entry.kind {
        case "skill": return "sparkles"
        case "model": return "cpu"
        default: return "terminal"
        }
    }
}

private struct SkillRow: View {
    let skill: SkillEntry
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 42, height: 42)
                .background(Color.primaryGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(skill.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.appText)
                Text(skill.description).font(.system(size: 13)).foregroundStyle(Color.appSecondaryText)
                Text(skill.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.appSecondaryText.opacity(0.75)).lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(hovering ? .red : Color.appSecondaryText)
        }
        .padding(16)
        .background(hovering ? Color.primaryGreen.opacity(0.07) : .white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ManagementPill: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appSecondaryText)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appText).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
    }
}

private struct KindBadge: View {
    let kind: String

    var body: some View {
        Text(kind.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(kind == "active" ? .white : Color.primaryGreen)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(kind == "active" ? Color.primaryGreen : Color.primaryGreen.opacity(0.10), in: Capsule())
    }
}

private struct ManagementButtonStyle: ButtonStyle {
    var primary = false
    var role: ButtonRole? = nil

    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = role == .destructive
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isDestructive ? Color.red : (primary ? .white : Color.primaryGreen))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                isDestructive
                    ? Color.red.opacity(configuration.isPressed ? 0.16 : 0.10)
                    : (primary ? Color.primaryGreen.opacity(configuration.isPressed ? 0.82 : 1) : Color.primaryGreen.opacity(configuration.isPressed ? 0.16 : 0.10)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

private struct FloatingAgentChat: View {
    @EnvironmentObject private var model: AppModel
    @Binding var expanded: Bool
    @State private var draft = ""
    @State private var mentionTab = "Tools"
    @State private var tronModuleItem: MentionItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.tr("Agent", "Agent"), systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "message")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            if expanded {
                VStack(spacing: 0) {
                    Divider().opacity(0.35)
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(model.chatMessages) { message in
                                ChatBubble(message: message)
                            }
                        }
                        .padding(12)
                    }
                    .frame(height: 250)
                    if mentionQuery != nil {
                        MentionPicker(
                            tab: $mentionTab,
                            moduleItem: $tronModuleItem,
                            onSelect: insertMention
                        )
                        .environmentObject(model)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                    HStack(spacing: 8) {
                        TextField(model.tr("Ask the workspace agent...", "询问工作区 Agent..."), text: $draft)
                            .textFieldStyle(.plain)
                            .focused($inputFocused)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(.white.opacity(0.68), in: Capsule())
                            .overlay(Capsule().stroke(Color.hairline.opacity(0.45), lineWidth: 1))
                            .onSubmit(send)
                            .onChange(of: draft) { _ in updateMentionSearch() }
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.primaryGreen)
                    }
                    .padding(12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: expanded ? 360 : 160)
        .acrylicPanel(cornerRadius: 22)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: expanded)
        .onAppear(perform: focusInputIfNeeded)
        .onChange(of: expanded) { _ in focusInputIfNeeded() }
    }

    private func send() {
        model.sendAgentMessage(draft)
        draft = ""
        tronModuleItem = nil
        focusInputIfNeeded()
    }

    private var mentionQuery: String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        let suffix = String(draft[draft.index(after: at)...])
        if suffix.contains(where: { $0.isWhitespace }) { return nil }
        return suffix
    }

    private func updateMentionSearch() {
        guard let mentionQuery else {
            tronModuleItem = nil
            return
        }
        model.searchMentions(query: mentionQuery)
    }

    private func insertMention(_ item: MentionItem, _ module: MentionModule?) {
        model.selectMention(item, module: module)
        let token: String
        if let module {
            token = "@\(item.label)#\(module.name)"
        } else {
            token = "@\(item.label)"
        }
        if let at = draft.lastIndex(of: "@") {
            draft.replaceSubrange(at..<draft.endIndex, with: token + " ")
        } else {
            draft += token + " "
        }
        tronModuleItem = nil
        inputFocused = true
    }

    private func focusInputIfNeeded() {
        guard expanded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            inputFocused = true
        }
    }
}

private struct MentionPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: String
    @Binding var moduleItem: MentionItem?
    let onSelect: (MentionItem, MentionModule?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                Picker("", selection: $tab) {
                    Text(model.tr("Skills", "Skills")).tag("Tools")
                    Text(model.tr("Files", "文件")).tag("Files")
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            Button {
                                moduleItem = nil
                                onSelect(item, nil)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: icon(for: item))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                        Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if !item.installed {
                                        Text(model.tr("CLOUD", "云端")).font(.system(size: 8, weight: .bold)).foregroundStyle(Color.primaryGreen)
                                    }
                                }
                                .padding(8)
                                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.32), lineWidth: 1))
        }
    }

    private var items: [MentionItem] {
        if tab == "Tools" {
            return model.mentionSearch.tools + model.mentionSearch.cloud_suggestions
        }
        return model.mentionSearch.files
    }

    private func icon(for item: MentionItem) -> String {
        switch item.kind {
        case "tool", "software", "model": return "terminal"
        case "tron": return "doc.richtext"
        case "cloud": return "icloud"
        default: return "doc"
        }
    }
}

private struct ChatBubble: View {
    @EnvironmentObject private var model: AppModel
    let message: AppModel.ChatMessage

    private var isUser: Bool { message.role == "user" }
    private var roleLabel: String {
        switch message.role {
        case "user": model.tr("USER", "用户")
        case "system": model.tr("SYSTEM", "系统")
        default: model.tr("AGENT", "AGENT")
        }
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(roleLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.28), lineWidth: 1))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

private struct NewProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var projectName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.tr("New Project", "新建项目")).font(.system(size: 28, weight: .bold))
            TextField("customer-onboarding", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createProject)
            HStack {
                Spacer()
                Button(model.tr("Cancel", "取消")) { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button(model.tr("Create", "创建")) {
                    createProject()
                }
                .buttonStyle(SheetActionButtonStyle(primary: true))
            }
        }
        .padding(28)
        .frame(width: 440)
        .onAppear {
            DispatchQueue.main.async {
                nameFocused = true
            }
        }
    }

    private func createProject() {
        model.createProject(named: projectName)
        isPresented = false
    }
}

private struct EmptyListView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(Color.primaryGreen)
            Text(title).font(.system(size: 20, weight: .bold))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
