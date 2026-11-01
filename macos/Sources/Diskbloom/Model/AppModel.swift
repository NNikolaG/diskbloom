import DiskbloomFFI
import DiskbloomKit
import Foundation

/// App state. Rust owns the scanned tree; Swift only keeps what is on screen.
@MainActor
final class AppModel: ObservableObject {
    nonisolated static let rings: UInt32 = 6
    nonisolated static let minFraction = 0.003

    // MARK: Selection and scan
    @Published var selected: Place?
    @Published var phase: ScanPhase = .idle
    @Published private(set) var tree: DiskTree?
    /// The place `tree` belongs to, and when it was scanned.
    @Published private(set) var scannedPlace: Place?
    @Published private(set) var scannedAt: Date?
    /// Entries the scan could not read (no Full Disk Access).
    @Published private(set) var inaccessible: UInt64 = 0
    /// Used on the volume but not seen by the scan.
    @Published private(set) var hiddenSpace: UInt64 = 0
    @Published var refreshing = false

    // MARK: Navigation
    @Published var resultMode: ResultMode = .map
    @Published private(set) var focus: UInt32 = 0
    @Published private(set) var segments: [SegmentInfo] = []
    @Published private(set) var crumbs: [NodeInfo] = []
    @Published private(set) var children: [NodeInfo] = []
    /// Increases on every tree or focus change; views use it as `.task(id:)`.
    @Published private(set) var dataVersion = 0
    @Published var hovered: SegmentInfo?
    /// The last item under the pointer, for Quick Look with the space bar.
    @Published var lastHoveredID: UInt32?
    @Published var previewURL: URL?

    // MARK: Collector, cleanup, alerts
    @Published var collector: [CollectedItem] = []
    /// Moving to the Trash: items done and total; `nil` when idle.
    @Published var trashProgress: (done: Int, total: Int)?
    @Published var showCleaner = false
    /// Result of the last duplicate search; `nil` if none ran for this scan.
    @Published var dupeGroups: [DupGroupInfo]?
    @Published var alert: String?

    private var job: ScanJob?
    private var openCleanerAfterScan = false
    let launchOptions: LaunchOptions

    init(launchOptions: LaunchOptions = .current) {
        self.launchOptions = launchOptions
    }

    var focusInfo: NodeInfo? { tree?.info(id: focus) }
    var rootSize: UInt64 { tree.flatMap { $0.info(id: $0.root()) }?.size ?? 0 }

    /// Writable view of `alert` for `.alert(isPresented:)`.
    var isShowingAlert: Bool {
        get { alert != nil }
        set { if !newValue { alert = nil } }
    }

    // MARK: - Scanning

    /// A click in the sidebar shows the overview with actions; it does not scan yet.
    func select(_ place: Place) {
        if case .scanning = phase { cancelScan() }
        selected = place
        phase = (scannedPlace == place && tree != nil) ? .ready : .idle
    }

    /// Writable view of `selected` for the sidebar list.
    var sidebarSelection: Place? {
        get { selected }
        set { if let newValue { select(newValue) } }
    }

    func showOverview() { phase = .idle }

    func showResults() { if tree != nil { phase = .ready } }

    func scan(_ place: Place, clean: Bool = false) {
        selected = place
        startScan(of: place, clean: clean)
    }

    /// Scans a folder chosen with the open panel (keeps the sidebar entry if it is the same).
    func scan(_ url: URL) {
        scan(selected.flatMap { $0.url == url ? $0 : nil } ?? .folder(url))
    }

    private func startScan(of place: Place, clean: Bool) {
        cancelScan()
        let path = BootVolume.scanRoot(for: place.url)
        let job: ScanJob
        do {
            job = try ScanJob(path: path)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        self.job = job
        openCleanerAfterScan = clean
        tree = nil
        dupeGroups = nil
        resultMode = .map
        collector = []
        segments = []
        phase = .scanning(path: path, scanned: 0)

        // Progress: poll the Rust counter while the scan runs in the background.
        Task {
            while self.job === job, case .scanning = phase {
                phase = .scanning(path: path, scanned: job.scanned())
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try job.run() } }.value
            guard self.job === job else { return }
            switch result {
            case .success(let tree):
                finishScan(tree, of: place, job: job)
            case .failure(let error) where (error as? BloomError) == .Cancelled:
                phase = .idle
            case .failure(let error):
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func finishScan(_ tree: DiskTree, of place: Place, job: ScanJob) {
        self.tree = tree
        scannedPlace = place
        scannedAt = .now
        inaccessible = job.errors()
        hiddenSpace = BootVolume.hiddenSpace(of: place.url, seen: tree.info(id: tree.root())?.size ?? 0)
        phase = .ready
        zoom(to: tree.root())
        if openCleanerAfterScan { showCleaner = true }
        openCleanerAfterScan = false
        applyLaunchOptionsAfterScan()
    }

    func cancelScan() {
        job?.cancel()
        job = nil
        if case .scanning = phase { phase = .idle }
    }

    // MARK: - Navigation

    func zoom(to id: UInt32) {
        guard let tree else { return }
        dataVersion += 1
        focus = id
        hovered = nil
        segments = tree.layout(focus: id, rings: Self.rings, minFraction: Self.minFraction)
        crumbs = tree.ancestors(id: id)
        children = tree.children(id: id)
    }

    /// After the tree changed: stay on the focus if it still exists, else go to the root.
    func rezoom() {
        guard let tree else { return }
        zoom(to: tree.isAttached(id: focus) ? focus : tree.root())
    }

    func zoomOut() {
        if crumbs.count >= 2 { zoom(to: crumbs[crumbs.count - 2].id) }
    }

    func open(_ segment: SegmentInfo) {
        if let id = segment.id, segment.hasChildren { zoom(to: id) }
    }

    func path(_ id: UInt32) -> String { tree?.path(id: id) ?? "" }

    /// Quick Look for an item; calling it again closes the preview.
    func quickLook(_ id: UInt32?) {
        guard let id, tree != nil else { return }
        let url = URL(fileURLWithPath: path(id))
        previewURL = previewURL == url ? nil : url
    }

    /// Display name: the volume or folder name for the root instead of its full path.
    func title(_ node: NodeInfo) -> String {
        guard let tree, node.id == tree.root() else { return node.name }
        let path = tree.rootPath()
        if path == BootVolume.dataVolume || path == "/" { return BootVolume.name }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// Title of the scanned root, for "x% of Macintosh HD".
    var rootTitle: String { crumbs.first.map(title) ?? "" }

    // MARK: - Launch options (CI screenshots, quick tests)

    func applyLaunchOptions() {
        if let path = launchOptions.scanPath {
            scan(.folder(URL(fileURLWithPath: path)), clean: launchOptions.openCleaner)
        } else if launchOptions.showOverview {
            select(.bootVolume)
        }
    }

    private func applyLaunchOptionsAfterScan() {
        switch launchOptions.view {
        case .largest: resultMode = .largest
        case .duplicates: resultMode = .duplicates
        case nil: break
        }
        if launchOptions.demoCollector, let first = children.first { collect(first.id) }
    }
}
