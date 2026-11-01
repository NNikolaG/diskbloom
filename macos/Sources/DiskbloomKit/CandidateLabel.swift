import Foundation

/// Readable names for Smart Clean candidates.
public enum CandidateLabel {
    /// A simulator becomes "iPhone 15 Pro · iOS 17.2", an Android emulator "Pixel 8",
    /// anything else its path with `~` for the home folder.
    public static func make(category: String, path: String, home: String) -> String {
        switch category {
        case "simulators":
            if let name = simulatorName(at: path) { return name }
        case "android-emulators":
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
        default:
            break
        }
        return abbreviatingHome(path, home: home)
    }

    /// `/Users/me/x` → `~/x`.
    public static func abbreviatingHome(_ path: String, home: String) -> String {
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Name and runtime from the simulator's `device.plist`.
    static func simulatorName(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path + "/device.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["name"] as? String
        else { return nil }
        guard let runtime = (plist["runtime"] as? String).flatMap(runtimeName) else { return name }
        return "\(name) · \(runtime)"
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-17-2` → `iOS 17.2`.
    static func runtimeName(_ identifier: String) -> String? {
        guard let last = identifier.components(separatedBy: ".").last else { return nil }
        let parts = last.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return last }
        return "\(platform) " + parts.dropFirst().joined(separator: ".")
    }
}
