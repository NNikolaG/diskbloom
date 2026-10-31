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

    /// Disk ili folder izabran u sidebar-u.
    struct Place: Identifiable, Hashable {
        let url: URL
        let name: String
        let icon: String
        let isVolume: Bool
        var id: URL { url }
        var isBootVolume: Bool { isVolume && url.path == "/" }

        static func folder(_ url: URL, name: String? = nil, icon: String = "folder") -> Place {
            Place(url: url, name: name ?? FileManager.default.displayName(atPath: url.path), icon: icon, isVolume: false)
        }
    }

    nonisolated static let rings: UInt32 = 6
    nonisolated static let minFraction = 0.003

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
    @Published var selected: Place?
    /// Za koje mesto je `tree` (poslednje skeniranje) i kada.
    @Published private(set) var scannedPlace: Place?
    @Published private(set) var scannedAt: Date?

    private var job: ScanJob?
    private var cleanAfterScan = false

    var focusInfo: NodeInfo? { tree?.info(id: focus) }
    var collectorTotal: UInt64 { collector.reduce(0) { $0 + $1.size } }

    // MARK: Skeniranje

    /// Klik na disk/folder u sidebar-u: prikazuje pregled sa akcijama, ne skenira odmah.
    func select(_ place: Place) {
        if case .scanning = phase { cancel() }
        selected = place
        phase = (scannedPlace == place && tree != nil) ? .ready : .idle
    }

    func showOverview() { phase = .idle }

    func showResults() { if tree != nil { phase = .ready } }

    func scan(_ place: Place, clean: Bool = false) {
        selected = place
        scan(place.url, clean: clean)
    }

    func scan(_ url: URL, clean: Bool = false) {
        cancel()
        cleanAfterScan = clean
        if selected?.url != url { selected = .folder(url) }
        let place = selected
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
                    self.scannedPlace = place
                    self.scannedAt = Date()
                    self.inaccessible = job.errors()
                    self.hiddenSpace = Self.hiddenSpace(scanned: url, tree: tree)
                    self.phase = .ready
                    self.zoom(to: tree.root())
                    if self.cleanAfterScan { self.showCleaner = true }
                    self.cleanAfterScan = false
                    // CI screenshot: pokazi korpu sa jednom stavkom
                    if ProcessInfo.processInfo.environment["DISKBLOOM_DEMO"] != nil,
                       let first = self.children.first {
                        self.collect(first.id)
                    }
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
        // "ForImportantUsage" ukljucuje purgeable prostor kao slobodan, kao Finder.
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeURLKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              v.volume?.standardizedFileURL == url.standardizedFileURL || url.path == "/",
              let total = v.volumeTotalCapacity.map(Int64.init), let free = v.volumeAvailableCapacityForImportantUsage,
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

    /// Lepo ime: za koren prikazujemo ime volumena/foldera umesto pune putanje.
    func title(_ n: NodeInfo) -> String {
        guard let tree, n.id == tree.root() else { return n.name }
        let path = tree.rootPath()
        if path == "/System/Volumes/Data" || path == "/" {
            let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey])
            return v?.volumeName ?? "Macintosh HD"
        }
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }

    /// Za CI screenshot / brzo testiranje: DISKBLOOM_SCAN=/neki/folder skenira odmah.
    func autoScanFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let p = env["DISKBLOOM_SCAN"], !p.isEmpty {
            scan(URL(fileURLWithPath: p))
            if env["DISKBLOOM_CLEAN"] != nil { cleanAfterScan = true }
        } else if env["DISKBLOOM_OVERVIEW"] != nil {
            let root = URL(fileURLWithPath: "/")
            let name = (try? root.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
            select(Place(url: root, name: name, icon: "internaldrive", isVolume: true))
        }
    }

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

    var collectedIDs: Set<UInt32> { Set(collector.map(\.id)) }

    /// Da li je stavka (ili neki njen predak) vec u korpi.
    func isCollected(_ id: UInt32) -> Bool {
        let ids = collectedIDs
        return ids.contains(id) || crumbs.contains { ids.contains($0.id) }
    }

    func toggleCollect(_ id: UInt32) {
        if collectedIDs.contains(id) { uncollect(id) } else { collect(id) }
    }

    var rootSize: UInt64 { tree.flatMap { $0.info(id: $0.root()) }?.size ?? 0 }

    /// Udeo u procentima, npr. "12.3%" (ili "<0.1%").
    static func percent(_ part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "" }
        let p = Double(part) / Double(total) * 100
        if p > 0, p < 0.1 { return "<0.1%" }
        return String(format: p >= 10 ? "%.0f%%" : "%.1f%%", p)
    }

    /// Napredak slanja u Trash (nil = nista se ne brise).
    @Published private(set) var trashProgress: (done: Int, total: Int)?

    /// Salje u Trash (moze da se vrati) i azurira stablo bez ponovnog skeniranja.
    /// Radi u grupama preko NSWorkspace.recycle, pa UI ostaje odziv i sa hiljadama stavki.
    @discardableResult
    func trash(_ items: [(id: UInt32, path: String)]) async -> UInt64 {
        guard let tree, !items.isEmpty, trashProgress == nil else { return 0 }
        trashProgress = (0, items.count)
        defer { trashProgress = nil }

        var freed: UInt64 = 0
        var failed: [String] = []
        var firstError: String?
        var done = 0
        let chunkSize = 200
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let chunk = items[start..<min(start + chunkSize, items.count)]
            let (moved, error) = await recycle(chunk.map { URL(fileURLWithPath: $0.path) })
            let movedPaths = Set(moved.keys.map { $0.standardizedFileURL.path })
            for item in chunk {
                if movedPaths.contains(URL(fileURLWithPath: item.path).standardizedFileURL.path) {
                    freed += tree.remove(id: item.id)
                } else {
                    failed.append(item.path)
                }
            }
            if let error, firstError == nil { firstError = error.localizedDescription }
            done += chunk.count
            trashProgress = (done, items.count)
        }
        if !failed.isEmpty {
            let shown = failed.prefix(8).joined(separator: "\n")
            alert = "Nije moguce premestiti u Trash (\(failed.count)):\n" + shown + (failed.count > 8 ? "\n…" : "")
                + (firstError.map { "\n\n" + $0 } ?? "")
        }
        let removed = Set(items.map(\.id))
        collector.removeAll { removed.contains($0.id) }
        // ako je fokus obrisan, vrati se na prvog postojeceg pretka
        let alive = tree.ancestors(id: focus).first?.id == tree.root()
        zoom(to: alive ? focus : tree.root())
        return freed
    }

    private func recycle(_ urls: [URL]) async -> ([URL: URL], Error?) {
        await withCheckedContinuation { cont in
            NSWorkspace.shared.recycle(urls) { moved, error in
                cont.resume(returning: (moved, error))
            }
        }
    }

    func trashCollector() {
        let items = collector.map { (id: $0.id, path: $0.path) }
        Task { await trash(items) }
    }

    /// Kandidati za ciscenje, racunaju se van glavne niti (veliko stablo).
    func loadCleanCandidates() async -> [CleanCandidate] {
        guard let tree else { return [] }
        return await Task.detached(priority: .userInitiated) { tree.cleanCandidates() }.value
    }

    // MARK: Akcije nad diskom

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func eject(_ place: Place) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: place.url)
            if selected == place { selected = nil; phase = .idle }
        } catch {
            alert = "Disk nije moguce izbaciti: \(error.localizedDescription)"
        }
    }

    func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Velicina ~/.Trash preko Rust skenera (nil ako nema dozvole, npr. bez Full Disk Access).
    nonisolated static func trashSize() async -> UInt64? {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        return await Task.detached(priority: .utility) { () -> UInt64? in
            guard let job = try? ScanJob(path: trash), let tree = try? job.run(), job.errors() == 0 else { return nil }
            return tree.info(id: tree.root())?.size
        }.value
    }

    /// Prazni Trash preko Finder-a (macOS jednom pita za dozvolu za Automation).
    func emptyTrash() {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error {
            alert = "Trash nije ispraznjen: \(error[NSAppleScript.errorMessage] ?? "nepoznata greska")"
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
