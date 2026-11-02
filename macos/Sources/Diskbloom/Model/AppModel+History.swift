import DiskbloomFFI
import Foundation

/// Saved scans: show the last scan of a place right away, bring it up to date by
/// rescanning only what FSEvents reports as changed, and show what grew.
extension AppModel {
    /// Changes smaller than this are not worth listing.
    private static let minGrowth: UInt64 = 25_000_000
    /// More changed folders than this: one full rescan is simpler and not slower.
    private static let maxRescans = 300

    /// Loads the saved scan of `place`, if any, then updates it in the background.
    func openSaved(_ place: Place) {
        let root = BootVolume.scanRoot(for: place.url)
        guard ScanStore.hasSaved(root: root) else { return }
        Task {
            guard let saved = await ScanStore.load(root: root),
                  selected == place, scannedPlace != place, !isScanning
            else { return }
            let date = Date(timeIntervalSince1970: TimeInterval(saved.savedAt()))
            show(saved, of: place, scannedAt: date, inaccessible: 0)
            sync = ScanStore.Sync(root: root, eventID: saved.savedEventId(), date: date)
            await catchUp(place)
        }
    }

    /// Rescans the folders that changed since the saved scan and lists what grew.
    private func catchUp(_ place: Place) async {
        guard let tree, let sync, !catchingUp else { return }
        catchingUp = true
        defer { catchingUp = false }
        let startID = ChangeHistory.currentEventID
        let baseline = await Task.detached(priority: .utility) { tree.copy() }.value
        let roots = place.isBootVolume ? ["/"] : [sync.root]
        let targets: [UInt32]
        switch await ChangeHistory.changes(under: roots, since: sync.eventID) {
        case .unknown:
            targets = [tree.root()]
        case .changed(let paths):
            targets = await Task.detached(priority: .utility) { Self.rescanTargets(paths, in: tree) }.value
        }
        for id in targets {
            guard self.tree === tree else { return } // another scan replaced it
            _ = await Task.detached(priority: .utility) { try? tree.rescan(id: id) }.value
        }
        guard self.tree === tree else { return }
        collector.removeAll { !tree.isAttached(id: $0.id) }
        rezoom()
        scannedAt = .now
        inaccessible = 0
        await showGrowth(of: tree, since: baseline, date: sync.date)
        self.sync = ScanStore.Sync(root: sync.root, eventID: startID, date: .now)
        persist()
    }

    /// Entries to rescan for the changed paths: the nearest known folder of each, without
    /// folders that lie inside another one on the list.
    nonisolated private static func rescanTargets(_ paths: Set<String>, in tree: DiskTree) -> [UInt32] {
        let ids = Set(paths.compactMap { tree.findNearest(path: $0) })
        let nested = ids.filter { id in
            tree.ancestors(id: id).dropLast().contains { ids.contains($0.id) }
        }
        let targets = ids.subtracting(nested)
        return targets.count > maxRescans ? [tree.root()] : Array(targets)
    }

    /// After a full scan: compare with the saved scan of the same place, then save.
    func compareWithSaved(_ tree: DiskTree, sync: ScanStore.Sync) async {
        self.sync = sync
        if let old = await ScanStore.load(root: sync.root) {
            await showGrowth(of: tree, since: old, date: Date(timeIntervalSince1970: TimeInterval(old.savedAt())))
        }
        persist()
    }

    private func showGrowth(of tree: DiskTree, since old: DiskTree, date: Date) async {
        let changes = await Task.detached(priority: .utility) {
            tree.growthSince(old: old, minDelta: Self.minGrowth, limit: 8)
        }.value
        guard self.tree === tree else { return }
        growth = changes
        growthSince = date
    }

    /// Saves the current tree in the background (after a scan, a refresh or a delete).
    func persist() {
        guard let tree, let sync else { return }
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            await ScanStore.save(tree, sync: sync)
        }
    }

    /// Shows a growth entry on the map.
    func showChange(_ change: GrowthInfo) {
        guard let id = change.id, let tree, tree.isAttached(id: id) else { return }
        let info = tree.info(id: id)
        let target = info?.isDir == true ? id : tree.ancestors(id: id).dropLast().last?.id ?? id
        resultMode = .map
        phase = .ready
        zoom(to: target)
    }

    func forgetSavedScans() {
        saveTask?.cancel()
        ScanStore.removeAll()
        growth = nil
        growthSince = nil
    }
}
