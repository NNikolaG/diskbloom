import DiskbloomFFI
import DiskbloomKit
import Foundation

/// Smart Clean, folder refresh, and cleanup through developer tools.
extension AppModel {
    /// Rescans `id` (by default the focused folder) and swaps it into the tree.
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
                // Queued ids from the old subtree are gone.
                collector.removeAll { !tree.isAttached(id: $0.id) }
                zoom(to: wasFocus || !tree.isAttached(id: focus) ? newID : focus)
                persist()
            case .failure(let error):
                alert = String(localized: "Refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func refresh(path: String) {
        if let id = tree?.find(path: path) { refresh(id) }
    }

    /// Computed off the main thread; large trees can have tens of thousands of candidates.
    func loadCleanCandidates() async -> [CleanCandidate] {
        guard let tree else { return [] }
        return await Task.detached(priority: .userInitiated) { tree.cleanCandidates() }.value
    }

    /// Removes Smart Clean candidates, each with the right tool (see `CleanupMethod`).
    func clean(_ candidates: [CleanCandidate]) async {
        guard let tree else { return }
        var toTrash: [TrashMover.Item] = []
        var simulators: [(id: UInt32, udid: String)] = []
        var runtimes: [(id: UInt32, path: String)] = []
        for candidate in candidates {
            switch CleanupMethod.resolve(category: candidate.category, path: candidate.path) {
            case .trash:
                toTrash.append(.init(id: candidate.id, path: candidate.path))
            case .simulator(let udid):
                simulators.append((candidate.id, udid))
            case .simulatorRuntime(let path):
                runtimes.append((candidate.id, path))
            case .androidEmulator(let ini):
                toTrash.append(.init(id: candidate.id, path: candidate.path))
                if let iniID = tree.find(path: ini) { toTrash.append(.init(id: iniID, path: ini)) }
            case .emptyTrash:
                emptyTrash()
            case .docker, .skip:
                continue
            }
        }
        if !simulators.isEmpty { await deleteSimulators(simulators) }
        if !runtimes.isEmpty { await deleteSimulatorRuntimes(runtimes) }
        if !toTrash.isEmpty { await trash(toTrash) }
    }

    /// `xcrun simctl runtime delete <identifier>`, with the identifier that
    /// `simctl runtime list -j` gives for each image path. Images it does not list as
    /// deletable are left alone; nothing is ever moved to the Trash.
    private func deleteSimulatorRuntimes(_ runtimes: [(id: UInt32, path: String)]) async {
        guard let tree else { return }
        let list = await Shell.run(ToolLocations.xcrun, ["simctl", "runtime", "list", "-j"])
        guard list.succeeded else {
            alert = String(localized: "Could not list simulator runtimes (is Xcode installed?):\n\(list.output)")
            return
        }
        var failed: [String] = []
        var removed = false
        for runtime in runtimes {
            guard let identifier = SimulatorRuntimeList.identifier(forImageAt: runtime.path, in: list.output) else {
                failed.append(runtime.path)
                continue
            }
            let result = await Shell.run(ToolLocations.xcrun, ["simctl", "runtime", "delete", identifier])
            if result.succeeded {
                _ = tree.remove(id: runtime.id)
                removed = true
            } else {
                failed.append("\(runtime.path)\n\(result.output)")
            }
        }
        if removed { rezoom() }
        if !failed.isEmpty {
            let paths = failed.joined(separator: "\n")
            alert = String(localized: "Could not remove these simulator runtimes. Remove them in Xcode → Settings → Platforms:\n\(paths)")
        }
    }

    private func deleteSimulators(_ simulators: [(id: UInt32, udid: String)]) async {
        guard let tree else { return }
        let result = await Shell.run(ToolLocations.xcrun, ["simctl", "delete"] + simulators.map(\.udid))
        guard result.succeeded else {
            alert = String(localized: "Could not delete simulators (is Xcode installed?):\n\(result.output)")
            return
        }
        for simulator in simulators { _ = tree.remove(id: simulator.id) }
        rezoom()
        persist()
    }

    /// `xcrun simctl delete unavailable`: simulators whose iOS version is no longer installed.
    func deleteUnavailableSimulators() async -> Bool {
        let result = await Shell.run(ToolLocations.xcrun, ["simctl", "delete", "unavailable"])
        guard result.succeeded else {
            alert = String(localized: "Could not delete simulators (is Xcode installed?):\n\(result.output)")
            return false
        }
        refresh(path: NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices")
        return true
    }

    /// `docker system prune -af`: unused images, stopped containers and build cache.
    func dockerPrune() async -> Bool {
        guard let docker = ToolLocations.docker() else {
            alert = String(localized: "Docker command line tool not found. Open Docker Desktop and use Troubleshoot → Clean / Purge data.")
            return false
        }
        let result = await Shell.run(docker, ["system", "prune", "-af"])
        guard result.succeeded else {
            alert = String(localized: "docker system prune failed (is Docker running?):\n\(result.output)")
            return false
        }
        refresh(path: NSHomeDirectory() + "/Library/Containers/com.docker.docker/Data/vms")
        return true
    }

    // MARK: Time Machine local snapshots

    nonisolated static func localSnapshots() async -> [TimeMachineSnapshot] {
        let result = await Shell.run(ToolLocations.tmutil, ["listlocalsnapshots", "/"])
        return result.succeeded ? TimeMachineSnapshot.parse(result.output) : []
    }

    /// Deletes Time Machine snapshots; macOS asks for an administrator password.
    func deleteSnapshots(_ snapshots: [TimeMachineSnapshot]) -> Bool {
        guard let command = TimeMachineSnapshot.deleteCommand(for: snapshots) else { return false }
        let result = SystemActions.runAsAdministrator(command)
        if !result.succeeded { alert = String(localized: "Could not delete snapshots:\n\(result.output)") }
        return result.succeeded
    }
}
