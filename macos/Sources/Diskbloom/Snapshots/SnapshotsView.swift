import DiskbloomKit
import SwiftUI

/// Local Time Machine snapshots, often the largest part of "purgeable" and hidden space.
/// macOS removes them only when space runs out; here they can go right away.
struct SnapshotsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [TimeMachineSnapshot]?
    @State private var selected: Set<String> = []
    @State private var working = false

    private var deletable: [TimeMachineSnapshot] { (snapshots ?? []).filter(\.isTimeMachine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Time Machine local snapshots").font(.title2.bold())
                Text("Time Machine keeps hourly snapshots on this disk while your backup drive is away. macOS frees them when space runs low, but they often hold tens of gigabytes. Your backups on the Time Machine drive are not affected.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            if let snapshots {
                if snapshots.isEmpty {
                    ContentUnavailable(title: "No local snapshots", message: "There is nothing to remove.",
                                       symbol: "clock.arrow.circlepath")
                } else {
                    List(snapshots) { s in row(s) }
                        .listStyle(.inset)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete selected…") { delete(deletable.filter { selected.contains($0.id) }) }
                    .disabled(selected.isEmpty || working)
                Button("Delete all") { delete(deletable) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(deletable.isEmpty || working)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await reload() }
    }

    private func row(_ s: TimeMachineSnapshot) -> some View {
        HStack {
            if s.isTimeMachine {
                CheckBox(state: selected.contains(s.id) ? .on : .off) {
                    if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
                }
            } else {
                Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let d = s.date {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text(s.name)
                }
                Text(s.isTimeMachine ? String(localized: "Time Machine") : String(localized: "System snapshot, managed by macOS"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func delete(_ snaps: [TimeMachineSnapshot]) {
        guard !snaps.isEmpty else { return }
        working = true
        Task {
            _ = model.deleteSnapshots(snaps)
            working = false
            selected = []
            await reload()
        }
    }

    private func reload() async {
        snapshots = await AppModel.localSnapshots()
    }
}
