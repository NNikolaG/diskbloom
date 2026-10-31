import AppKit
import DiskbloomFFI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            VolumesSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle:
                    if let place = model.selected { PlaceOverview(place: place) } else { EmptyState() }
                case .scanning(let path, let scanned):
                    ScanningView(path: path, scanned: scanned)
                case .failed(let msg):
                    ContentUnavailable(title: "Greska", message: msg, symbol: "exclamationmark.triangle")
                case .ready:
                    ResultView()
                }
                if case .ready = model.phase { CollectorBar() }
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
                Button { model.showOverview() } label: { Label("Pregled diska", systemImage: "square.grid.2x2") }
                    .help("Nazad na pregled i akcije za ovaj disk")
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
    let ejectable: Bool
    var id: URL { url }
    var place: AppModel.Place { AppModel.Place(url: url, name: name, icon: url.path == "/" ? "internaldrive" : "externaldrive", isVolume: true) }

    static func all() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(url: url, name: v.volumeName ?? url.lastPathComponent,
                              total: total, free: v.volumeAvailableCapacity ?? 0,
                              ejectable: url.path != "/" && (v.volumeIsEjectable == true || v.volumeIsRemovable == true))
        }
    }
}

struct VolumesSidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var volumes = VolumeInfo.all()

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let folders: [AppModel.Place] = [
        .folder(home, name: "Home", icon: "house"),
        .folder(home.appendingPathComponent("Desktop"), name: "Desktop", icon: "menubar.dock.rectangle"),
        .folder(home.appendingPathComponent("Documents"), name: "Documents", icon: "doc.text"),
        .folder(home.appendingPathComponent("Downloads"), name: "Downloads", icon: "arrow.down.circle"),
        .folder(home.appendingPathComponent("Library"), name: "Library", icon: "building.columns"),
        .folder(URL(fileURLWithPath: "/Applications"), name: "Applications", icon: "square.grid.2x2"),
    ]

    var body: some View {
        // Izvorna selekcija liste: klik oznaci red i otvori pregled sa akcijama.
        List(selection: Binding(get: { model.selected }, set: { if let p = $0 { model.select(p) } })) {
            Section("Diskovi") {
                ForEach(volumes) { v in
                    VolumeRow(volume: v)
                        .tag(v.place)
                        .contextMenu { PlaceMenu(place: v.place, ejectable: v.ejectable) }
                }
            }
            Section("Folderi") {
                ForEach(Self.folders) { f in
                    Label(f.name, systemImage: f.icon)
                        .tag(f)
                        .contextMenu { PlaceMenu(place: f, ejectable: false) }
                }
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
}

/// Desni klik na disk/folder u sidebar-u.
struct PlaceMenu: View {
    @EnvironmentObject var model: AppModel
    let place: AppModel.Place
    let ejectable: Bool

    var body: some View {
        Button("Skeniraj") { model.scan(place) }
        Button("Smart Clean") { model.scan(place, clean: true) }
        Divider()
        Button("Prikazi u Finder-u") { model.revealInFinder(url: place.url) }
        if ejectable {
            Button("Izbaci") { model.eject(place) }
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        let used = Double(volume.total - volume.free) / Double(volume.total)
        VStack(alignment: .leading, spacing: 4) {
            Label(volume.name, systemImage: volume.url.path == "/" ? "internaldrive" : "externaldrive")
                .lineLimit(1)
            ProgressView(value: used).tint(used > 0.9 ? .red : .accentColor)
            Text("\(Fmt.bytes(UInt64(volume.free))) slobodno od \(Fmt.bytes(UInt64(volume.total)))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
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
                           message: "Izaberi disk ili folder levo.",
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
            // Obican HStack umesto HSplitView: HSplitView je sabirao idealne sirine
            // i gurao sadrzaj van prozora (sidebar odsecen levo, lista desno).
            HStack(spacing: 0) {
                SunburstView()
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ChildrenList().frame(width: 340)
            }
        }
    }
}

struct AccessBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text("\(Fmt.count(model.inaccessible)) foldera nije dostupno. Daj Diskbloom-u Full Disk Access za potpun pregled.")
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Otvori podesavanja") { model.openFullDiskAccessSettings() }
                .fixedSize()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ChildrenList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Breadcrumbs()
                if let f = model.focusInfo {
                    HStack(spacing: 4) {
                        Text("\(Fmt.bytes(f.size)) · \(Fmt.count(f.files)) fajlova")
                        if model.crumbs.count > 1 {
                            Text("· \(AppModel.percent(f.size, of: model.rootSize)) od \(model.crumbs.first.map { model.title($0) } ?? "")")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if model.hiddenSpace > 0, model.crumbs.count == 1 {
                    Text("Skriveni prostor: \(Fmt.bytes(model.hiddenSpace))")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Zauzeto na volumenu, a nije vidljivo skeneru: sistemski volumen, snapshot-i, folderi bez dozvole.")
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.children, id: \.id) { c in
                        ChildRow(node: c, total: model.focusInfo?.size ?? 1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct Breadcrumbs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(model.title(n)) { model.zoom(to: n.id) }
                            .buttonStyle(.link)
                            .font(i == model.crumbs.count - 1 ? .headline : .body)
                            .lineLimit(1)
                            .fixedSize()
                            .id(n.id)
                    }
                }
            }
            .onChange(of: model.focus) { id in proxy.scrollTo(id, anchor: .trailing) }
        }
    }
}

struct ChildRow: View {
    @EnvironmentObject var model: AppModel
    let node: NodeInfo
    let total: UInt64
    @State private var hover = false

    var body: some View {
        let seg = model.segments.first { $0.id == node.id }
        let color = seg.map { Palette.color($0) } ?? Color.gray.opacity(0.35)
        let fraction = total > 0 ? Double(node.size) / Double(total) : 0
        let collected = model.isCollected(node.id)
        let highlighted = hover || (model.hovered?.id == node.id)

        // Ceo red je dugme: klik na folder ulazi u njega.
        // (.onTapGesture + .draggable na macOS-u: drag "proguta" klik.)
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                    Image(systemName: node.isDir ? "folder.fill" : "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .strikethrough(collected)
                            .foregroundStyle(collected ? .secondary : .primary)
                        // traka: koliki deo trenutnog foldera zauzima
                        GeometryReader { g in
                            Capsule().fill(Color.primary.opacity(0.06))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(color.opacity(0.85))
                                        .frame(width: max(2, g.size.width * fraction))
                                }
                        }
                        .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(node.size)).monospacedDigit()
                        Text(AppModel.percent(node.size, of: total))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 76, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrag { NSItemProvider(object: String(node.id) as NSString) }

            Button { model.toggleCollect(node.id) } label: {
                Image(systemName: collected ? "trash.slash" : "trash")
                    .foregroundStyle(collected ? Color.red : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hover || collected ? 1 : 0)
            .help(collected ? "Izbaci iz korpe" : "Dodaj u korpu za brisanje")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlighted ? Color.primary.opacity(0.07) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hover = $0 }
        .help("\(node.displayName) — \(Fmt.bytes(node.size)) (\(AppModel.percent(node.size, of: total)))")
        .contextMenu {
            if node.hasChildren { Button("Otvori") { open() } }
            Button(collected ? "Izbaci iz korpe" : "Dodaj u korpu") { model.toggleCollect(node.id) }
            Button("Prikazi u Finder-u") { model.revealInFinder(node.id) }
        }
    }

    /// Folder: udji u njega. Fajl: prikazi ga u Finder-u.
    private func open() {
        if node.hasChildren { model.zoom(to: node.id) } else { model.revealInFinder(node.id) }
    }
}
