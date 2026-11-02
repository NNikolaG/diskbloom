import CryptoKit
import DiskbloomFFI
import Foundation

/// Saved scans in `~/Library/Caches/<bundle id>/scans`, one file per scanned folder.
/// They hold file names and sizes only, never leave the Mac, and can be deleted at any
/// time (the next scan simply starts from scratch).
enum ScanStore {
    /// What is needed to save a tree after it changed.
    struct Sync: Sendable {
        let root: String
        /// FSEvents event id at the moment the tree matched the disk.
        let eventID: UInt64
        let date: Date
    }

    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "io.github.nnikolag.diskbloom"
        return caches.appendingPathComponent(bundle).appendingPathComponent("scans")
    }

    /// The file for a scanned root path (hashed, so any path makes a valid file name).
    static func file(for root: String) -> URL {
        let digest = SHA256.hash(data: Data(root.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("dbtree")
    }

    static func save(_ tree: DiskTree, sync: Sync) async {
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try tree.save(path: file(for: sync.root).path,
                              scannedAt: Int64(sync.date.timeIntervalSince1970),
                              eventId: sync.eventID)
            } catch {
                // A missing cache only costs a full scan next time.
            }
        }.value
    }

    static func load(root: String) async -> DiskTree? {
        let path = file(for: root).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return await Task.detached(priority: .userInitiated) { try? DiskTree.load(path: path) }.value
    }

    static func hasSaved(root: String) -> Bool {
        FileManager.default.fileExists(atPath: file(for: root).path)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
