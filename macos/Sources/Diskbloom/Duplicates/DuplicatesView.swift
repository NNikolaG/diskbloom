import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// Duplicate files. Rust does the search: size, then a hash of the head, then a full hash.
struct DuplicatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var job: DupeJob?
    @State private var progress: (done: UInt64, total: UInt64) = (0, 0)
    @State private var minSize: UInt64 = 1_000_000
    /// Bytes each group would really free, accounting for APFS clones (keyed by the
    /// group's first file id). Missing while measuring or when the volume can't tell.
    @State private var reclaimable: [UInt32: UInt64] = [:]
    @State private var cloneTarget: DupGroupInfo?
    @State private var cloning = false

    private static let sizes: [UInt64] = [100_000, 1_000_000, 10_000_000, 100_000_000]

    /// Groups after deletions: only files still in the tree, only groups with two or more.
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
                    ForEach(Self.sizes, id: \.self) { Text(Format.bytes($0)).tag($0) }
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
            if model.launchOptions.view == .duplicates { run() }
        }
    }

    private var running: some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 320)
            Text("Comparing \(Format.count(progress.done)) of \(Format.count(progress.total)) files…")
                .foregroundStyle(.secondary).monospacedDigit()
            Button("Cancel") { job?.cancel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        let gs = groups
        let wasted = gs.reduce(UInt64(0)) { $0 + reclaim($1) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicates").font(.title3.bold())
                    Text("\(Format.count(gs.count)) groups · \(Format.bytes(wasted)) can be freed")
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
                        ForEach(gs, id: \.files.first?.id) { group($0) }
                    }
                    .padding(12)
                }
                Text("Sizes account for APFS clones: copies that already share disk space are not counted.")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        }
        .task(id: model.dupeGroups?.count) { await measureClones() }
        .confirmationDialog(
            "Replace \(Format.count((cloneTarget?.files.count ?? 1) - 1)) copies with clones?",
            isPresented: Binding(get: { cloneTarget != nil }, set: { if !$0 { cloneTarget = nil } }),
            presenting: cloneTarget
        ) { target in
            Button("Replace") { Task { await replaceWithClones(target) } }
        } message: { _ in
            Text("Every copy stays where it is, with its own name and dates, but the contents are stored only once. Editing one copy later does not change the others.")
        }
    }

    private func group(_ g: DupGroupInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(Format.count(g.files.count)) copies · \(Format.bytes(g.size)) each")
                    .font(.headline)
                Spacer()
                if reclaim(g) == 0 {
                    Label("Already share disk space (APFS clones)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Text("\(Format.bytes(reclaim(g))) wasted").foregroundStyle(.secondary).monospacedDigit()
                    Button("Replace with clones…") { cloneTarget = g }
                        .disabled(cloning)
                        .help("Keep all copies but store their contents once. Frees \(Format.bytes(reclaim(g))) without deleting anything.")
                }
                Button("Keep one") { keepOne(g) }
                    .help("Keep the first copy and add the others to the Trash list")
            }
            .padding(.horizontal, 12)
            ForEach(g.files, id: \.id) { f in FileRow(file: f) }
        }
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Keeps the copy with the shortest path (usually the original) and queues the others.
    private func keepOne(_ g: DupGroupInfo) {
        for f in Self.byOriginality(g.files).dropFirst() where !model.isCollected(f.id) { model.collect(f.id) }
    }

    /// Shortest path first: usually the original.
    private static func byOriginality(_ files: [FileInfo]) -> [FileInfo] {
        files.sorted { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
    }

    private func reclaim(_ g: DupGroupInfo) -> UInt64 {
        g.files.first.flatMap { reclaimable[$0.id] } ?? g.wasted
    }

    /// Asks APFS how much of each copy is really its own.
    private func measureClones() async {
        let all = model.dupeGroups ?? []
        reclaimable = await Task.detached(priority: .utility) {
            var result: [UInt32: UInt64] = [:]
            for g in all {
                guard let first = g.files.first else { continue }
                result[first.id] = APFSClones.reclaimable(g.files.map(\.path))
            }
            return result
        }.value
    }

    /// Turns every copy except the original into a clone of it.
    private func replaceWithClones(_ g: DupGroupInfo) async {
        let files = Self.byOriginality(g.files)
        guard let original = files.first else { return }
        cloning = true
        defer { cloning = false }
        let failures = await Task.detached(priority: .userInitiated) { () -> [String] in
            files.dropFirst().compactMap { copy -> String? in
                do {
                    try APFSClones.replaceWithClone(original: original.path, duplicate: copy.path)
                    return nil
                } catch {
                    let reason = (error as? APFSClones.ReplaceError) ?? .system(error.localizedDescription)
                    return "\(copy.path): \(Self.describe(reason))"
                }
            }
        }.value
        if !failures.isEmpty {
            model.alert = String(localized: "Some copies could not be replaced with clones:") + "\n" + failures.joined(separator: "\n")
        }
        await measureClones()
    }

    nonisolated private static func describe(_ error: APFSClones.ReplaceError) -> String {
        switch error {
        case .notRegularFiles: String(localized: "not a regular file")
        case .differentVolumes: String(localized: "on a different disk")
        case .hardLinked: String(localized: "has other hard links")
        case .contentsDiffer: String(localized: "contents changed since the search")
        case .system(let message): message
        }
    }

    private func run() {
        guard let tree = model.tree else { return }
        let job = DupeJob(tree: tree, minSize: minSize)
        self.job = job
        progress = (0, 0)
        Task {
            while self.job === job {
                progress = (job.progressDone(), job.progressTotal())
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try job.run() } }.value
            if case .success(let groups) = result { model.dupeGroups = groups }
            self.job = nil
        }
    }
}
