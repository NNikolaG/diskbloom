import Foundation

/// Free and total space of a mounted volume, for the menu bar. Free space includes
/// purgeable space, as in Finder and the disk overview (`VolumeCapacity`).
struct VolumeUsage: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64

    var id: URL { url }
    var isBoot: Bool { url.path == "/" }
    var icon: String { isBoot ? "internaldrive" : "externaldrive" }
    var place: Place { Place(url: url, name: name, icon: icon, isVolume: true) }
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }

    /// Every visible mounted volume, the startup disk first. Only reads volume keys of
    /// `URLResourceValues`, so it is cheap enough to call every minute.
    static func mounted() -> [VolumeUsage] {
        let volumes = MountedVolume.all().compactMap { volume -> VolumeUsage? in
            guard let capacity = VolumeCapacity(url: volume.url) else { return nil }
            return VolumeUsage(url: volume.url, name: volume.name, total: capacity.total,
                               free: capacity.availableForImportantUsage)
        }
        return volumes.filter(\.isBoot) + volumes.filter { !$0.isBoot }
    }
}
