import DiskbloomFFI
import SwiftUI

/// Smart Clean: regenerisivo smece (build folderi, kesevi, deps) koje pronalaze Rust pravila.
struct CleanerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [CleanCandidate] = []
    @State private var selected: Set<UInt32> = []

    private static let titles: [String: String] = [
        "rust-build": "Rust build (target/)",
        "node-deps": "Node moduli",
        "js-build": "JS build kes (.next, .nuxt)",
        "python-cache": "Python kes",
        "gradle": "Gradle",
        "user-cache": "Korisnicki kes",
        "pkg-cache": "Kes paketa (npm, cargo, gradle)",
        "xcode": "Xcode DerivedData",
        "trash": "Trash",
        "macos-junk": ".DS_Store",
    ]

    struct Group: Identifiable {
        let category: String
        let items: [CleanCandidate]
        var size: UInt64 { items.reduce(0) { $0 + $1.size } }
        var id: String { category }
    }

    private var groups: [Group] {
        Dictionary(grouping: candidates, by: { $0.category })
            .map { Group(category: $0.key, items: $0.value) }
            .sorted { $0.size > $1.size }
    }

    private var selectedSize: UInt64 {
        candidates.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Smart Clean").font(.title2.bold()).padding()
            if candidates.isEmpty {
                ContentUnavailable(title: "Cisto", message: "Nema regenerisivog smeca u ovom folderu.", symbol: "checkmark.seal")
            } else {
                List {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.items, id: \.id) { c in row(c) }
                        } header: {
                            HStack {
                                Toggle(isOn: groupBinding(g.items)) {
                                    Text(Self.titles[g.category] ?? g.category).font(.headline)
                                }
                                Spacer()
                                Text(Fmt.bytes(g.size)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Izabrano: \(Fmt.bytes(selectedSize))").monospacedDigit()
                Spacer()
                Button("Zatvori") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Premesti u Trash") {
                    let items = candidates.filter { selected.contains($0.id) }.map { (id: $0.id, path: $0.path) }
                    model.trash(items)
                    reload()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 480)
        .onAppear(perform: reload)
    }

    private func row(_ c: CleanCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { selected.contains(c.id) },
            set: { if $0 { selected.insert(c.id) } else { selected.remove(c.id) } }
        )) {
            HStack {
                Text(displayPath(c.path)).lineLimit(1).truncationMode(.head).help(c.path)
                Spacer()
                Text(Fmt.bytes(c.size)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func groupBinding(_ items: [CleanCandidate]) -> Binding<Bool> {
        Binding(
            get: { !items.isEmpty && items.allSatisfy { selected.contains($0.id) } },
            set: { on in items.forEach { if on { selected.insert($0.id) } else { selected.remove($0.id) } } }
        )
    }

    private func displayPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    private func reload() {
        candidates = model.tree?.cleanCandidates() ?? []
        // Podrazumevano cekiramo samo bezbedne kategorije; Trash i korisnicki kes rucno.
        let safe: Set<String> = ["rust-build", "node-deps", "js-build", "python-cache", "gradle", "xcode", "macos-junk"]
        selected = Set(candidates.filter { safe.contains($0.category) }.map(\.id))
    }
}
