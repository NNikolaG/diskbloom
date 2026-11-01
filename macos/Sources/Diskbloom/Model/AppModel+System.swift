import AppKit
import DiskbloomFFI

/// Actions on disks and items outside the tree.
extension AppModel {
    func revealInFinder(_ id: UInt32) {
        SystemActions.reveal(URL(fileURLWithPath: path(id)))
    }

    func revealInFinder(url: URL) {
        SystemActions.reveal(url)
    }

    func eject(_ place: Place) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: place.url)
            if selected == place {
                selected = nil
                phase = .idle
            }
        } catch {
            alert = String(localized: "Could not eject the disk: \(error.localizedDescription)")
        }
    }

    func emptyTrash() {
        if let message = SystemActions.emptyTrash() {
            alert = String(localized: "Could not empty the Trash: \(message)")
        }
    }

    func openStorageSettings() { SystemActions.openStorageSettings() }

    func openFullDiskAccessSettings() { SystemActions.openFullDiskAccessSettings() }

    /// Size of `~/.Trash`, or `nil` without permission to read it (no Full Disk Access).
    nonisolated static func trashSize() async -> UInt64? {
        let trash = NSHomeDirectory() + "/.Trash"
        return await Task.detached(priority: .utility) { () -> UInt64? in
            guard let job = try? ScanJob(path: trash), let tree = try? job.run(), job.errors() == 0 else { return nil }
            return tree.info(id: tree.root())?.size
        }.value
    }
}
