import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// Smart Clean: build folders, caches, emulators, VMs… found by the Rust rules.
/// Simulators are deleted with `xcrun simctl`, Android emulators together with their
/// `.ini`, and the Docker disk is never deleted (`docker system prune` instead).
///
/// Stays fast with tens of thousands of candidates: grouping runs off the main thread,
/// categories start collapsed, and an open category shows at most `maxRows` items.
struct CleanerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// `nil` while loading.
    @State private var groups: [CleanGroup]?
    @State private var selected: Set<UInt32> = []
    @State private var expanded: Set<String> = []
    @State private var confirm = false
    @State private var confirmDocker = false
    @State private var working = false

    private static let maxRows = 100

    private var selectedSize: UInt64 {
        (groups ?? []).lazy.flatMap(\.items).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.candidate.size }
    }

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
        .confirmationDialog("Clean up \(Format.count(selected.count)) items (\(Format.bytes(selectedSize)))?",
                            isPresented: $confirm) {
            Button("Clean up", role: .destructive) { Task { await cleanSelected() } }
        } message: {
            Text("Files go to the Trash, so you can put them back. Simulators are deleted with Xcode's simctl.")
        }
        .confirmationDialog("Remove unused Docker data?", isPresented: $confirmDocker) {
            Button("Run docker system prune", role: .destructive) {
                run { await model.dockerPrune() }
            }
        } message: {
            Text("Deletes stopped containers, unused images, networks and build cache. Running containers and volumes are kept. Docker must be running.")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Clean").font(.title2.bold())
                if let groups {
                    let total = groups.reduce(0) { $0 + $1.size }
                    Text("Found \(Format.bytes(total)) in \(Format.count(groups.count)) categories")
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
            ForEach(groups) { group in
                groupRow(group)
                if expanded.contains(group.category) { groupItems(group) }
            }
        }
    }

    @ViewBuilder private func groupItems(_ group: CleanGroup) -> some View {
        if group.category == "simulators" {
            Button("Delete all unavailable simulators") {
                run { await model.deleteUnavailableSimulators() }
            }
            .help("Simulators for iOS versions that are no longer installed (xcrun simctl delete unavailable)")
            .padding(.leading, 58)
            .padding(.vertical, 4)
        }
        ForEach(group.items.prefix(Self.maxRows)) { itemRow($0) }
        if group.items.count > Self.maxRows {
            let rest = group.items.dropFirst(Self.maxRows)
            Text("… and \(Format.count(rest.count)) more (\(Format.bytes(rest.reduce(0) { $0 + $1.candidate.size }))). Checking the category includes them too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 58)
                .padding(.vertical, 4)
        }
    }

    private func groupRow(_ group: CleanGroup) -> some View {
        let info = CategoryInfo.meta(group.category)
        let ids = group.selectableIDs
        let count = ids.count(where: selected.contains)
        let state: CheckBox.State = count == 0 ? .off : count == ids.count ? .on : .mixed
        let tint = group.safe ? Color.accentColor : Color.orange
        let isExpanded = expanded.contains(group.category)
        return HStack(spacing: 12) {
            CheckBox(state: state) { setGroup(group, on: state != .on) }
            Image(systemName: info.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title).font(.body.weight(.medium))
                (Text(info.detail) + Text(verbatim: " · ") + Text("\(Format.count(group.items.count)) items"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Format.bytes(group.size)).monospacedDigit().fontWeight(.medium)
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { expanded.formSymmetricDifference([group.category]) }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private func itemRow(_ item: CleanGroup.Item) -> some View {
        HStack(spacing: 10) {
            if item.isSelectable {
                CheckBox(state: selected.contains(item.id) ? .on : .off) {
                    selected.formSymmetricDifference([item.id])
                }
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            Text(item.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.candidate.path)
            if item.method == .docker {
                Button("Clean up in Docker…") { confirmDocker = true }
                    .help("The Docker disk image must not be deleted while Docker uses it. This runs docker system prune instead.")
            }
            Text(Format.bytes(item.candidate.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            IconButton(symbol: "magnifyingglass", label: "Show in Finder") {
                model.revealInFinder(url: URL(fileURLWithPath: item.candidate.path))
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            if let progress = model.trashProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 180)
                Text("Moving to Trash… \(Format.count(progress.done))/\(Format.count(progress.total))")
                    .foregroundStyle(.secondary)
            } else if working {
                ProgressView().controlSize(.small)
            } else {
                Text("Selected: \(Format.count(selected.count)) · \(Format.bytes(selectedSize))").monospacedDigit()
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Clean up…") { confirm = true }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || model.trashProgress != nil || working)
        }
        .padding(16)
    }

    // MARK: Logic

    private func reload() async {
        groups = nil
        let candidates = await model.loadCleanCandidates()
        groups = await Task.detached(priority: .userInitiated) { CleanGroup.make(from: candidates) }.value
        selectSafe()
    }

    /// Runs a tool action and reloads the candidates if it succeeded.
    private func run(_ action: @escaping () async -> Bool) {
        Task {
            working = true
            if await action() { await reload() }
            working = false
        }
    }

    private func selectSafe() {
        selected = Set((groups ?? []).filter(\.safe).flatMap(\.selectableIDs))
    }

    private func setGroup(_ group: CleanGroup, on: Bool) {
        if on { selected.formUnion(group.selectableIDs) } else { selected.subtract(group.selectableIDs) }
    }

    private func cleanSelected() async {
        let candidates = (groups ?? []).flatMap(\.items)
            .filter { selected.contains($0.id) && $0.isSelectable }
            .map(\.candidate)
        await model.clean(candidates)
        await reload()
    }
}
