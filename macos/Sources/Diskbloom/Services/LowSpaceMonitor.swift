import DiskbloomKit
import Foundation

/// Warns once when the startup disk runs low, then stays quiet until space has recovered
/// (`LowSpaceAlert` decides). Whether it already warned survives restarts, so a full
/// disk does not bring a notification on every launch.
@MainActor
final class LowSpaceMonitor {
    private static let notifiedKey = "lowSpaceNotified"

    private var alert: LowSpaceAlert
    private let notifications: LowSpaceNotifications

    init(onOpen: @escaping @MainActor @Sendable () -> Void) {
        alert = LowSpaceAlert(hasNotified: UserDefaults.standard.bool(forKey: Self.notifiedKey))
        notifications = LowSpaceNotifications(onOpen: onOpen)
        // Only the click handler is installed now; permission is asked before the first post.
        notifications.install()
    }

    func check(_ volume: VolumeUsage) {
        guard AppSettings.notifyLowSpace else { return }
        let warn = alert.update(free: volume.free, total: volume.total)
        UserDefaults.standard.set(alert.hasNotified, forKey: Self.notifiedKey)
        guard warn else { return }
        let free = Format.bytes(UInt64(max(0, volume.free)))
        let name = volume.name
        Task { await LowSpaceNotifications.post(free: free, volume: name) }
    }
}
