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

    /// Prikaz rezultata: mapa, najveci fajlovi ili duplikati.
    enum ResultMode: String, CaseIterable, Identifiable {
        case map, largest, duplicates
        var id: String { rawValue }
    }
    @Published var resultMode: ResultMode = .map
    /// Fajl za Quick Look (razmaknica ili dugme "oko").
    @Published var previewURL: URL?
    /// Poslednja stavka nad kojom je bio mis (za razmaknicu = Quick Look).
    @Published var lastHoveredID: UInt32?
    @Published var refreshing = false
    /// Rezultat poslednje pretrage duplikata (nil = nije pokretana za ovo skeniranje).
    @Published var dupeGroups: [DupGroupInfo]?
    /// Raste pri svakoj promeni stabla/fokusa; pogledi ga koriste kao `.task(id:)`.
    @Published private(set) var dataVersion = 0

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
        dupeGroups = nil
        resultMode = .map
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
                    // CI screenshot-ovi: izabrani prikaz
                    switch ProcessInfo.processInfo.environment["DISKBLOOM_MODE"] {
                    case "largest": self.resultMode = .largest
                    case "duplicates": self.resultMode = .duplicates
                    default: break
                    }
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
        dataVersion += 1
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

    /// Quick Look za stavku (razmaknica ili dugme "oko"); ponovni poziv zatvara pregled.
    func quickLook(_ id: UInt32?) {
        guard let id, tree != nil else { return }
        let url = URL(fileURLWithPath: path(id))
        previewURL = previewURL == url ? nil : url
    }

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
        var firstError: String?   // greska grupe (NSWorkspace.recycle)
        var itemError: String?    // prva greska pojedinacne stavke (FileManager.trashItem)
        var done = 0
        let chunkSize = 200
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let chunk = items[start..<min(start + chunkSize, items.count)]
            let (moved, error) = await recycle(chunk.map { URL(fileURLWithPath: $0.path) })
            let movedPaths = Set(moved.keys.map { $0.standardizedFileURL.path })
            var retry: [(id: UInt32, path: String)] = []
            for item in chunk {
                if movedPaths.contains(URL(fileURLWithPath: item.path).standardizedFileURL.path) {
                    freed += tree.remove(id: item.id)
                } else {
                    retry.append(item)
                }
            }
            if let error, firstError == nil { firstError = Self.describe(error) }
            // Drugi pokusaj direktno (FileManager.trashItem), van glavne niti;
            // daje i tacnu gresku po stavci ako ni to ne uspe.
            if !retry.isEmpty {
                let toRetry = retry
                let results = await Task.detached(priority: .userInitiated) { () -> [(Int, String?)] in
                    let fm = FileManager()
                    return toRetry.enumerated().map { i, item in
                        do {
                            try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                            return (i, nil)
                        } catch {
                            return (i, AppModel.describe(error))
                        }
                    }
                }.value
                for (i, err) in results {
                    if let err {
                        failed.append(retry[i].path)
                        if itemError == nil { itemError = err }
                    } else {
                        freed += tree.remove(id: retry[i].id)
                    }
                }
            }
            done += chunk.count
            trashProgress = (done, items.count)
        }
        if !failed.isEmpty {
            let shown = failed.prefix(8).joined(separator: "\n")
            alert = String(localized: "Could not move \(Fmt.count(UInt64(failed.count))) items to the Trash:") + "\n" + shown + (failed.count > 8 ? "\n…" : "")
                + ((itemError ?? firstError).map { "\n\n" + $0 } ?? "")
        }
        // iz korpe izlaze samo obrisane stavke; neuspele ostaju da mogu ponovo
        let failedSet = Set(failed)
        let removed = Set(items.filter { !failedSet.contains($0.path) }.map(\.id))
        collector.removeAll { removed.contains($0.id) }
        // ako je fokus obrisan, vrati se na prvog postojeceg pretka
        let alive = tree.ancestors(id: focus).first?.id == tree.root()
        zoom(to: alive ? focus : tree.root())
        return freed
    }

    /// Greska sa domenom/kodom i uzrokom, da bi se iz poruke videlo sta je macOS odbio.
    nonisolated static func describe(_ error: Error) -> String {
        let e = error as NSError
        var text = "\(e.localizedDescription) [\(e.domain) \(e.code)]"
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += "\n← \(u.localizedDescription) [\(u.domain) \(u.code)]"
        }
        return text
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
            alert = String(localized: "Could not eject the disk: \(error.localizedDescription)")
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
            alert = String(localized: "Could not empty the Trash: \(String(describing: error[NSAppleScript.errorMessage] ?? "?"))")
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
