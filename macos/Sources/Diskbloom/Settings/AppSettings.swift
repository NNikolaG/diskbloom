import Foundation

/// The app's two preferences, stored in `UserDefaults` (and read with `@AppStorage`).
/// Both are on by default.
enum AppSettings {
    /// Whether the free-space item is in the menu bar.
    static let showMenuBarExtraKey = "showMenuBarExtra"
    /// Whether to post a notification when the startup disk runs low.
    static let notifyLowSpaceKey = "notifyLowSpace"

    static var notifyLowSpace: Bool {
        UserDefaults.standard.object(forKey: notifyLowSpaceKey) as? Bool ?? true
    }
}
