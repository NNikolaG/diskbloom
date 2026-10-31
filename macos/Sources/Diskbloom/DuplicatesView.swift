import DiskbloomFFI
import SwiftUI

/// Duplikati: isti sadrzaj na vise mesta. Trazenje radi Rust (velicina -> hes pocetka -> pun hes).
struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    @State private var job: DupeJob?
    @State private var progress: (done: UInt64, total: UInt64) = (0, 0)
    @State private var minSize: UInt64 = 1_000_000

    private static let sizes: [UInt64] = [100_000, 1_000_000, 10_000_000, 100_000_000]

    /// Grupe posle brisanja: samo fajlovi koji su jos u stablu, i samo grupe sa 2+.
    private var groups: [DupGroupInfo] {
        guard let all = model.dupeGroups, let tree = model.tree else { return [] }
        return all.compactMap { g in
            let alive = g.files.filter { tree.isAttached(id: $0.id) }
            guard alive.count > 1 else { return nil }
            return DupGroupInfo(size: g.size, wasted: g.size * UInt64(alive.count - 1), files: alive)
        }
    }

    var body: some View {
        if job != nil {
            running
        } else if model.dupeGroups == nil {
            start
        } else {
            results
        }
    }

    private var start: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            Text("Find duplicate files").font(.title2.bold())
            Text("Files with identical content in different places. Only files that are the same size are read, so this is usually quick.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Text("Ignore files smaller than")
                Picker("", selection: $minSize) {
                    ForEach(Self.sizes, id: \.self) { Text(Fmt.bytes($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Button("Find duplicates") { run() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // CI screenshot: odmah pokreni pretragu
            if ProcessInfo.processInfo.environment["DISKBLOOM_MODE"] == "duplicates" { run() }
        }
    }

    private var running: some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 320)
            Text("Comparing \(Fmt.count(progress.done)) of \(Fmt.count(progress.total)) files…")
                .foregroundStyle(.secondary).monospacedDigit()
            Button("Cancel") { job?.cancel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        let gs = groups
        let wasted = gs.reduce(UInt64(0)) { $0 + $1.wasted }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicates").font(.title3.bold())
                    Text("\(Fmt.count(UInt64(gs.count))) groups · \(Fmt.bytes(wasted)) can be freed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Search again") { model.dupeGroups = nil }
            }
            .padding(16)
            Divider()
            if gs.isEmpty {
                ContentUnavailable(title: "No duplicates", message: "Every file here is unique.", symbol: "checkmark.seal")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(gs.enumerated()), id: \.offset) { _, g in group(g) }
                    }
                    .padding(12)
                }
                Text("Copies made with Finder's Duplicate on APFS can share disk space, so deleting them may free less than shown.")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        }
    }

    private func group(_ g: DupGroupInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(Fmt.count(UInt64(g.files.count))) copies · \(Fmt.bytes(g.size)) each")
                    .font(.headline)
                Spacer()
                Text("\(Fmt.bytes(g.wasted)) wasted").foregroundStyle(.secondary).monospacedDigit()
                Button("Keep one") { keepOne(g) }
                    .help("Keep the first copy and add the others to the Trash list")
            }
            .padding(.horizontal, 12)
            ForEach(g.files, id: \.id) { f in FileRow(file: f) }
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Zadrzi kopiju sa najkracom putanjom (obicno "original"), ostale u korpu.
    private func keepOne(_ g: DupGroupInfo) {
        let sorted = g.files.sorted { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
        for f in sorted.dropFirst() where !model.isCollected(f.id) { model.collect(f.id) }
    }

    private func run() {
        guard let tree = model.tree else { return }
        let job = DupeJob(tree: tree, minSize: minSize)
        self.job = job
        progress = (0, 0)
        Task {
            while self.job === job {
                progress = (job.progressDone(), job.progressTotal())
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try job.run() } }.value
            if case .success(let groups) = result { model.dupeGroups = groups }
            self.job = nil
        }
    }
}
