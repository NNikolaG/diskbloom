import AppKit
import Combine
import Observation

/// Free space of the mounted volumes, for the menu bar item and the low-space warning.
/// Refreshes every minute and whenever a volume is mounted, unmounted or renamed.
@MainActor
@Observable
final class DiskStatus {
    static let refreshInterval: Duration = .seconds(60)

    private(set) var volumes: [VolumeUsage] = []

    @ObservationIgnored private let lowSpace: LowSpaceMonitor
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    var boot: VolumeUsage? { volumes.first(where: \.isBoot) }

    /// `openBootOverview` runs when the low-space notification is clicked.
    init(openBootOverview: @escaping @MainActor @Sendable () -> Void) {
        lowSpace = LowSpaceMonitor(onOpen: openBootOverview)
        let center = NSWorkspace.shared.notificationCenter
        Publishers.Merge3(center.publisher(for: NSWorkspace.didMountNotification),
                          center.publisher(for: NSWorkspace.didUnmountNotification),
                          center.publisher(for: NSWorkspace.didRenameVolumeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        timer = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    /// Reads the volumes off the main thread; a refresh already under way is enough.
    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            let volumes = await Task.detached(priority: .utility) { VolumeUsage.mounted() }.value
            if volumes != self.volumes { self.volumes = volumes }
            refreshTask = nil
            if let boot { lowSpace.check(boot) }
        }
    }
}
