import AppKit
import DiskbloomKit

/// Finder, System Settings and other things outside the app.
@MainActor
enum SystemActions {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openStorageSettings() {
        open("x-apple.systempreferences:com.apple.settings.Storage")
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Empties the Trash through Finder (macOS asks once for Automation permission).
    /// Returns the error message, if any.
    static func emptyTrash() -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        return error.map { String(describing: $0[NSAppleScript.errorMessage] ?? "?") }
    }

    /// Runs a shell command as administrator; macOS asks for the password. Only pass
    /// validated values: the command goes to `/bin/sh`.
    static func runAsAdministrator(_ command: String) -> Shell.Result {
        let escaped = command
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
        var error: NSDictionary?
        let output = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)
        if let error {
            return Shell.Result(status: 1, output: (error[NSAppleScript.errorMessage] as? String) ?? "error")
        }
        return Shell.Result(status: 0, output: output?.stringValue ?? "")
    }
}
