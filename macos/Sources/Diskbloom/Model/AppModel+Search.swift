import Foundation

/// Finding files and folders by name in the scan.
extension AppModel {
    /// Most results a search shows; Rust keeps the largest ones.
    nonisolated static let searchLimit: UInt32 = 500

    /// Whether search results are shown instead of the selected mode.
    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Leaves the search and opens a folder on the map.
    func showOnMap(_ id: UInt32) {
        searchQuery = ""
        resultMode = .map
        zoom(to: id)
    }
}
