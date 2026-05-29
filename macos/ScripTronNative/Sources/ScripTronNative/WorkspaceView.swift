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

    private var presentation: WorkspaceProjectListPresentation {
        WorkspaceProjectListPresentation(
            archived: archived,
            projects: model.projects,
            language: model.appLanguage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.title)
                    .font(.system(size: 38, weight: .bold))
                Text(presentation.subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ProjectTableHeader(archived: archived)
                ForEach(presentation.visibleProjects) { project in
                    ProjectRow(project: project, archived: archived)
                    Divider()
                }
                if presentation.visibleProjects.isEmpty {
                    EmptyListView(title: presentation.emptyTitle, subtitle: presentation.emptySubtitle)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(zipDropTargeted ? Color.primaryGreen : Color.hairline.opacity(0.7), style: StrokeStyle(lineWidth: zipDropTargeted ? 2 : 1, dash: zipDropTargeted ? [7, 5] : []))
            )
            .shadow(color: zipDropTargeted ? Color.primaryGreen.opacity(0.14) : Color.clear, radius: 18, y: 10)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $zipDropTargeted) { providers in
                guard presentation.allowsZipDrop else { return false }
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

    private var presentation: ProjectRowPresentation {
        ProjectRowPresentation(project: project, archived: archived)
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: presentation.iconName)
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.system(size: 14, weight: .semibold))
                Text(project.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(presentation.statusText)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 82, alignment: .leading)
                .foregroundStyle(Color.primaryGreen)

            HStack(spacing: 8) {
                WorkspaceActionButton(model.tr("Open", "打开"), icon: "arrow.up.right.square", disabled: presentation.disablesOpenAndPackage) { model.openProject(project) }
                WorkspaceActionButton(model.tr("Package", "打包"), icon: "shippingbox", disabled: presentation.disablesOpenAndPackage) { model.packageProject(project) }
                if archived {
                    WorkspaceActionButton(model.tr("Restore", "恢复"), icon: "arrow.uturn.backward") { model.restoreProject(project) }
                } else {
                    WorkspaceActionButton(model.tr("Archive", "归档"), icon: "archivebox") { model.archiveProject(project) }
                }
                WorkspaceActionButton(model.tr("Delete", "删除"), icon: "trash", role: .destructive) { model.deleteProject(project) }
            }
            .frame(width: CGFloat(presentation.actionsWidth), alignment: .leading)
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
    @State private var source: ExtensionCatalogSource = .hermesHub
    @State private var category = "All"
    @State private var query = ""
    @State private var page = 1

    private var catalog: ExtensionCatalogState {
        ExtensionCatalogState(items: model.cliMarketCatalogItems)
    }

    private var visibleItems: [ExtensionCatalogItem] {
        catalog.page(source: source, category: category, query: query, page: page)
    }

    private var totalItems: Int {
        catalog.filtered(source: source, category: category, query: query).count
    }

    private var totalPages: Int {
        catalog.pageCount(source: source, category: category, query: query)
    }

    var body: some View {
        ManagementPage(title: model.tr("CLI Market", "CLI 市场"), subtitle: model.tr("Browse Hermes-managed CLI wrappers and TronHub workspace CLIs.", "浏览 Hermes 管理的 CLI wrapper 与 TronHub 工作区 CLI。")) {
            HStack {
                ManagementPill(model.tr("Source", "来源"), value: source.rawValue)
                ManagementPill(model.tr("Available", "可用"), value: "\(totalItems)")
                Spacer()
                Button { model.syncTronhub() } label: { Label(model.tr("Sync TronHub", "同步 TronHub"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }
            ExtensionCatalogControls(
                source: $source,
                category: $category,
                query: $query,
                categories: ["All"] + catalog.categories
            )
            ExtensionCatalogPager(page: $page, totalPages: totalPages)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(visibleItems) { item in
                    ExtensionCatalogCard(item: item) {
                        handleCatalogAction(item)
                    }
                }
            }
        }
        .onAppear { model.ensureWorkspaceManagementDataLoaded() }
        .onChange(of: source) { _ in page = 1 }
        .onChange(of: category) { _ in page = 1 }
        .onChange(of: query) { _ in page = 1 }
    }

    private func handleCatalogAction(_ item: ExtensionCatalogItem) {
        if item.source == .tronHub,
           let entry = model.tronhubClis.first(where: { $0.name == item.name }) {
            model.installTronhub(entry)
        } else {
            model.status = model.tr("Hermes CLI install will run through the gateway.", "Hermes CLI 安装将通过网关执行。")
        }
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
        .onAppear { model.ensureWorkspaceManagementDataLoaded() }
    }
}

private struct SkillMarketView: View {
    @EnvironmentObject private var model: AppModel
    @State private var source: ExtensionCatalogSource = .hermesHub
    @State private var category = "All"
    @State private var query = ""
    @State private var page = 1

    private var catalog: ExtensionCatalogState {
        ExtensionCatalogState(items: model.skillMarketCatalogItems)
    }

    private var visibleItems: [ExtensionCatalogItem] {
        catalog.page(source: source, category: category, query: query, page: page)
    }

    private var totalItems: Int {
        catalog.filtered(source: source, category: category, query: query).count
    }

    private var totalPages: Int {
        catalog.pageCount(source: source, category: category, query: query)
    }

    var body: some View {
        ManagementPage(title: model.tr("Skill Market", "Skill 市场"), subtitle: model.tr("Browse Hermes Official / Hub skills and TronHub workspace extensions.", "浏览 Hermes Official / Hub skills 与 TronHub 工作区扩展。")) {
            HStack {
                ManagementPill(model.tr("Source", "来源"), value: source.rawValue)
                ManagementPill(model.tr("Available", "可用"), value: "\(totalItems)")
                Spacer()
                Button { model.syncTronhub() } label: { Label(model.tr("Sync TronHub", "同步 TronHub"), systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(ManagementButtonStyle(primary: true))
            }
            ExtensionCatalogControls(
                source: $source,
                category: $category,
                query: $query,
                categories: ["All"] + catalog.categories
            )
            ExtensionCatalogPager(page: $page, totalPages: totalPages)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(visibleItems) { item in
                    ExtensionCatalogCard(item: item) {
                        handleCatalogAction(item)
                    }
                }
            }
        }
        .onAppear { model.ensureWorkspaceManagementDataLoaded() }
        .onChange(of: source) { _ in page = 1 }
        .onChange(of: category) { _ in page = 1 }
        .onChange(of: query) { _ in page = 1 }
    }

    private func handleCatalogAction(_ item: ExtensionCatalogItem) {
        model.installCatalogItem(item)
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
        .onAppear { model.ensureWorkspaceManagementDataLoaded() }
    }
}

private struct ExtensionCatalogControls: View {
    @Binding var source: ExtensionCatalogSource
    @Binding var category: String
    @Binding var query: String
    let categories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search extensions", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
                Picker("", selection: $source) {
                    ForEach(ExtensionCatalogSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { item in
                        Button(item) { category = item }
                            .buttonStyle(ManagementButtonStyle(primary: category == item))
                    }
                }
            }
        }
    }
}

private struct ExtensionCatalogCard: View {
    @EnvironmentObject private var model: AppModel
    let item: ExtensionCatalogItem
    let action: () -> Void

    private var presentation: ExtensionCatalogCardPresentation {
        ExtensionCatalogCardPresentation(item: item, language: model.appLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primaryGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.primaryGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.appText)
                    Text(item.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(2)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(presentation.visibleBadges, id: \.self) { badge in
                    CatalogBadge(badge)
                }
            }
            Button(presentation.actionTitle) { action() }
                .buttonStyle(ManagementButtonStyle(primary: true))
        }
        .padding(16)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
    }
}

