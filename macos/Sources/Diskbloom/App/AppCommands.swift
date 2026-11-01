import SwiftUI

/// Menu bar commands and their keyboard shortcuts.
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan Home") { model.scan(.home) }
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
            Button("Map") { model.resultMode = .map }
                .keyboardShortcut("1", modifiers: .command)
            Button("Largest Files") { model.resultMode = .largest }
                .keyboardShortcut("2", modifiers: .command)
            Button("Duplicates") { model.resultMode = .duplicates }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
        }
    }
}
