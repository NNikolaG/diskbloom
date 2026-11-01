import AppKit
import SwiftUI

@main
struct DiskbloomApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Needed when started as a bare binary (`swift run`) outside an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { model.applyLaunchOptions() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(model: model) }
    }
}
