import SwiftUI

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
        case .modelManagement:
            ModelManagementView()
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
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            VStack(alignment: .leading, spacing: 8) {
                WorkspaceNavButton(panel: .allProjects, icon: "folder")
                WorkspaceNavButton(panel: .archived, icon: "archivebox")
                Divider().padding(.vertical, 6)
                WorkspaceNavButton(panel: .cliMarket, icon: "shippingbox")
                WorkspaceNavButton(panel: .cliManagement, icon: "terminal")
                WorkspaceNavButton(panel: .modelManagement, icon: "cpu")
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
        SidebarButton(title: panel.rawValue, icon: icon, active: model.workspacePanel == panel) {
            model.selectWorkspacePanel(panel)
        }
    }
}

private struct WorkspaceTopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Label("Local Workspace", systemImage: "internaldrive")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { model.refreshFiles() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .frame(height: 72)
        .background(.white.opacity(0.75))
    }
}

private struct ProjectsListView: View {
    @EnvironmentObject private var model: AppModel
    let archived: Bool

    private var visibleProjects: [AppModel.ProjectItem] {
        model.projects.filter { $0.archived == archived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(archived ? "Archived Projects" : "Projects")
                    .font(.system(size: 38, weight: .bold))
                Text(archived ? "Restore or delete archived local projects." : "Manage, package, open, archive, or delete local automation projects.")
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
                    EmptyListView(title: archived ? "No archived projects" : "No projects", subtitle: "Create a project from the sidebar.")
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProjectTableHeader: View {
    let archived: Bool

    var body: some View {
        HStack {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: 100, alignment: .leading)
            Text("Actions").frame(width: archived ? 180 : 260, alignment: .leading)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color.surfaceSoft)
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var model: AppModel
    let project: AppModel.ProjectItem
    let archived: Bool

    var body: some View {
        HStack(spacing: 12) {
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
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(Color.primaryGreen)

            HStack(spacing: 12) {
                Button("Open") { model.openProject(project) }.disabled(archived)
                Button("Package") { model.packageProject(project) }.disabled(archived)
                if archived {
                    Button("Restore") { model.restoreProject(project) }
                } else {
                    Button("Archive") { model.archiveProject(project) }
                }
                Button("Delete") { model.deleteProject(project) }.foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .frame(width: archived ? 180 : 260, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }
}

private struct CLIMarketView: View {
    var body: some View {
        ManagementPanel(title: "CLI Market", subtitle: "Browse installable CLI capabilities.", rows: ["Excel CLI", "PDF CLI", "Archive CLI", "HR Report CLI"])
    }
}

private struct CLIManagementView: View {
    var body: some View {
        ManagementPanel(title: "CLI Management", subtitle: "Inspect installed local command-line tools and their manifests.", rows: ["Installed tools", "Manifest validation", "Tool health checks"])
    }
}

private struct ModelManagementView: View {
    var body: some View {
        ManagementPanel(title: "Model Management", subtitle: "Configure local model/provider selection for this device.", rows: ["Active provider", "Model selection", "API key storage"])
    }
}

private struct ManagementPanel: View {
    let title: String
    let subtitle: String
    let rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title).font(.system(size: 38, weight: .bold))
            Text(subtitle).font(.system(size: 17)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    HStack {
                        Text(row).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("LOCAL").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.primaryGreen)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    Divider()
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline.opacity(0.7), lineWidth: 1))
            Spacer()
        }
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FloatingAgentChat: View {
    @EnvironmentObject private var model: AppModel
    @Binding var expanded: Bool
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Agent", systemImage: "sparkles")
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
                    HStack(spacing: 8) {
                        TextField("Ask the workspace agent...", text: $draft)
                            .textFieldStyle(.plain)
                            .focused($inputFocused)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(.white.opacity(0.68), in: Capsule())
                            .overlay(Capsule().stroke(Color.hairline.opacity(0.45), lineWidth: 1))
                            .onSubmit(send)
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
        focusInputIfNeeded()
    }

    private func focusInputIfNeeded() {
        guard expanded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            inputFocused = true
        }
    }
}

private struct ChatBubble: View {
    let message: AppModel.ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role.uppercased())
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
            Text("New Project").font(.system(size: 28, weight: .bold))
            TextField("customer-onboarding", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(createProject)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SheetActionButtonStyle())
                Button("Create") {
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
