#if canImport(Darwin)
import Darwin
import Foundation

/// APFS copy-on-write clones. A file made with Finder's Duplicate (or `cp -c`) shares its
/// blocks with the original until one of them changes, so deleting it frees little or
/// nothing. macOS reports, per file, how much of it is *private* (not shared).
public enum APFSClones {
    /// Sharing information for one file.
    public struct Info: Equatable, Sendable {
        /// Bytes only this file uses; deleting the file frees about this much.
        public let privateSize: UInt64
        /// Files with the same non-zero id were cloned from each other.
        public let cloneID: UInt64
    }

    /// Reads the private size and clone id of a regular file (not following symlinks).
    /// `nil` when the volume does not report them (not APFS, or an old macOS).
    public static func info(path: String) -> Info? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        // With FSOPT_ATTR_CMN_EXTENDED the fork group carries the "common extended" attributes.
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID)
        let options = UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)

        // u_int32_t length, attribute_set_t returned, off_t private size, u_int64_t clone id
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, options)
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> Info? in
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            var offset = 4 + MemoryLayout<attribute_set_t>.size
            var privateSize: UInt64?
            var cloneID: UInt64 = 0
            if returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 {
                privateSize = UInt64(max(0, raw.loadUnaligned(fromByteOffset: offset, as: off_t.self)))
                offset += MemoryLayout<off_t>.size
            }
            if returned.forkattr & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0 {
                cloneID = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            }
            return privateSize.map { Info(privateSize: $0, cloneID: cloneID) }
        }
    }

    /// Bytes deleting all but one of `files` would really free: the private sizes of
    /// all copies minus the largest (the copy that stays). `nil` if unknown for any file.
    public static func reclaimable(_ files: [String]) -> UInt64? {
        let sizes = files.map { info(path: $0)?.privateSize }
        guard !sizes.isEmpty, sizes.allSatisfy({ $0 != nil }) else { return nil }
        let values = sizes.compactMap { $0 }
        return values.reduce(0, +) - (values.max() ?? 0)
    }

    public enum ReplaceError: Error, Equatable {
        case notRegularFiles
        case differentVolumes
        case hardLinked
        case contentsDiffer
        case system(String)
    }

    /// Replaces `duplicate` with a clone of `original`, keeping the duplicate's name,
    /// permissions, dates and extended attributes. The two files must have identical
    /// contents; this is checked byte by byte first. The swap is atomic (`rename`), so
    /// the duplicate is never missing or half-written.
    public static func replaceWithClone(original: String, duplicate: String) throws(ReplaceError) {
        var a = stat(), b = stat()
        guard lstat(original, &a) == 0, lstat(duplicate, &b) == 0,
              a.st_mode & S_IFMT == S_IFREG, b.st_mode & S_IFMT == S_IFREG
        else { throw .notRegularFiles }
        guard a.st_dev == b.st_dev else { throw .differentVolumes }
        // Replacing one name of a hard-linked file would silently split it from the others.
        guard b.st_nlink == 1 else { throw .hardLinked }
        guard a.st_size == b.st_size, try sameContents(original, duplicate) else { throw .contentsDiffer }

        let folder = (duplicate as NSString).deletingLastPathComponent
        let temporary = (folder as NSString).appendingPathComponent(".diskbloom-clone-\(UUID().uuidString)")
        defer { unlink(temporary) } // a no-op once renamed
        guard copyfile(original, temporary, nil, copyfile_flags_t(COPYFILE_CLONE_FORCE)) == 0 else {
            throw .system(String(cString: strerror(errno)))
        }
        // The duplicate's own metadata (mode, owner, dates, xattrs, ACL), not the original's.
        guard copyfile(duplicate, temporary, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw .system(String(cString: strerror(errno)))
        }
        guard rename(temporary, duplicate) == 0 else {
            throw .system(String(cString: strerror(errno)))
        }
    }

    /// Byte-by-byte comparison.
    static func sameContents(_ first: String, _ second: String) throws(ReplaceError) -> Bool {
        guard let a = FileHandle(forReadingAtPath: first), let b = FileHandle(forReadingAtPath: second) else {
            throw .notRegularFiles
        }
        defer {
            try? a.close()
            try? b.close()
        }
        let chunk = 1 << 20
        while true {
            let left = (try? a.read(upToCount: chunk)) ?? Data()
            let right = (try? b.read(upToCount: chunk)) ?? Data()
            if left != right { return false }
            if left.isEmpty { return true }
        }
    }
}
#endif
