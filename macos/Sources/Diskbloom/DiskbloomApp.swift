import AppKit
import SwiftUI

@main
struct DiskbloomApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Potrebno kad se pokrece kao goli binarni fajl (`swift run`), van .app paketa.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { model.autoScanFromEnvironment() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Skeniraj Home") { model.scan(FileManager.default.homeDirectoryForCurrentUser) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }
}
