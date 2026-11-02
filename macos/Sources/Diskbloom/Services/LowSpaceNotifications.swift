import Foundation
import UserNotifications

/// Posts the "startup disk is almost full" notification and handles clicks on it.
final class LowSpaceNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let category = "low-space"
    static let openAction = "open-overview"

    private let onOpen: @MainActor @Sendable () -> Void

    init(onOpen: @escaping @MainActor @Sendable () -> Void) {
        self.onOpen = onOpen
    }

    /// UserNotifications needs an app bundle: a bare binary (`swift run`) would crash.
    nonisolated static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Becomes the delegate, so a click also works when it launched the app. This does
    /// not ask for permission.
    @MainActor func install() {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for permission the first time; without it, does nothing.
    nonisolated static func post(free: String, volume: String) async {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else { return }

        let open = UNNotificationAction(identifier: openAction, title: String(localized: "Open Diskbloom"),
                                        options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [open], intentIdentifiers: [], options: []),
        ])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your startup disk is almost full")
        content.body = String(localized: "Only \(free) free on \(volume). Open Diskbloom to see what takes up space.")
        content.sound = .default
        content.categoryIdentifier = category
        try? await center.add(UNNotificationRequest(identifier: category, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A click on the notification or its button opens the startup disk's overview.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Self.category,
              response.actionIdentifier != UNNotificationDismissActionIdentifier
        else { return }
        await onOpen()
    }

    /// Shown as a banner even while Diskbloom is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
