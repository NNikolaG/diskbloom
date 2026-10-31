import AppKit
import DiskbloomFFI
import SwiftUI

/// Smart Clean: build folderi, kesevi, emulatori, VM-ovi… koje pronalaze Rust pravila.
///
/// Napravljeno da ostane brzo i sa desetinama hiljada kandidata:
/// kandidati se racunaju van glavne niti, kategorije su sklopljene (zbir),
/// a u otvorenoj kategoriji prikazuje se najvise `maxRows` stavki.
struct CleanerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [CleanGroup]?          // nil = racuna se
    @State private var sizes: [UInt32: UInt64] = [:]
    @State private var selected: Set<UInt32> = []
    @State private var expanded: Set<String> = []
    @State private var confirm = false

    private static let maxRows = 100

    struct Item: Identifiable {
        let c: CleanCandidate
        let label: String
        var id: UInt32 { c.id }
    }

    struct CleanGroup: Identifiable {
        let category: String
        let safe: Bool
        let items: [Item]
        let size: UInt64
        var id: String { category }
    }

    private var selectedSize: UInt64 { selected.reduce(0) { $0 + (sizes[$1] ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 640)
        .task { await reload() }
        .confirmationDialog("Premestiti \(selected.count) stavki (\(Fmt.bytes(selectedSize))) u Trash?",
                            isPresented: $confirm) {
            Button("Premesti u Trash", role: .destructive) { Task { await trashSelected() } }
        } message: {
            Text("Stavke mozes vratiti iz Trash-a dok ga ne ispraznis.")
        }
    }

    // MARK: Delovi

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Clean").font(.title2.bold())
                if let groups {
                    let total = groups.reduce(0) { $0 + $1.size }
                    Text("Pronadjeno \(Fmt.bytes(total)) u \(groups.count) kategorija")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let groups, !groups.isEmpty {
                Button("Samo bezbedno") { selectSafe() }
                Button("Nista") { selected = [] }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        if let groups {
            if groups.isEmpty {
                ContentUnavailable(title: "Cisto", message: "Nema smeca u ovom folderu.", symbol: "checkmark.seal")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        section("Bezbedno za brisanje", "Regenerise se samo: build, kesevi, logovi.",
                                groups.filter(\.safe))
                        section("Pogledaj pre brisanja", "Emulatori, virtuelne masine, backup-i, instaleri.",
                                groups.filter { !$0.safe })
                    }
                    .padding(16)
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Trazim sta moze da se obrise…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ subtitle: String, _ groups: [CleanGroup]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            ForEach(groups) { g in
                groupRow(g)
                if expanded.contains(g.category) {
                    ForEach(g.items.prefix(Self.maxRows)) { item in itemRow(item) }
                    if g.items.count > Self.maxRows {
                        let rest = g.items.dropFirst(Self.maxRows)
                        Text("… i jos \(rest.count) stavki (\(Fmt.bytes(rest.reduce(0) { $0 + $1.c.size }))). Cekiranje kategorije ukljucuje i njih.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 58).padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func groupRow(_ g: CleanGroup) -> some View {
        let meta = Category.meta(g.category)
        let count = g.items.filter { selected.contains($0.id) }.count
        let state: CheckState = count == 0 ? .off : count == g.items.count ? .on : .mixed
        return HStack(spacing: 12) {
            CheckBox(state: state) { setGroup(g, on: state != .on) }
            Image(systemName: meta.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(g.safe ? Color.accentColor : Color.orange)
                .frame(width: 30, height: 30)
                .background((g.safe ? Color.accentColor : Color.orange).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(meta.title).font(.body.weight(.medium))
                Text("\(meta.detail) · \(g.items.count) \(g.items.count == 1 ? "stavka" : "stavki")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.bytes(g.size)).monospacedDigit().fontWeight(.medium)
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(expanded.contains(g.category) ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded.contains(g.category) { expanded.remove(g.category) } else { expanded.insert(g.category) }
        }
    }

    private func itemRow(_ item: Item) -> some View {
        HStack(spacing: 10) {
            CheckBox(state: selected.contains(item.id) ? .on : .off) {
                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            }
            Text(item.label)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.c.path)
            Text(Fmt.bytes(item.c.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.revealInFinder(url: URL(fileURLWithPath: item.c.path)) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Prikazi u Finder-u")
        }
        .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            if let p = model.trashProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .frame(width: 180)
                Text("Premestam u Trash… \(p.done)/\(p.total)").foregroundStyle(.secondary)
            } else {
                Text("Izabrano: \(selected.count) · \(Fmt.bytes(selectedSize))").monospacedDigit()
            }
            Spacer()
            Button("Zatvori") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Premesti u Trash…") { confirm = true }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || model.trashProgress != nil)
        }
        .padding(16)
    }

    // MARK: Logika

    private func reload() async {
        let candidates = await model.loadCleanCandidates()
        let built = await Task.detached(priority: .userInitiated) { Self.buildGroups(candidates) }.value
        sizes = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.size) })
        groups = built
        selectSafe()
    }

    private func selectSafe() {
        selected = Set((groups ?? []).filter(\.safe).flatMap { $0.items.map(\.id) })
    }

    private func setGroup(_ g: CleanGroup, on: Bool) {
        let ids = g.items.map(\.id)
        if on { selected.formUnion(ids) } else { selected.subtract(ids) }
    }

    private func trashSelected() async {
        let items = (groups ?? []).flatMap(\.items)
            .filter { selected.contains($0.id) }
            .map { (id: $0.c.id, path: $0.c.path) }
        await model.trash(items)
        groups = nil
        await reload()
    }

    nonisolated private static func buildGroups(_ candidates: [CleanCandidate]) -> [CleanGroup] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return Dictionary(grouping: candidates, by: { $0.category })
            .map { category, cs in
                let items = cs.sorted { $0.size > $1.size }.map { Item(c: $0, label: label(for: $0, home: home)) }
                return CleanGroup(category: category, safe: cs.first?.safe ?? true, items: items,
                             size: cs.reduce(0) { $0 + $1.size })
            }
            .sorted { $0.size > $1.size }
    }

    /// Citljivo ime: simulator -> "iPhone 15 Pro · iOS 17.2", ostalo -> putanja sa ~.
    nonisolated private static func label(for c: CleanCandidate, home: String) -> String {
        if c.category == "simulators",
           let data = FileManager.default.contents(atPath: c.path + "/device.plist"),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let name = plist["name"] as? String {
            // com.apple.CoreSimulator.SimRuntime.iOS-17-2 -> iOS 17.2
            let runtime = (plist["runtime"] as? String)?
                .components(separatedBy: ".").last?
                .replacingOccurrences(of: "-", with: " ", options: [], range: nil)
                .replacingFirstSpaceWithDots()
            return runtime.map { "\(name) · \($0)" } ?? name
        }
        if c.category == "android-emulators" {
            return URL(fileURLWithPath: c.path).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
        }
        return c.path.hasPrefix(home) ? "~" + c.path.dropFirst(home.count) : c.path
    }
}

private extension String {
    /// "iOS 17 2" -> "iOS 17.2" (prvi razmak ostaje, ostali postaju tacke)
    func replacingFirstSpaceWithDots() -> String {
        let parts = split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return self }
        return String(parts[0]) + " " + parts[1].replacingOccurrences(of: " ", with: ".")
    }
}

// MARK: - Kategorije

enum Category {
    struct Meta {
        let title: String
        let detail: String
        let icon: String
    }

    static func meta(_ id: String) -> Meta {
        switch id {
        case "rust-build": return Meta(title: "Rust build", detail: "target/ — cargo build ga pravi ponovo", icon: "gearshape.2")
        case "node-deps": return Meta(title: "node_modules", detail: "npm / yarn install ih vraca", icon: "shippingbox")
        case "js-build": return Meta(title: "JS build kes", detail: ".next, .nuxt, .turbo", icon: "bolt")
        case "python-cache": return Meta(title: "Python kes", detail: "__pycache__, pytest, mypy, ruff", icon: "chevron.left.forwardslash.chevron.right")
        case "python-venv": return Meta(title: "Python virtualenv", detail: "Posle brisanja treba pip install", icon: "cube")
        case "gradle": return Meta(title: "Gradle build", detail: "build/ i .gradle/ u projektima", icon: "hammer")
        case "cocoapods": return Meta(title: "CocoaPods", detail: "Pods/ — pod install ih vraca", icon: "shippingbox")
        case "swift-build": return Meta(title: "Swift build", detail: ".build/ u Swift paketima", icon: "swift")
        case "xcode-derived": return Meta(title: "Xcode DerivedData", detail: "Xcode ga pravi ponovo", icon: "hammer")
        case "xcode-device-support": return Meta(title: "Device Support", detail: "Simboli za stare iOS verzije", icon: "iphone")
        case "xcode-archives": return Meta(title: "Xcode arhive", detail: "Stari build-ovi za App Store", icon: "archivebox")
        case "simulators": return Meta(title: "iOS simulatori", detail: "Uredjaji u Xcode simulatoru", icon: "iphone")
        case "simulator-cache": return Meta(title: "Kes simulatora", detail: "CoreSimulator/Caches", icon: "iphone")
        case "android-emulators": return Meta(title: "Android emulatori", detail: "AVD uredjaji", icon: "smartphone")
        case "android-images": return Meta(title: "Android system images", detail: "Ponovo se preuzimaju u Android Studio", icon: "square.stack.3d.up")
        case "vms": return Meta(title: "Virtuelne masine", detail: "Docker, UTM, Parallels, VMware", icon: "server.rack")
        case "pkg-cache": return Meta(title: "Kes paketa", detail: "Homebrew, npm, pip, Cargo, Gradle…", icon: "shippingbox")
        case "app-cache": return Meta(title: "Kes aplikacija", detail: "~/Library/Caches", icon: "tray.full")
        case "logs": return Meta(title: "Logovi", detail: "~/Library/Logs", icon: "doc.plaintext")
        case "ios-backups": return Meta(title: "iPhone / iPad backup-i", detail: "Proveri da li ti trebaju", icon: "iphone")
        case "installers": return Meta(title: "Instaleri", detail: ".dmg, .pkg, .iso u Downloads", icon: "arrow.down.doc")
        case "trash": return Meta(title: "Trash", detail: "Vec obrisani fajlovi", icon: "trash")
        default: return Meta(title: id, detail: "", icon: "folder")
        }
    }
}

// MARK: - Checkbox sa tri stanja

enum CheckState { case off, on, mixed }

struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
