import Foundation

/// How a Smart Clean candidate is removed. Most go to the Trash; some need their own tool.
public enum CleanupMethod: Equatable, Sendable {
    case trash
    /// `xcrun simctl delete <UDID>`, so Xcode forgets the device too.
    case simulator(udid: String)
    /// The `.avd` folder together with the `.ini` next to it; otherwise Android Studio
    /// shows a broken device.
    case androidEmulator(ini: String)
    /// The Docker disk image must not be deleted while Docker uses it; offer
    /// `docker system prune` instead.
    case docker
    /// `~/.Trash` is emptied, not moved to the Trash.
    case emptyTrash
    /// A simulator runtime image, removed with `xcrun simctl runtime delete`. Its
    /// identifier is looked up with `SimulatorRuntimeList` right before deleting;
    /// never moved to the Trash.
    case simulatorRuntime(path: String)
    /// Cannot be removed safely (a simulator folder that is not a device UUID).
    case skip

    /// Picks the method for a candidate from the Rust category id and its path.
    public static func resolve(category: String, path: String) -> CleanupMethod {
        let url = URL(fileURLWithPath: path)
        switch category {
        case "simulators":
            let udid = url.lastPathComponent
            return isSimulatorUDID(udid) ? .simulator(udid: udid) : .skip
        case "android-emulators":
            return .androidEmulator(ini: url.deletingPathExtension().appendingPathExtension("ini").path)
        case "trash":
            return .emptyTrash
        case "sim-runtimes":
            return SimulatorRuntimeList.isImageLocation(path) ? .simulatorRuntime(path: path) : .skip
        default:
            return path.contains("/com.docker.docker/") ? .docker : .trash
        }
    }

    /// Only real device UUIDs. The folder name is passed to `simctl delete`, where a
    /// folder called "all" would otherwise delete every simulator.
    public static func isSimulatorUDID(_ name: String) -> Bool {
        name.range(of: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
                   options: .regularExpression) != nil
    }
}
