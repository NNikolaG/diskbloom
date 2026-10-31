import AppKit
import DiskbloomFFI
import SwiftUI

/// Smart Clean: build folderi, kesevi, emulatori, VM-ovi… koje pronalaze Rust pravila.
/// Simulatori se brisu kroz `xcrun simctl`, Android emulatori zajedno sa `.ini` fajlom,
/// a Docker disk se ne brise nego prazni kroz `docker system prune`.
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
    @State private var confirmDocker = false
    @State private var working = false

    private static let maxRows = 100

    struct Item: Identifiable {
        let c: CleanCandidate
        let label: String
        var id: UInt32 { c.id }
        /// Docker disk se ne brise kao fajl, nego kroz `docker system prune`.
        var isDocker: Bool {
            if case .docker = AppModel.cleanupMethod(category: c.category, path: c.path) { return true }
            return false
        }
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
        .confirmationDialog("Clean up \(Fmt.count(UInt64(selected.count))) items (\(Fmt.bytes(selectedSize)))?",
                            isPresented: $confirm) {
            Button("Clean up", role: .destructive) { Task { await trashSelected() } }
        } message: {
            Text("Files go to the Trash, so you can put them back. Simulators are deleted with Xcode's simctl.")
        }
        .confirmationDialog("Remove unused Docker data?", isPresented: $confirmDocker) {
            Button("Run docker system prune", role: .destructive) {
                Task {
                    working = true
                    if await model.dockerPrune() { groups = nil; await reload() }
                    working = false
                }
            }
        } message: {
            Text("Deletes stopped containers, unused images, networks and build cache. Running containers and volumes are kept. Docker must be running.")
        }
    }

    // MARK: Delovi

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Clean").font(.title2.bold())
                if let groups {
                    let total = groups.reduce(0) { $0 + $1.size }
                    Text("Found \(Fmt.bytes(total)) in \(Fmt.count(UInt64(groups.count))) categories")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let groups, !groups.isEmpty {
                Button("Only safe") { selectSafe() }
                Button("None") { selected = [] }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        if let groups {
            if groups.isEmpty {
                ContentUnavailable(title: "All clean", message: "Nothing to clean up here.", symbol: "checkmark.seal")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        section("Safe to remove", "Rebuilt or re-downloaded automatically: builds, caches, logs.",
                                groups.filter(\.safe))
                        section("Review before removing", "Emulators, virtual machines, backups, installers.",
                                groups.filter { !$0.safe })
                    }
                    .padding(16)
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking for things to clean up…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ groups: [CleanGroup]) -> some View {
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
                    if g.category == "simulators" {
                        Button("Delete all unavailable simulators") {
                            Task {
                                working = true
                                if await model.deleteUnavailableSimulators() { self.groups = nil; await reload() }
                                working = false
                            }
                        }
                        .help("Simulators for iOS versions that are no longer installed (xcrun simctl delete unavailable)")
                        .padding(.leading, 58).padding(.vertical, 4)
                    }
                    ForEach(g.items.prefix(Self.maxRows)) { item in itemRow(item) }
                    if g.items.count > Self.maxRows {
                        let rest = g.items.dropFirst(Self.maxRows)
                        Text("… and \(Fmt.count(UInt64(rest.count))) more (\(Fmt.bytes(rest.reduce(0) { $0 + $1.c.size }))). Checking the category includes them too.")
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
        let selectable = g.items.filter { !$0.isDocker }.count
        let state: CheckState = count == 0 ? .off : count == selectable ? .on : .mixed
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
                (Text(meta.detail) + Text(verbatim: " · ") + Text("\(Fmt.count(UInt64(g.items.count))) items"))
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
            if item.isDocker {
                Image(systemName: "shippingbox").foregroundStyle(.secondary).frame(width: 16)
            } else {
                CheckBox(state: selected.contains(item.id) ? .on : .off) {
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                }
            }
            Text(item.label)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.c.path)
            if item.isDocker {
                Button("Clean up in Docker…") { confirmDocker = true }
                    .help("The Docker disk image must not be deleted while Docker uses it. This runs docker system prune instead.")
            }
            Text(Fmt.bytes(item.c.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.revealInFinder(url: URL(fileURLWithPath: item.c.path)) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show in Finder")
        }
        .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            if let p = model.trashProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .frame(width: 180)
                Text("Moving to Trash… \(Fmt.count(UInt64(p.done)))/\(Fmt.count(UInt64(p.total)))").foregroundStyle(.secondary)
            } else if working {
                ProgressView().controlSize(.small)
            } else {
                Text("Selected: \(Fmt.count(UInt64(selected.count))) · \(Fmt.bytes(selectedSize))").monospacedDigit()
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Clean up…") { confirm = true }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || model.trashProgress != nil || working)
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
        let ids = g.items.filter { !$0.isDocker }.map(\.id)
        if on { selected.formUnion(ids) } else { selected.subtract(ids) }
    }

    private func trashSelected() async {
        let items = (groups ?? []).flatMap(\.items)
            .filter { selected.contains($0.id) && !$0.isDocker }
            .map(\.c)
        await model.clean(items)
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
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let icon: String
    }

    static func meta(_ id: String) -> Meta {
        switch id {
        case "rust-build": return Meta(title: "Rust build", detail: "target/, rebuilt by cargo build", icon: "gearshape.2")
        case "node-deps": return Meta(title: "node_modules", detail: "Restored by npm / yarn install", icon: "shippingbox")
        case "js-build": return Meta(title: "JS build cache", detail: ".next, .nuxt, .turbo", icon: "bolt")
        case "python-cache": return Meta(title: "Python cache", detail: "__pycache__, pytest, mypy, ruff", icon: "chevron.left.forwardslash.chevron.right")
        case "python-venv": return Meta(title: "Python virtualenvs", detail: "Need pip install again after removing", icon: "cube")
        case "gradle": return Meta(title: "Gradle build", detail: "build/ and .gradle/ in projects", icon: "hammer")
        case "cocoapods": return Meta(title: "CocoaPods", detail: "Pods/, restored by pod install", icon: "shippingbox")
        case "swift-build": return Meta(title: "Swift build", detail: ".build/ in Swift packages", icon: "swift")
        case "xcode-derived": return Meta(title: "Xcode DerivedData", detail: "Rebuilt by Xcode", icon: "hammer")
        case "xcode-device-support": return Meta(title: "Device Support", detail: "Debug symbols for older iOS versions", icon: "iphone")
        case "xcode-archives": return Meta(title: "Xcode archives", detail: "Old App Store builds", icon: "archivebox")
        case "simulators": return Meta(title: "iOS simulators", detail: "Devices in Xcode's Simulator", icon: "iphone")
        case "simulator-cache": return Meta(title: "Simulator cache", detail: "CoreSimulator/Caches", icon: "iphone")
        case "android-emulators": return Meta(title: "Android emulators", detail: "AVD devices", icon: "smartphone")
        case "android-images": return Meta(title: "Android system images", detail: "Downloaded again by Android Studio", icon: "square.stack.3d.up")
        case "vms": return Meta(title: "Virtual machines", detail: "Docker, UTM, Parallels, VMware", icon: "server.rack")
        case "pkg-cache": return Meta(title: "Package caches", detail: "Homebrew, npm, pip, Cargo, Gradle…", icon: "shippingbox")
        case "app-cache": return Meta(title: "App caches", detail: "~/Library/Caches", icon: "tray.full")
        case "logs": return Meta(title: "Logs", detail: "~/Library/Logs", icon: "doc.plaintext")
        case "ios-backups": return Meta(title: "iPhone / iPad backups", detail: "Check that you don't need them", icon: "iphone")
        case "installers": return Meta(title: "Installers", detail: ".dmg, .pkg, .iso in Downloads", icon: "arrow.down.doc")
        case "trash": return Meta(title: "Trash", detail: "Files you already deleted", icon: "trash")
        default: return Meta(title: LocalizedStringKey(id), detail: "", icon: "folder")
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
