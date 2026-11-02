#if canImport(Darwin)
import Darwin
@testable import DiskbloomKit
import Foundation
import Testing

struct APFSClonesTests {
    let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clones-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func write(_ name: String, _ bytes: Int, value: UInt8 = 7) -> String {
        let path = folder.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data(repeating: value, count: bytes))
        return path
    }

    @Test func clonesShareSpaceAndCopiesDoNot() throws {
        let original = write("a.bin", 4_000_000)
        let copy = write("b.bin", 4_000_000)
        let clone = folder.appendingPathComponent("c.bin").path
        try #require(copyfile(original, clone, nil, copyfile_flags_t(COPYFILE_CLONE_FORCE)) == 0)

        let a = try #require(APFSClones.info(path: original))
        let b = try #require(APFSClones.info(path: copy))
        let c = try #require(APFSClones.info(path: clone))
        #expect(b.privateSize >= 4_000_000) // a plain copy owns its blocks
        #expect(a.privateSize == 0 && c.privateSize == 0) // original and clone share them
        #expect(a.cloneID == c.cloneID)
        #expect(APFSClones.reclaimable([original, clone]) == 0)
        #expect((APFSClones.reclaimable([original, copy]) ?? 0) >= 4_000_000)
    }

    @Test func replaceWithCloneFreesTheCopyAndKeepsItsName() throws {
        let original = write("a.bin", 3_000_000)
        let copy = write("b.bin", 3_000_000)
        chmod(copy, 0o600)
        try APFSClones.replaceWithClone(original: original, duplicate: copy)
        #expect(FileManager.default.contents(atPath: copy) == Data(repeating: 7, count: 3_000_000))
        #expect(APFSClones.info(path: copy)?.privateSize == 0)
        var st = stat()
        lstat(copy, &st)
        #expect(st.st_mode & 0o777 == 0o600) // the duplicate's own permissions stay
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers.sorted() == ["a.bin", "b.bin"])
    }

    @Test func differentContentsAreNeverReplaced() {
        let original = write("a.bin", 100_000, value: 1)
        let other = write("b.bin", 100_000, value: 2)
        #expect(throws: APFSClones.ReplaceError.contentsDiffer) {
            try APFSClones.replaceWithClone(original: original, duplicate: other)
        }
        #expect(FileManager.default.contents(atPath: other) == Data(repeating: 2, count: 100_000))
    }

    @Test func hardLinksAreNotReplaced() {
        let original = write("a.bin", 10_000)
        let copy = write("b.bin", 10_000)
        link(copy, folder.appendingPathComponent("b-link.bin").path)
        #expect(throws: APFSClones.ReplaceError.hardLinked) {
            try APFSClones.replaceWithClone(original: original, duplicate: copy)
        }
    }
}
#endif
