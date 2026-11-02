import DiskbloomFFI
import DiskbloomKit
import Foundation

/// Smart Clean candidates of one category.
struct CleanGroup: Identifiable {
    struct Item: Identifiable {
        let candidate: CleanCandidate
        let label: String
        let method: CleanupMethod
        /// Last change in the project outside this item; `nil` for non-project items.
        let lastActivity: Date?
        var id: UInt32 { candidate.id }
        /// Docker data is cleaned with `docker system prune`, never selected as a file.
        var isSelectable: Bool { method != .docker && method != .skip }
    }

    let category: String
    let safe: Bool
    let items: [Item]
    let size: UInt64
    var id: String { category }

    var selectableIDs: [UInt32] { items.filter(\.isSelectable).map(\.id) }

    /// Groups candidates by category, largest first. Reads simulator plists, so call
    /// it off the main thread.
    static func make(from candidates: [CleanCandidate]) -> [CleanGroup] {
        let home = NSHomeDirectory()
        return Dictionary(grouping: candidates, by: \.category)
            .map { category, members in
                let items = members.sorted { $0.size > $1.size }.map { candidate in
                    Item(candidate: candidate,
                         label: CandidateLabel.make(category: category, path: candidate.path, home: home),
                         method: CleanupMethod.resolve(category: category, path: candidate.path),
                         lastActivity: candidate.lastActivity > 0
                             ? Date(timeIntervalSince1970: TimeInterval(candidate.lastActivity)) : nil)
                }
                return CleanGroup(category: category, safe: members.first?.safe ?? true, items: items,
                                  size: members.reduce(0) { $0 + $1.size })
            }
            .sorted { $0.size > $1.size }
    }
}