private struct ExtensionCatalogPager: View {
    @Binding var page: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Button { page = max(1, page - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ManagementButtonStyle())
            .disabled(page <= 1)
            Text("\(page) / \(max(1, totalPages))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.appSecondaryText)
                .frame(minWidth: 52)
            Button { page = min(totalPages, page + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(ManagementButtonStyle())
            .disabled(page >= totalPages)
        }
    }
}

private struct CatalogBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.primaryGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primaryGreen.opacity(0.08), in: Capsule())
    }
}

struct ModelManagementView: View {
    @EnvironmentObject private var model: AppModel

    private var gatewayStatus: ProviderStatus? {
        model.providerStatuses.first
    }

    var body: some View {
        ManagementPage(title: model.tr("Model Management", "模型管理"), subtitle: model.tr("Hermes Agent manages model login, selection, tools, and skills for ScripTron.", "Hermes Agent 统一管理模型登录、选择、工具和 skill。")) {
            HStack {
                ManagementPill(model.tr("Gateway", "网关"), value: gatewayStatus?.display_name ?? "Hermes")
                ManagementPill(model.tr("Auth", "认证"), value: gatewayStatus?.auth_method ?? model.tr("Hermes managed", "Hermes 管理"))
                ManagementPill(model.tr("Active Model", "当前模型"), value: model.activeConfig?.model ?? model.tr("Hermes default", "Hermes 默认"))
                Spacer()
                Button { model.loadWorkspaceManagementData() } label: { Label(model.tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }
                    .buttonStyle(ManagementButtonStyle())
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: gatewayStatus?.connected == true ? "checkmark.seal.fill" : "seal")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(gatewayStatus?.connected == true ? Color.primaryGreen : Color.appSecondaryText)
                        .frame(width: 48, height: 48)
                        .background(Color.primaryGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.tr("Hermes Gateway", "Hermes 网关"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.appText)
                        Text(model.tr("Use Hermes to check installation, sign in, pick models, and inspect doctor output.", "通过 Hermes 检查安装、登录、选择模型并查看 doctor 输出。"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    Spacer()
                    Text(gatewayStatus?.connected == true ? model.tr("Ready", "就绪") : model.tr("Pending", "待检查"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gatewayStatus?.connected == true ? .white : Color.appSecondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(gatewayStatus?.connected == true ? Color.primaryGreen : Color.surfaceSoft, in: Capsule())
                }

                HStack(spacing: 10) {
                    Button { model.checkHermesInstall() } label: {
                        Label(model.tr("Check Install", "检查安装"), systemImage: "stethoscope")
                    }
                    .buttonStyle(ManagementButtonStyle(primary: true))
                    Button { model.checkHermesAuth(provider: "codex") } label: {
                        Label(model.tr("Codex", "Codex"), systemImage: "terminal")
                    }
                    .buttonStyle(ManagementButtonStyle())
                    Button { model.checkHermesAuth(provider: "anthropic") } label: {
                        Label(model.tr("Claude Code", "Claude Code"), systemImage: "curlybraces")
                    }
                    .buttonStyle(ManagementButtonStyle())
                    Button { model.checkHermesAuth(provider: "openai") } label: {
                        Label(model.tr("API", "API"), systemImage: "key")
                    }
                    .buttonStyle(ManagementButtonStyle())
                    Button { model.runHermesDoctor() } label: {
                        Label(model.tr("Doctor", "诊断"), systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(ManagementButtonStyle())
                    Button { model.openHermesModelInstructions() } label: {
                        Label(model.tr("Setup", "配置"), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(ManagementButtonStyle())
                }

                if let output = model.hermesCommandOutput {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(output.success ? model.tr("Hermes Output", "Hermes 输出") : model.tr("Hermes Error", "Hermes 错误"))
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("exit \(output.exit_code)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Text(output.output)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(18)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
        }
        .onAppear { model.ensureWorkspaceManagementDataLoaded() }
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
        RegistryItemPresentation(kind: item.kind).iconName
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
        TronhubEntryPresentation(kind: entry.kind).iconName
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
                    Text(model.tr("Skills", "Skills")).tag("Tools")
                    Text(model.tr("Files", "文件")).tag("Files")
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(presentation.items) { item in
                            Button {
                                moduleItem = nil
                                onSelect(item, nil)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: presentation.iconName(for: item))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                        Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if presentation.showsCloudBadge(for: item) {
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
