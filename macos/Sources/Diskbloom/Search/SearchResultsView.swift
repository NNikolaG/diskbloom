import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// Files and folders in the scan whose name contains the search text, largest first.
/// Rust walks the tree off the main thread, after a short pause in typing.
struct SearchResultsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hits: [SearchHit]?

    /// What a search depends on; a new value cancels the running one.
    private struct Request: Equatable {
        let query: String
        let version: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let hits {
                if hits.isEmpty {
                    ContentUnavailable(title: "No results", message: "Nothing in this scan has that name.",
                                       symbol: "magnifyingglass")
                } else {
                    list(hits)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: Request(query: model.searchQuery, version: model.dataVersion)) { await search() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Search results").font(.title3.bold())
            Group {
                if let hits, hits.count >= Int(AppModel.searchLimit) {
                    Text("The \(Format.count(hits.count)) largest matches")
                } else if let hits {
                    Text("\(Format.count(hits.count)) matches · folders open on the map")
                } else {
                    Text("Searching…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func list(_ hits: [SearchHit]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(hits, id: \.file.id) { hit in
                    if hit.isDir {
                        FileRow(file: hit.file, detail: String(localized: "folder")) {
                            model.showOnMap(hit.file.id)
                        }
                    } else {
                        FileRow(file: hit.file)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
    }

    private func search() async {
        let query = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tree = model.tree, !query.isEmpty else { return }
        // Debounce: typing again cancels this task before the walk starts.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let found = await Task.detached(priority: .userInitiated) {
            tree.search(query: query, limit: AppModel.searchLimit)
        }.value
        guard !Task.isCancelled else { return }
        hits = found
    }
}
