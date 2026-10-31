import AppKit
import DiskbloomFFI
import SwiftUI

/// Pregled diska/foldera posle klika u sidebar-u: zauzece + akcije.
struct PlaceOverview: View {
    @EnvironmentObject var model: AppModel
    let place: AppModel.Place

    @State private var capacity: Capacity?
    @State private var trashSize: UInt64?
    @State private var trashLoaded = false
    @State private var confirmEmptyTrash = false
    @State private var showSnapshots = false
    @State private var snapshotCount: Int?

    struct Capacity {
        let total: Int64
        let available: Int64      // stvarno slobodno
        let important: Int64      // slobodno + purgeable (kao Finder)
        let ejectable: Bool
        var used: Int64 { max(0, total - important) }
        var purgeable: Int64 { max(0, important - available) }

        init?(url: URL) {
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                             .volumeAvailableCapacityForImportantUsageKey,
                                             .volumeIsEjectableKey, .volumeIsRemovableKey]
            guard let v = try? url.resourceValues(forKeys: keys), let t = v.volumeTotalCapacity, t > 0 else { return nil }
            total = Int64(t)
            available = Int64(v.volumeAvailableCapacity ?? 0)
            important = max(available, v.volumeAvailableCapacityForImportantUsage ?? available)
            ejectable = url.path != "/" && (v.volumeIsEjectable == true || v.volumeIsRemovable == true)
        }
    }

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
            capacity = Capacity(url: place.url)
            if place.isBootVolume {
                snapshotCount = await AppModel.localSnapshots().filter(\.isTimeMachine).count
                trashLoaded = false
                trashSize = await AppModel.trashSize()
                trashLoaded = true
            }
        }
        .sheet(isPresented: $showSnapshots, onDismiss: {
            Task { snapshotCount = await AppModel.localSnapshots().filter(\.isTimeMachine).count }
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

    // MARK: Zaglavlje sa prstenom zauzeca

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
                        stat("Used", Fmt.bytes(UInt64(c.used)), .accentColor)
                        if c.purgeable > 0 { stat("Purgeable", Fmt.bytes(UInt64(c.purgeable)), .orange) }
                        stat("Free", Fmt.bytes(UInt64(c.available)), .secondary)
                        stat("Total", Fmt.bytes(UInt64(c.total)), .secondary)
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

    // MARK: Akcije

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
                model.scan(.folder(FileManager.default.homeDirectoryForCurrentUser, name: "Home", icon: "house"))
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
        if capacity?.ejectable == true {
            ActionCard(icon: "eject", title: "Eject disk", subtitle: Text("Safely remove this volume")) {
                model.eject(place)
            }
        }
    }

    private var trashSubtitle: Text {
        if !trashLoaded { return Text("Calculating size…") }
        if let s = trashSize { return s == 0 ? Text("Trash is empty") : Text("Free \(Fmt.bytes(s))") }
        return Text("Size unknown (needs Full Disk Access)")
    }

    private var snapshotSubtitle: Text {
        guard let n = snapshotCount else { return Text("Checking…") }
        return n == 0 ? Text("No local snapshots") : Text("\(Fmt.count(UInt64(n))) local snapshots")
    }
}

/// Kartica akcije u mrezi.
struct ActionCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: Text
    var prominent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(prominent ? Color.white : Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    subtitle.font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(hover ? 0.07 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(prominent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Prsten zauzeca diska: zauzeto (accent) + purgeable (narandzasto).
struct UsageRing: View {
    let used: Double
    let purgeable: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle().trim(from: 0, to: used)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if purgeable > 0.002 {
                Circle().trim(from: used, to: min(1, used + purgeable))
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(Int((used * 100).rounded()))%").font(.title.bold().monospacedDigit())
                Text("used").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
