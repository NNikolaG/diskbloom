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
                Button("Scan Home") {
                    model.scan(.folder(FileManager.default.homeDirectoryForCurrentUser, name: "Home", icon: "house"))
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Refresh This Folder") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.tree == nil || model.refreshing)
                Button("Smart Clean…") { model.showCleaner = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model.tree == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { model.quickLook(model.lastHoveredID) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.tree == nil)
                Divider()
                Button("Map") { model.resultMode = .map }.keyboardShortcut("1", modifiers: .command)
                Button("Largest Files") { model.resultMode = .largest }.keyboardShortcut("2", modifiers: .command)
                Button("Duplicates") { model.resultMode = .duplicates }.keyboardShortcut("3", modifiers: .command)
                Divider()
            }
        }
    }
}
