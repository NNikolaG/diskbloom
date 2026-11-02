import Foundation

/// Simulator runtimes as listed by `xcrun simctl runtime list -j`.
///
/// Runtime images live in `/Library/Developer/CoreSimulator` (`Images/<uuid>.dmg` since
/// Xcode 15, `Cryptex/Images/bundle/SimRuntimeBundle-<uuid>` since Xcode 16). The UUID
/// in the file name is not always the runtime identifier, so the identifier for
/// `simctl runtime delete` is taken from simctl's own list, matched by the image path.
public enum SimulatorRuntimeList {
    /// The folders Smart Clean offers runtime images from.
    static let imageFolders = [
        "/Library/Developer/CoreSimulator/Images/",
        "/Library/Developer/CoreSimulator/Cryptex/Images/bundle/",
    ]

    /// Whether `path` is directly inside one of the runtime image folders.
    public static func isImageLocation(_ path: String) -> Bool {
        let path = normalized(path)
        return imageFolders.contains { folder in
            guard path.hasPrefix(folder) else { return false }
            let name = path.dropFirst(folder.count)
            return !name.isEmpty && name != "." && name != ".." && !name.contains("/")
        }
    }

    /// The identifier to pass to `xcrun simctl runtime delete` for the image at `path`,
    /// from `output` of `xcrun simctl runtime list -j`. `nil` unless exactly one listed
    /// runtime lives at (or inside) `path`, simctl marks it deletable, and its
    /// identifier is a UUID (never a word such as "all").
    public static func identifier(forImageAt path: String, in output: String) -> String? {
        guard isImageLocation(path), let entries = parse(output) else { return nil }
        let path = normalized(path)
        let matches = entries.filter { entry in
            guard let entryPath = entry.path.map(normalized) else { return false }
            return entryPath == path || entryPath.hasPrefix(path + "/")
        }
        guard matches.count == 1, let entry = matches.first, entry.deletable == true,
              let identifier = entry.identifier, CleanupMethod.isSimulatorUDID(identifier)
        else { return nil }
        return identifier
    }

    struct Entry: Decodable {
        let identifier: String?
        let path: String?
        let deletable: Bool?
    }

    /// The runtimes in simctl's JSON (a dictionary keyed by UUID). The shell output
    /// also carries stderr, so only the part from the first `{` to the last `}` is read.
    static func parse(_ output: String) -> [Entry]? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else { return nil }
        let json = Data(output[start...end].utf8)
        return (try? JSONDecoder().decode([String: Entry].self, from: json)).map { Array($0.values) }
    }

    /// The firmlinked form without a trailing slash: `/System/Volumes/Data/Library/x/`
    /// → `/Library/x`.
    static func normalized(_ path: String) -> String {
        var path = path
        let dataVolume = "/System/Volumes/Data"
        if path.hasPrefix(dataVolume + "/") { path.removeFirst(dataVolume.count) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
