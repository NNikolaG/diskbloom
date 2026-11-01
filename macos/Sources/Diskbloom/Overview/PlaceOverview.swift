import DiskbloomKit
import SwiftUI

/// Overview of a disk or folder after it is selected in the sidebar: usage and actions.
struct PlaceOverview: View {
    @EnvironmentObject private var model: AppModel
    let place: Place

    @State private var capacity: VolumeCapacity?
    @State private var trashSize: UInt64?
    @State private var trashLoaded = false
    @State private var confirmEmptyTrash = false
    @State private var showSnapshots = false
    @State private var snapshotCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    actions
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: place) {
            capacity = VolumeCapacity(url: place.url)
            if place.isBootVolume {
                await loadSnapshotCount()
                trashLoaded = false
                trashSize = await AppModel.trashSize()
                trashLoaded = true
            }
        }
        .sheet(isPresented: $showSnapshots, onDismiss: {
            Task { await loadSnapshotCount() }
        }) {
            SnapshotsView().environmentObject(model)
        }
        .confirmationDialog("Permanently delete everything in the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) {
                model.emptyTrash()
                trashSize = 0
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: Header with the usage ring

    private var header: some View {
        HStack(alignment: .center, spacing: 28) {
            if let c = capacity, place.isVolume {
                UsageRing(used: Double(c.used) / Double(c.total),
                          purgeable: Double(c.purgeable) / Double(c.total))
                    .frame(width: 132, height: 132)
            } else {
                Image(systemName: place.icon)
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 132, height: 132)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(place.name).font(.largeTitle.bold())
                Text(place.url.path).foregroundStyle(.secondary).textSelection(.enabled)
                if let c = capacity, place.isVolume {
                    HStack(spacing: 18) {
                        stat("Used", Format.bytes(UInt64(c.used)), .accentColor)
                        if c.purgeable > 0 { stat("Purgeable", Format.bytes(UInt64(c.purgeable)), .orange) }
                        stat("Free", Format.bytes(UInt64(c.available)), .secondary)
                        stat("Total", Format.bytes(UInt64(c.total)), .secondary)
                    }
                    .padding(.top, 4)
                }
                if let at = model.scannedAt, model.scannedPlace == place {
                    Text("Last scanned: \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.monospacedDigit().weight(.medium))
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if model.scannedPlace == place, model.tree != nil {
            ActionCard(icon: "chart.pie", title: "Show map", subtitle: Text("Result of the last scan"), prominent: true) {
                model.showResults()
            }
        }
        ActionCard(icon: "magnifyingglass", title: place.isVolume ? "Scan disk" : "Scan folder",
                   subtitle: Text("Map of everything that takes up space"),
                   prominent: model.scannedPlace != place) {
            model.scan(place)
        }
        ActionCard(icon: "sparkles", title: "Smart Clean",
                   subtitle: Text("Build folders, caches, simulators, VMs…")) {
            model.scan(place, clean: true)
        }
        if place.isBootVolume {
            ActionCard(icon: "house", title: "Scan Home only", subtitle: Text("Faster, only your files")) {
                model.scan(.home)
            }
            ActionCard(icon: "clock.arrow.circlepath", title: "Time Machine snapshots", subtitle: snapshotSubtitle) {
                showSnapshots = true
            }
            ActionCard(icon: "trash", title: "Empty Trash", subtitle: trashSubtitle) {
                confirmEmptyTrash = true
            }
            ActionCard(icon: "internaldrive", title: "macOS Storage", subtitle: Text("System storage settings")) {
                model.openStorageSettings()
            }
            ActionCard(icon: "lock.open", title: "Full Disk Access", subtitle: Text("Permission to see the whole disk")) {
                model.openFullDiskAccessSettings()
            }
        }
        ActionCard(icon: "folder", title: "Show in Finder", subtitle: Text(verbatim: place.url.path)) {
            model.revealInFinder(url: place.url)
        }
        if capacity?.isEjectable == true {
            ActionCard(icon: "eject", title: "Eject disk", subtitle: Text("Safely remove this volume")) {
                model.eject(place)
            }
        }
    }

    private func loadSnapshotCount() async {
        snapshotCount = await AppModel.localSnapshots().filter(\.isTimeMachine).count
    }

    private var trashSubtitle: Text {
        if !trashLoaded { return Text("Calculating size…") }
        if let s = trashSize { return s == 0 ? Text("Trash is empty") : Text("Free \(Format.bytes(s))") }
        return Text("Size unknown (needs Full Disk Access)")
    }

    private var snapshotSubtitle: Text {
        guard let n = snapshotCount else { return Text("Checking…") }
        return n == 0 ? Text("No local snapshots") : Text("\(Format.count(n)) local snapshots")
    }
}
