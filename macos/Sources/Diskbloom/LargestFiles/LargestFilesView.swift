import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// The largest files in the scan, with when they were last opened (from Spotlight).
struct LargestFilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var entries: [Entry]?
    @State private var age: FileAge = .any

    struct Entry: Identifiable {
        let file: FileInfo
        let lastUsed: Date?
        var id: UInt32 { file.id }
    }

    private var shown: [Entry] {
        guard let entries else { return [] }
        guard let cutoff = age.cutoff else { return entries }
        // No date means Spotlight never saw it opened, so it counts as old.
        return entries.filter { ($0.lastUsed ?? .distantPast) < cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Largest files").font(.title3.bold())
                    let total = shown.reduce(UInt64(0)) { $0 + $1.file.size }
                    Text("\(Format.count(shown.count)) files · \(Format.bytes(total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $age) {
                    ForEach(FileAge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(16)
            Divider()
            if entries == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                ContentUnavailable(title: "Nothing here", message: "No large files match this filter.",
                                   symbol: "doc.text.magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { e in
                            FileRow(file: e.file, detail: Self.lastUsedText(e.lastUsed))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
        .task(id: model.dataVersion) { await load() }
    }

    private func load() async {
        guard let tree = model.tree else { return }
        entries = await Task.detached(priority: .userInitiated) {
            tree.largestFiles(limit: 300, minSize: 10_000_000).map { f in
                let item = NSMetadataItem(url: URL(fileURLWithPath: f.path))
                let used = item?.value(forAttribute: "kMDItemLastUsedDate") as? Date
                return Entry(file: f, lastUsed: used)
            }
        }.value
    }

    static func lastUsedText(_ d: Date?) -> String {
        guard let d else { return String(localized: "never opened") }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return String(localized: "opened \(rel.localizedString(for: d, relativeTo: .now))")
    }
}
