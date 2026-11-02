import Foundation

/// A mounted volume for the sidebar.
struct MountedVolume: Identifiable {
    let url: URL
    let name: String
    let total: Int
    let free: Int
    let isEjectable: Bool

    var id: URL { url }
    var isBoot: Bool { url.path == "/" }
    var icon: String { isBoot ? "internaldrive" : "externaldrive" }
    var place: Place { Place(url: url, name: name, icon: icon, isVolume: true) }
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }

    static func all() -> [MountedVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            return MountedVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                total: total,
                // Purgeable space counts as free, as in Finder and the menu bar.
                free: Int(clamping: values.volumeAvailableCapacityForImportantUsage
                    ?? Int64(values.volumeAvailableCapacity ?? 0)),
                isEjectable: url.path != "/" && (values.volumeIsEjectable == true || values.volumeIsRemovable == true)
            )
        }
    }
}
