import AppKit
import DiskbloomKit

/// Moves files to the Trash in batches, so the UI stays responsive with thousands of items.
@MainActor
enum TrashMover {
    struct Item: Sendable, Hashable {
        let id: UInt32
        let path: String
    }

    struct Report {
        var moved: [Item] = []
        var failed: [Item] = []
        /// The first error macOS gave, with domain and code.
        var error: String?
    }

    private static let batchSize = 200

    /// Tries `NSWorkspace.recycle` per batch, then `FileManager.trashItem` one by one for
    /// what is left, which also gives the exact error per item.
    static func move(_ items: [Item], progress: (Int) -> Void) async -> Report {
        var report = Report()
        var done = 0
        for start in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[start..<min(start + batchSize, items.count)])
            let (movedURLs, batchError) = await recycle(batch.map { URL(fileURLWithPath: $0.path) })
            let movedPaths = Set(movedURLs.keys.map(\.standardizedFileURL.path))
            let (moved, rest) = batch.partitioned { movedPaths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }
            report.moved += moved

            let retried = await trashOneByOne(rest)
            for (item, error) in retried {
                if let error {
                    report.failed.append(item)
                    report.error = report.error ?? error
                } else {
                    report.moved.append(item)
                }
            }
            if report.error == nil, !rest.isEmpty, let batchError {
                report.error = batchError.detailedDescription
            }
            done += batch.count
            progress(done)
        }
        return report
    }

    private static func recycle(_ urls: [URL]) async -> ([URL: URL], (any Error)?) {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { moved, error in
                continuation.resume(returning: (moved, error))
            }
        }
    }

    /// Returns each item with its error message, or `nil` when it was moved.
    private static func trashOneByOne(_ items: [Item]) async -> [(Item, String?)] {
        guard !items.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager()
            return items.map { item in
                do {
                    try fileManager.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    return (item, nil)
                } catch {
                    return (item, error.detailedDescription)
                }
            }
        }.value
    }
}

private extension Array {
    /// Elements that match, and those that do not, in order.
    func partitioned(by matches: (Element) -> Bool) -> (matching: [Element], rest: [Element]) {
        var matching: [Element] = []
        var rest: [Element] = []
        for element in self {
            if matches(element) { matching.append(element) } else { rest.append(element) }
        }
        return (matching, rest)
    }
}
