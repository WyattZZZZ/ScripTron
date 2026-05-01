import SwiftUI

@main
struct ScripTronNativeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { model.boot() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("ScripTron") {
                Button("Refresh Files") {
                    model.refreshFiles()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

