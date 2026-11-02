import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// What the scan is made of: size and count per file kind, and the largest items of
/// the selected kind. Rust classifies by extension and counts `.app` bundles as one item.
struct TypesView: View {
    @Environment(AppModel.self) private var model
    /// Kinds with at least one item, largest first.
    @State private var kinds: [KindInfo]?
    @State private var selected: FileKind?
    @State private var files: [FileInfo]?

    private static let fileLimit: UInt32 = 200

    /// What the file list depends on; a new value cancels the running load.
    private struct FilesRequest: Equatable {
        let kind: FileKind?
        let version: Int
    }

    private var total: UInt64 { kinds?.reduce(0) { $0 + $1.size } ?? 0 }
    private var count: UInt64 { kinds?.reduce(0) { $0 + $1.count } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kinds {
                if kinds.isEmpty {
                    ContentUnavailable(title: "Nothing here", message: "This scan has no files.", symbol: "chart.bar")
                } else {
                    summary(kinds)
                    Divider()
                    HStack(spacing: 0) {
                        kindList(kinds).frame(width: 320)
                        Divider()
                        fileList
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: model.dataVersion) { await loadKinds() }
        .task(id: FilesRequest(kind: selected, version: model.dataVersion)) { await loadFiles() }
    }

    private func summary(_ kinds: [KindInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("File types").font(.title3.bold())
                Text("\(Format.count(count)) items · \(Format.bytes(total))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            KindsBar(kinds: kinds, total: total, selected: selected) { selected = $0 }
        }
        .padding(16)
    }

    private func kindList(_ kinds: [KindInfo]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(kinds, id: \.kind) { info in
                    KindRow(info: info, total: total, selected: info.kind == selected) { selected = info.kind }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kind = selected, let info = kinds?.first(where: { $0.kind == kind }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text("Largest of \(Format.count(info.count)) items · \(Format.bytes(info.size))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
            }
            if let files {
                if files.isEmpty {
                    ContentUnavailable(title: "Nothing here", message: "No files of this kind.",
                                       symbol: "doc.text.magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(files, id: \.id) { FileRow(file: $0) }
                        }
                        .padding(6)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func loadKinds() async {
        guard let tree = model.tree else { return }
        let found = await Task.detached(priority: .userInitiated) {
            tree.fileKinds().filter { $0.count > 0 }.sorted { $0.size > $1.size }
        }.value
        kinds = found
        // Keep the selection while it still has items; otherwise pick the largest kind.
        if !found.contains(where: { $0.kind == selected }) { selected = found.first?.kind }
    }

    private func loadFiles() async {
        guard let tree = model.tree, let kind = selected else { return }
        let limit = Self.fileLimit
        let found = await Task.detached(priority: .userInitiated) {
            tree.largestOfKind(kind: kind, limit: limit)
        }.value
        guard !Task.isCancelled else { return }
        files = found
    }
}
