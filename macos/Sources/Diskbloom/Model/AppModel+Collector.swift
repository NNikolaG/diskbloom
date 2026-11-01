import DiskbloomFFI

/// The Trash list: items queued while browsing, moved to the Trash in one step.
extension AppModel {
    var collectorTotal: UInt64 { collector.reduce(0) { $0 + $1.size } }

    var collectedIDs: Set<UInt32> { Set(collector.map(\.id)) }

    /// Queues an item. Does nothing if an ancestor is already queued; queued
    /// descendants are replaced by the new item.
    func collect(_ id: UInt32) {
        guard let tree, id != tree.root(), let info = tree.info(id: id) else { return }
        let ancestors = Set(tree.ancestors(id: id).map(\.id))
        if collector.contains(where: { ancestors.contains($0.id) }) { return }
        collector.removeAll { item in tree.ancestors(id: item.id).contains { $0.id == id } }
        collector.append(CollectedItem(id: id, name: info.name, path: tree.path(id: id), size: info.size))
    }

    func uncollect(_ id: UInt32) { collector.removeAll { $0.id == id } }

    func toggleCollect(_ id: UInt32) {
        if collectedIDs.contains(id) { uncollect(id) } else { collect(id) }
    }

    /// Whether the item, or the focused folder containing it, is queued.
    func isCollected(_ id: UInt32) -> Bool {
        let ids = collectedIDs
        return ids.contains(id) || crumbs.contains { ids.contains($0.id) }
    }

    func trashCollector() {
        let items = collector.map { TrashMover.Item(id: $0.id, path: $0.path) }
        Task { await trash(items) }
    }

    /// Moves items to the Trash (they can be put back) and updates the tree without a
    /// rescan. Items that fail stay in the Trash list so they can be retried.
    @discardableResult
    func trash(_ items: [TrashMover.Item]) async -> UInt64 {
        guard let tree, !items.isEmpty, trashProgress == nil else { return 0 }
        trashProgress = (0, items.count)
        defer { trashProgress = nil }

        let report = await TrashMover.move(items) { done in
            self.trashProgress = (done, items.count)
        }
        let freed = report.moved.reduce(UInt64(0)) { $0 + tree.remove(id: $1.id) }
        if !report.failed.isEmpty {
            let shown = report.failed.prefix(8).map(\.path).joined(separator: "\n")
            alert = String(localized: "Could not move \(Format.count(report.failed.count)) items to the Trash:")
                + "\n" + shown + (report.failed.count > 8 ? "\n…" : "")
                + (report.error.map { "\n\n" + $0 } ?? "")
        }
        let moved = Set(report.moved.map(\.id))
        collector.removeAll { moved.contains($0.id) }
        rezoom()
        return freed
    }
}
