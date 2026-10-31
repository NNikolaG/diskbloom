import AppKit
import DiskbloomFFI
import Foundation

// MARK: - Osvezavanje, posebno brisanje, Time Machine snapshot-i

extension AppModel {
    // MARK: Osvezi samo ovaj folder

    /// Ponovo skenira `id` (podrazumevano trenutni folder) i ubacuje ga u stablo.
    func refresh(_ id: UInt32? = nil) {
        guard let tree, !refreshing else { return }
        let target = id ?? focus
        let wasFocus = target == focus
        refreshing = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try tree.rescan(id: target) } }.value
            refreshing = false
            switch result {
            case .success(let newID):
                // kolektor drzi ID-jeve iz starog podstabla
                collector.removeAll { !tree.isAttached(id: $0.id) }
                zoom(to: wasFocus ? newID : (tree.isAttached(id: focus) ? focus : newID))
            case .failure(let e):
                alert = String(localized: "Refresh failed: \(e.localizedDescription)")
            }
        }
    }

    // MARK: Brisanje koje zahteva pravi alat

    /// Bira kako se stavka brise. Vecina ide u Trash; neke stvari imaju svoj alat.
    enum CleanupMethod {
        case trash
        /// `xcrun simctl delete <UDID>` da Xcode zna da uredjaj vise ne postoji.
        case simulator(udid: String)
        /// Trash za `.avd` folder i pripadajuci `.ini` (inace Android Studio vidi pokvaren uredjaj).
        case androidAVD
        /// Docker disk se ne brise; prazni se kroz `docker system prune`.
        case docker
    }

    nonisolated static func cleanupMethod(category: String, path: String) -> CleanupMethod {
        if category == "simulators" { return .simulator(udid: URL(fileURLWithPath: path).lastPathComponent) }
        if category == "android-emulators" { return .androidAVD }
        if path.contains("/com.docker.docker/") { return .docker }
        return .trash
    }

    /// Brise kandidate Smart Clean-a odgovarajucim alatom. Docker stavke se preskacu.
    func clean(_ items: [CleanCandidate]) async {
        guard let tree else { return }
        var trash: [(id: UInt32, path: String)] = []
        var sims: [CleanCandidate] = []
        for c in items {
            switch Self.cleanupMethod(category: c.category, path: c.path) {
            case .trash: trash.append((id: c.id, path: c.path))
            case .simulator: sims.append(c)
            case .androidAVD:
                trash.append((id: c.id, path: c.path))
                // Pixel_8.avd -> Pixel_8.ini pored njega (mali fajl, nije u stablu kao kandidat)
                let ini = URL(fileURLWithPath: c.path).deletingPathExtension().appendingPathExtension("ini").path
                if let iniID = tree.find(path: ini) { trash.append((id: iniID, path: ini)) }
            case .docker: continue
            }
        }
        if !sims.isEmpty { await deleteSimulators(sims) }
        if !trash.isEmpty { await self.trash(trash) }
    }

    private func deleteSimulators(_ sims: [CleanCandidate]) async {
        guard let tree else { return }
        let udids = sims.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let r = await Shell.run("/usr/bin/xcrun", ["simctl", "delete"] + udids)
        if r.ok {
            for s in sims { tree.remove(id: s.id) }
            zoom(to: tree.isAttached(id: focus) ? focus : tree.root())
        } else {
            alert = String(localized: "Could not delete simulators (is Xcode installed?):\n\(r.output)")
        }
    }

    /// `xcrun simctl delete unavailable`: simulatori za koje Xcode vise nema iOS verziju.
    func deleteUnavailableSimulators() async -> Bool {
        let r = await Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
        if !r.ok {
            alert = String(localized: "Could not delete simulators (is Xcode installed?):\n\(r.output)")
            return false
        }
        refreshFolder(FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/CoreSimulator/Devices")
        return true
    }

    /// `docker system prune -af`: brise nekoriscene image-e, kontejnere i build kes.
    func dockerPrune() async -> Bool {
        guard let docker = Shell.docker else {
            alert = String(localized: "Docker command line tool not found. Open Docker Desktop and use Troubleshoot → Clean / Purge data.")
            return false
        }
        let r = await Shell.run(docker, ["system", "prune", "-af"])
        if !r.ok {
            alert = String(localized: "docker system prune failed (is Docker running?):\n\(r.output)")
            return false
        }
        refreshFolder(FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Containers/com.docker.docker/Data/vms")
        return true
    }

    private func refreshFolder(_ path: String) {
        if let id = tree?.find(path: path) { refresh(id) }
    }

    // MARK: Time Machine lokalni snapshot-i

    struct Snapshot: Identifiable, Hashable {
        let name: String          // com.apple.TimeMachine.2026-10-31-101500.local
        let date: Date?
        var id: String { name }
        var isTimeMachine: Bool { name.hasPrefix("com.apple.TimeMachine.") }
        /// "2026-10-31-101500", argument za tmutil deletelocalsnapshots
        var stamp: String? {
            guard isTimeMachine else { return nil }
            return name.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                .replacingOccurrences(of: ".local", with: "")
        }
    }

    nonisolated static func localSnapshots() async -> [Snapshot] {
        let r = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        guard r.ok else { return [] }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return r.output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
            .map { name in
                let stamp = name.components(separatedBy: ".").dropFirst(3).first ?? ""
                return Snapshot(name: name, date: fmt.date(from: stamp))
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Brise Time Machine snapshot-e (macOS trazi administratorsku lozinku).
    func deleteSnapshots(_ snaps: [Snapshot]) async -> Bool {
        let stamps = snaps.compactMap(\.stamp)
        guard !stamps.isEmpty else { return false }
        let cmd = stamps.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: " && ")
        let r = await Shell.runAsAdmin(cmd)
        if !r.ok { alert = String(localized: "Could not delete snapshots:\n\(r.output)") }
        return r.ok
    }
}
