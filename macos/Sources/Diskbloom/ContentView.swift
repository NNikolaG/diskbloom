import AppKit
import DiskbloomFFI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VolumesSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle:
                    EmptyState()
                case .scanning(let path, let scanned):
                    ScanningView(path: path, scanned: scanned)
                case .failed(let msg):
                    ContentUnavailable(title: "Greska", message: msg, symbol: "exclamationmark.triangle")
                case .ready:
                    ResultView()
                }
                if !model.collector.isEmpty { CollectorBar() }
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $model.showCleaner) { CleanerView().environmentObject(model) }
        .alert("Diskbloom", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if case .ready = model.phase {
                Button { model.zoomOut() } label: { Label("Nazad", systemImage: "chevron.left") }
                    .disabled(model.crumbs.count < 2)
                Button { model.showCleaner = true } label: { Label("Smart Clean", systemImage: "sparkles") }
            }
            Button { chooseFolder() } label: { Label("Izaberi folder", systemImage: "folder") }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Skeniraj"
        if panel.runModal() == .OK, let url = panel.url { model.scan(url) }
    }
}

// MARK: - Sidebar sa volumenima

struct VolumeInfo: Identifiable {
    let url: URL
    let name: String
    let total: Int
    let free: Int
    var id: URL { url }

    static func all() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(url: url, name: v.volumeName ?? url.lastPathComponent,
                              total: total, free: v.volumeAvailableCapacity ?? 0)
        }
    }
}

struct VolumesSidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var volumes = VolumeInfo.all()

    var body: some View {
        List {
            Section("Diskovi") {
                ForEach(volumes) { v in
                    Button { model.scan(v.url) } label: { VolumeRow(volume: v) }
                        .buttonStyle(.plain)
                }
            }
            Section("Folderi") {
                folder("Home", FileManager.default.homeDirectoryForCurrentUser, "house")
                folder("Downloads", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"), "arrow.down.circle")
                folder("Library", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"), "building.columns")
            }
        }
        .listStyle(.sidebar)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = VolumeInfo.all()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = VolumeInfo.all()
        }
    }

    private func folder(_ title: String, _ url: URL, _ icon: String) -> some View {
        Button { model.scan(url) } label: { Label(title, systemImage: icon) }.buttonStyle(.plain)
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        let used = Double(volume.total - volume.free) / Double(volume.total)
        VStack(alignment: .leading, spacing: 4) {
            Label(volume.name, systemImage: volume.url.path == "/" ? "internaldrive" : "externaldrive")
            ProgressView(value: used).tint(used > 0.9 ? .red : .accentColor)
            Text("\(Fmt.bytes(UInt64(volume.free))) slobodno od \(Fmt.bytes(UInt64(volume.total)))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Stanja

struct ContentUnavailable: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    var body: some View {
        ContentUnavailable(title: "Diskbloom",
                           message: "Izaberi disk ili folder levo da vidis sta zauzima prostor.",
                           symbol: "circle.hexagongrid")
    }
}

struct ScanningView: View {
    @EnvironmentObject var model: AppModel
    let path: String
    let scanned: UInt64

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Skeniram \(path)").font(.headline)
            Text("\(Fmt.count(scanned)) objekata").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            Button("Otkazi") { model.cancel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rezultat: mapa + lista

struct ResultView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.inaccessible > 0 { AccessBanner() }
            HSplitView {
                SunburstView().frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                ChildrenList().frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
            }
        }
    }
}

struct AccessBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            Image(systemName: "lock.fill")
            Text("\(Fmt.count(model.inaccessible)) foldera nije dostupno. Daj Diskbloom-u Full Disk Access za potpun pregled.")
            Spacer()
            Button("Otvori podesavanja") { model.openFullDiskAccessSettings() }
        }
        .font(.callout)
        .padding(8)
        .background(.yellow.opacity(0.18))
    }
}

struct ChildrenList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Breadcrumbs().padding(10)
            if model.hiddenSpace > 0, model.crumbs.count == 1 {
                Text("Skriveni prostor (sistem, snapshot-i, nedostupno): \(Fmt.bytes(model.hiddenSpace))")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 6)
            }
            Divider()
            List(model.children, id: \.id) { c in
                ChildRow(node: c)
            }
            .listStyle(.inset)
        }
    }
}

struct Breadcrumbs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button(i == 0 ? model.tree?.rootPath() ?? n.name : n.name) { model.zoom(to: n.id) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ChildRow: View {
    @EnvironmentObject var model: AppModel
    let node: NodeInfo

    var body: some View {
        let seg = model.segments.first { $0.id == node.id }
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(seg.map { Palette.color($0) } ?? Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
            Image(systemName: node.isDir ? "folder.fill" : "doc").foregroundStyle(.secondary)
            Text(node.displayName).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if node.hasChildren { model.zoom(to: node.id) } }
        .draggable(String(node.id))
        .contextMenu {
            if node.hasChildren { Button("Otvori") { model.zoom(to: node.id) } }
            Button("Dodaj u Collector") { model.collect(node.id) }
            Button("Prikazi u Finder-u") { model.revealInFinder(node.id) }
        }
    }
}
