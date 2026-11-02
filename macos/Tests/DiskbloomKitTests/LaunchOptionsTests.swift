import DiskbloomKit
import Testing

struct LaunchOptionsTests {
    @Test func typesModeIsRead() {
        #expect(LaunchOptions(environment: ["DISKBLOOM_MODE": "types"]).view == .types)
        #expect(LaunchOptions(environment: ["DISKBLOOM_MODE": "nope"]).view == nil)
    }

    @Test func searchQueryIsRead() {
        #expect(LaunchOptions(environment: ["DISKBLOOM_SEARCH": "video"]).searchQuery == "video")
        #expect(LaunchOptions(environment: ["DISKBLOOM_SEARCH": ""]).searchQuery == nil)
        #expect(LaunchOptions(environment: [:]).searchQuery == nil)
    }
}
