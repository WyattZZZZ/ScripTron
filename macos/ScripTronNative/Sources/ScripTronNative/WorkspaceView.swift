import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar()
            VStack(spacing: 0) {
                TopSearchBar()
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        projectGrid
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 42)
                }
                CommandCenterBar()
                    .padding(.bottom, 22)
            }
            .background(Color.appBackground)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workspace")
                    .font(.system(size: 36, weight: .bold))
                Text("Manage automation projects, scripts, tools, and run history from one native macOS workspace.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 17))
            }
            Spacer()
            Button {
                model.openProject(panel: .settings)
            } label: {
                Label("Share Workspace", systemImage: "person.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primaryGreen)
        }
    }

    private var projectGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24)
        ], spacing: 24) {
            ProjectCard(title: "Customer Onboarding", status: "Active", metric: "98% Success", icon: "person.text.rectangle", tint: .mint) {
                model.openProject()
            }
            ProjectCard(title: "Lead Enrichment", status: "Idle", metric: "100% Reliable", icon: "cylinder.split.1x2", tint: .purple) {
                model.openProject()
            }
            ProjectCard(title: "Market Pulse", status: "Draft", metric: "Unmonitored", icon: "chart.line.uptrend.xyaxis", tint: .cyan) {
                model.openProject()
            }
            StartAutomatingCard {
                model.openProject(panel: .explorer)
            }
        }
    }
}

private struct WorkspaceSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
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
                model.openProject(panel: .explorer)
            } label: {
                Label("New Project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            VStack(alignment: .leading, spacing: 8) {
                SidebarButton(title: "All Projects", icon: "folder", active: true) {}
                SidebarButton(title: "Shared", icon: "square.and.arrow.up") {}
                SidebarButton(title: "Recent", icon: "clock") {}
                SidebarButton(title: "Archived", icon: "archivebox") {}
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

private struct TopSearchBar: View {
    var body: some View {
        HStack {
            Label("Search automations...", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(width: 520, height: 46, alignment: .leading)
                .background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            Button {} label: { Image(systemName: "bell") }
            Button {} label: { Image(systemName: "gearshape") }
            Text("AR")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.primaryGreen, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        .frame(height: 90)
        .background(.white.opacity(0.75))
    }
}

private struct ProjectCard: View {
    let title: String
    let status: String
    let metric: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 23))
                        .foregroundStyle(Color.primaryGreen)
                        .frame(width: 58, height: 58)
                        .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
                    Spacer()
                    Text(status.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.surfaceSoft, in: Capsule())
                }
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text("Native automation workflow connected to the Rust core through direct C ABI.")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Text("HEALTH METRIC")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(metric)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.primaryGreen)
                }
                ProgressView(value: 0.85)
                    .tint(Color.primaryGreen)
            }
            .padding(26)
            .frame(minHeight: 300)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
    }
}

private struct StartAutomatingCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 36))
                Text("Start Automating")
                    .font(.system(size: 22, weight: .bold))
                Text("Create a native Swift project flow.")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .foregroundStyle(.white)
            .background(Color.primaryGreen, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

private struct CommandCenterBar: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("⌘").padding(8).background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
            Text("K").padding(8).background(Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
            Text("COMMAND CENTER").font(.system(size: 12, weight: .bold)).tracking(2)
            Divider().frame(height: 22)
            Label("Quick Action", systemImage: "bolt")
            Label("View History", systemImage: "clock.arrow.circlepath")
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 26)
        .frame(height: 54)
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

