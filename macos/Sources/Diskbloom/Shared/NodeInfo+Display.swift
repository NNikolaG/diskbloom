import DiskbloomFFI

extension NodeInfo {
    /// Folders end with a slash.
    var displayName: String { isDir && !name.hasSuffix("/") ? name + "/" : name }
}
