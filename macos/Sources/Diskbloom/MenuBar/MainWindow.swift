import AppKit
import SwiftUI

/// Brings the main window forward, or opens a new one when it was closed.
@MainActor
enum MainWindow {
    /// The `WindowGroup` id; SwiftUI names its windows "main-AppWindow-1" and so on.
    static let id = "main"

    /// SwiftUI only hands `openWindow` to views, so views that have it leave it here for
    /// code without one (the notification handler).
    private static var opener: OpenWindowAction?

    static func rememberOpener(_ action: OpenWindowAction) {
        opener = action
    }

    static func show(using openWindow: OpenWindowAction? = nil) {
        if let openWindow { opener = openWindow }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: isMainWindow) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else if let opener {
            opener(id: id)
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            // Opening the running app again makes SwiftUI create a window, like a Dock click.
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Closed windows can stay in `NSApp.windows`; only visible or minimized ones count.
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.identifier?.rawValue.hasPrefix(id) == true else { return false }
        return window.isVisible || window.isMiniaturized
    }
}
