import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .workspace:
                WorkspaceView()
            case .project:
                ProjectStudioView()
            }
        }
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .foregroundStyle(Color.appText)
        .background(Color.appBackground)
        .alert("ScripTron", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
