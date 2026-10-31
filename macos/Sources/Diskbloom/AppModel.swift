import AppKit
import DiskbloomFFI
import SwiftUI

/// Stanje aplikacije. Rust drzi stablo, Swift drzi samo ono sto prikazuje.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning(path: String, scanned: UInt64)
        case ready
        case failed(String)
    }

    struct Collected: Identifiable, Hashable {
        let id: UInt32
        let name: String
        let path: String
        let size: UInt64
    }

    nonisolated static let rings: UInt32 = 6
    nonisolated static let minFraction = 0.0015

    @Published var phase: Phase = .idle
    @Published private(set) var tree: DiskTree?
    @Published private(set) var focus: UInt32 = 0
    @Published private(set) var segments: [SegmentInfo] = []
    @Published private(set) var crumbs: [NodeInfo] = []
    @Published private(set) var children: [NodeInfo] = []
    @Published var hovered: SegmentInfo?
    @Published var collector: [Collected] = []
    @Published private(set) var inaccessible: UInt64 = 0
    @Published private(set) var hiddenSpace: UInt64 = 0
    @Published var showCleaner = false
    @Published var alert: String?

    private var job: ScanJob?

    var focusInfo: NodeInfo? { tree?.info(id: focus) }
    var collectorTotal: UInt64 { collector.reduce(0) { $0 + $1.size } }

    // MARK: Skeniranje

    func scan(_ url: URL) {
        cancel()
        let path = Self.scanRoot(for: url)
        let job: ScanJob
        do { job = try ScanJob(path: path) } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        self.job = job
        tree = nil
        collector = []
        segments = []
        phase = .scanning(path: path, scanned: 0)

        // Napredak: citamo brojac iz Rust-a dok skener radi u pozadini.
        Task { [weak self] in
            while let self, self.job === job, case .scanning = self.phase {
                self.phase = .scanning(path: path, scanned: job.scanned())
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
        Task.detached(priority: .userInitiated) {
            let result = Result { try job.run() }
            await MainActor.run { [weak self] in
                guard let self, self.job === job else { return }
                switch result {
                case .success(let tree):
                    self.tree = tree
                    self.inaccessible = job.errors()
                    self.hiddenSpace = Self.hiddenSpace(scanned: url, tree: tree)
                    self.phase = .ready
                    self.zoom(to: tree.root())
                case .failure(let e) where (e as? BloomError) == .Cancelled:
                    self.phase = .idle
                case .failure(let e):
                    self.phase = .failed(e.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        job?.cancel()
        job = nil
        if case .scanning = phase { phase = .idle }
    }

    /// Na macOS-u je "/" zapecaceni sistemski volumen; korisnicki podaci su na
    /// Data volumenu (povezani "firmlink"-ovima). Skener ne prelazi volumene,
    /// pa za boot disk skeniramo Data volumen direktno.
    static func scanRoot(for url: URL) -> String {
        let data = "/System/Volumes/Data"
        if url.path == "/", FileManager.default.fileExists(atPath: data) { return data }
        return url.path
    }

    /// "Hidden space" kao u DaisyDisk-u: zauzeto na volumenu minus ono sto smo videli.
    static func hiddenSpace(scanned url: URL, tree: DiskTree) -> UInt64 {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeURLKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              v.volume?.standardizedFileURL == url.standardizedFileURL || url.path == "/",
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacity,
              let seen = tree.info(id: tree.root())?.size
        else { return 0 }
        let used = UInt64(max(0, total - free))
        return used > seen ? used - seen : 0
    }

    // MARK: Navigacija

    func zoom(to id: UInt32) {
        guard let tree else { return }
        focus = id
        hovered = nil
        segments = tree.layout(focus: id, rings: Self.rings, minFraction: Self.minFraction)
        crumbs = tree.ancestors(id: id)
        children = tree.children(id: id)
    }

    func zoomOut() {
        if crumbs.count >= 2 { zoom(to: crumbs[crumbs.count - 2].id) }
    }

    func open(_ seg: SegmentInfo) {
        if let id = seg.id, seg.hasChildren { zoom(to: id) }
    }

    func path(_ id: UInt32) -> String { tree?.path(id: id) ?? "" }

    func revealInFinder(_ id: UInt32) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path(id))])
    }

    // MARK: Collector

    func collect(_ id: UInt32) {
        guard let tree, id != tree.root(), let info = tree.info(id: id) else { return }
        let ancestors = Set(tree.ancestors(id: id).map(\.id))
        if collector.contains(where: { ancestors.contains($0.id) }) { return } // roditelj je vec tu
        // izbaci potomke koje novi element vec pokriva
        collector.removeAll { item in tree.ancestors(id: item.id).contains { $0.id == id } }
        collector.append(Collected(id: id, name: info.name, path: tree.path(id: id), size: info.size))
    }

    func uncollect(_ id: UInt32) { collector.removeAll { $0.id == id } }

    /// Salje u Trash (moze da se vrati), pa azurira stablo bez ponovnog skeniranja.
    @discardableResult
    func trash(_ items: [(id: UInt32, path: String)]) -> UInt64 {
        guard let tree else { return 0 }
        var freed: UInt64 = 0
        var failed: [String] = []
        for item in items {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                freed += tree.remove(id: item.id)
            } catch {
                failed.append("\(item.path): \(error.localizedDescription)")
            }
        }
        if !failed.isEmpty { alert = "Nije moguce obrisati:\n" + failed.joined(separator: "\n") }
        let removed = Set(items.map(\.id))
        collector.removeAll { removed.contains($0.id) }
        // ako je fokus obrisan, vrati se na prvog postojeceg pretka
        let alive = tree.ancestors(id: focus).first?.id == tree.root()
        zoom(to: alive ? focus : tree.root())
        return freed
    }

    func trashCollector() {
        trash(collector.map { (id: $0.id, path: $0.path) })
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
