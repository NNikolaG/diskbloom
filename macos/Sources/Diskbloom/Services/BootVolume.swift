import Foundation

/// The startup disk. Since Catalina `/` is a sealed system volume and user data lives on
/// the data volume, joined by firmlinks. The scanner never crosses volumes, so the boot
/// disk is scanned through the data volume directly.
enum BootVolume {
    static let dataVolume = "/System/Volumes/Data"

    /// The path to scan for a sidebar place.
    static func scanRoot(for url: URL) -> String {
        if url.path == "/", FileManager.default.fileExists(atPath: dataVolume) { return dataVolume }
        return url.path
    }

    /// "Macintosh HD" or whatever the user named it.
    static var name: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
    }

    /// Used on the volume minus what the scan saw (`seen` bytes): system volume,
    /// snapshots, folders without permission. Zero when `url` is not a whole volume.
    static func hiddenSpace(of url: URL, seen: UInt64) -> UInt64 {
        guard let capacity = VolumeCapacity(url: url), capacity.isVolumeRoot || url.path == "/" else { return 0 }
        let used = UInt64(capacity.used)
        return used > seen ? used - seen : 0
    }
}
