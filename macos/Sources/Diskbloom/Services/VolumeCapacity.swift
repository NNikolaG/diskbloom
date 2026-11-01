import Foundation

/// Space on the volume that holds a URL.
struct VolumeCapacity {
    let total: Int64
    /// Really free.
    let available: Int64
    /// Free plus purgeable, as Finder shows it.
    let availableForImportantUsage: Int64
    let isEjectable: Bool
    /// Whether the URL is the volume's mount point.
    let isVolumeRoot: Bool

    var used: Int64 { max(0, total - availableForImportantUsage) }
    var purgeable: Int64 { max(0, availableForImportantUsage - available) }

    init?(url: URL) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeURLKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        self.total = Int64(total)
        available = Int64(values.volumeAvailableCapacity ?? 0)
        availableForImportantUsage = max(available, values.volumeAvailableCapacityForImportantUsage ?? available)
        isEjectable = url.path != "/" && (values.volumeIsEjectable == true || values.volumeIsRemovable == true)
        isVolumeRoot = values.volume?.standardizedFileURL == url.standardizedFileURL
    }
}
