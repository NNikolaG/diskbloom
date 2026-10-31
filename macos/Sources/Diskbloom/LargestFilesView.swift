import DiskbloomFFI
import SwiftUI

/// Najveci fajlovi u skeniranom folderu, sa datumom poslednjeg otvaranja (Spotlight).
struct LargestFilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var entries: [Entry]?
    @State private var age: Age = .any

    struct Entry: Identifiable {
        let file: FileInfo
        let lastUsed: Date?
        var id: UInt32 { file.id }
    }

    enum Age: String, CaseIterable, Identifiable {
        case any, sixMonths, year
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .any: return "All"
            case .sixMonths: return "Not opened in 6 months"
            case .year: return "Not opened in a year"
            }
        }
        var cutoff: Date? {
            switch self {
            case .any: return nil
            case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: Date())
            case .year: return Calendar.current.date(byAdding: .year, value: -1, to: Date())
            }
        }
    }

    private var shown: [Entry] {
        guard let entries else { return [] }
        guard let cutoff = age.cutoff else { return entries }
        // bez datuma = Spotlight ne zna da je ikad otvaran -> racuna se kao star
        return entries.filter { ($0.lastUsed ?? .distantPast) < cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Largest files").font(.title3.bold())
                    let total = shown.reduce(UInt64(0)) { $0 + $1.file.size }
                    Text("\(Fmt.count(UInt64(shown.count))) files · \(Fmt.bytes(total))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $age) {
                    ForEach(Age.allCases) { Text($0.title).tag($0) }
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
        return String(localized: "opened \(rel.localizedString(for: d, relativeTo: Date()))")
    }
}
