import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen {
        case workspace
        case project(ProjectPanel)
    }

    enum ProjectPanel: String, CaseIterable, Identifiable {
        case explorer = "Explorer"
        case search = "Search"
        case toolNodes = "Tool Nodes"
        case ragNodes = "RAG Nodes"
        case history = "History"
        case extensions = "Extensions"
        case settings = "Settings"

        var id: String { rawValue }
    }

    @Published var screen: Screen = .workspace
    @Published var workspacePath = "Loading..."
    @Published var files: [FileEntry] = []
    @Published var selectedFile: TronFile?
    @Published var status = "Starting"
    @Published var errorMessage: String?

    private let bridge = RustBridge.shared

    func boot() {
        do {
            try bridge.initialize()
            workspacePath = try bridge.call("get_workspace_path", as: String.self)
            files = try bridge.call("list_workspace_files", as: [FileEntry].self)
            status = "Connected"
        } catch {
            errorMessage = error.localizedDescription
            status = "Rust bridge error"
        }
    }

    func openProject(panel: ProjectPanel = .toolNodes) {
        screen = .project(panel)
    }

    func showWorkspace() {
        screen = .workspace
    }

    func selectPanel(_ panel: ProjectPanel) {
        screen = .project(panel)
    }

    func refreshFiles() {
        do {
            files = try bridge.call("list_workspace_files", as: [FileEntry].self)
            status = "Files refreshed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFile(_ file: FileEntry) {
        guard file.is_tron else { return }
        do {
            selectedFile = try bridge.call("open_tron_file", params: ["path": file.path], as: TronFile.self)
            screen = .project(.explorer)
            status = "Opened \(file.name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

