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
                trashLoaded = false
                trashSize = await AppModel.trashSize()
                trashLoaded = true
            }
        }
        .confirmationDialog("Trajno obrisati sve iz Trash-a?", isPresented: $confirmEmptyTrash) {
            Button("Isprazni Trash", role: .destructive) {
                model.emptyTrash()
                trashSize = 0
            }
        } message: {
            Text("Ovo se ne moze vratiti.")
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
                        stat("Zauzeto", Fmt.bytes(UInt64(c.used)), .accentColor)
                        if c.purgeable > 0 { stat("Purgeable", Fmt.bytes(UInt64(c.purgeable)), .orange) }
                        stat("Slobodno", Fmt.bytes(UInt64(c.available)), .secondary)
                        stat("Ukupno", Fmt.bytes(UInt64(c.total)), .secondary)
                    }
                    .padding(.top, 4)
                }
                if let at = model.scannedAt, model.scannedPlace == place {
                    Text("Poslednje skeniranje: \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
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
            ActionCard(icon: "chart.pie", title: "Prikazi mapu", subtitle: "Rezultat poslednjeg skeniranja", prominent: true) {
                model.showResults()
            }
        }
        ActionCard(icon: "magnifyingglass", title: place.isVolume ? "Skeniraj disk" : "Skeniraj folder",
                   subtitle: "Mapa svega sto zauzima prostor",
                   prominent: model.scannedPlace != place) {
            model.scan(place)
        }
        ActionCard(icon: "sparkles", title: "Smart Clean",
                   subtitle: "Build folderi, kesevi, node_modules…") {
            model.scan(place, clean: true)
        }
        if place.isBootVolume {
            ActionCard(icon: "house", title: "Skeniraj samo Home", subtitle: "Brze, samo tvoji fajlovi") {
                model.scan(.folder(FileManager.default.homeDirectoryForCurrentUser, name: "Home", icon: "house"))
            }
            ActionCard(icon: "trash", title: "Isprazni Trash", subtitle: trashSubtitle) {
                confirmEmptyTrash = true
            }
            ActionCard(icon: "internaldrive", title: "macOS Storage", subtitle: "Sistemska podesavanja skladista") {
                model.openStorageSettings()
            }
            ActionCard(icon: "lock.open", title: "Full Disk Access", subtitle: "Dozvola za potpun pregled") {
                model.openFullDiskAccessSettings()
            }
        }
        ActionCard(icon: "folder", title: "Prikazi u Finder-u", subtitle: place.url.path) {
            model.revealInFinder(url: place.url)
        }
        if capacity?.ejectable == true {
            ActionCard(icon: "eject", title: "Izbaci disk", subtitle: "Bezbedno ukloni volumen") {
                model.eject(place)
            }
        }
    }

    private var trashSubtitle: String {
        if !trashLoaded { return "Racunam velicinu…" }
        if let s = trashSize { return s == 0 ? "Trash je prazan" : "Oslobodi \(Fmt.bytes(s))" }
        return "Velicina nepoznata (treba Full Disk Access)"
    }
}

/// Kartica akcije u mrezi.
struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
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
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
                Text("zauzeto").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
