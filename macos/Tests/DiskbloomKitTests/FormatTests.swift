import DiskbloomKit
import Foundation
import Testing

struct FormatTests {
    @Test func percentHandlesEdges() {
        #expect(Format.percent(1, of: 0) == "")
        #expect(Format.percent(1, of: 100_000) == "<0.1%")
        #expect(Format.percent(0, of: 10).hasPrefix("0"))
    }

    @Test func homeIsAbbreviated() {
        #expect(CandidateLabel.abbreviatingHome("/Users/me/x", home: "/Users/me") == "~/x")
        #expect(CandidateLabel.abbreviatingHome("/Users/meow/x", home: "/Users/me") == "/Users/meow/x")
    }

    @Test func androidLabel() {
        let label = CandidateLabel.make(category: "android-emulators", path: "/h/.android/avd/Pixel_8_API_34.avd", home: "/h")
        #expect(label == "Pixel 8 API 34")
    }

    @Test func launchOptionsReadEnvironment() {
        let options = LaunchOptions(environment: ["DISKBLOOM_SCAN": "/tmp", "DISKBLOOM_MODE": "duplicates"])
        #expect(options.scanPath == "/tmp")
        #expect(options.view == .duplicates)
        #expect(!options.openCleaner)
        #expect(LaunchOptions(environment: ["DISKBLOOM_SCAN": ""]).scanPath == nil)
        #expect(LaunchOptions(environment: ["DISKBLOOM_OVERVIEW": "1"]).overviewPath == nil)
        #expect(LaunchOptions(environment: ["DISKBLOOM_OVERVIEW": "/Users/x"]).overviewPath == "/Users/x")
    }

    @Test func shortBytesFitsTheMenuBar() {
        let en = Locale(identifier: "en_US")
        #expect(Format.shortBytes(84_321_000_000, locale: en) == "84 GB")
        #expect(Format.shortBytes(6_480_000_000, locale: en) == "6.5 GB")
        #expect(Format.shortBytes(6_000_000_000, locale: en) == "6 GB")
        #expect(Format.shortBytes(1_230_000_000_000, locale: en) == "1.2 TB")
        #expect(Format.shortBytes(999_700_000_000, locale: en) == "1 TB")
        #expect(Format.shortBytes(512_000_000, locale: en) == "512 MB")
        #expect(Format.shortBytes(6_480_000_000, locale: Locale(identifier: "sr_Latn_RS")) == "6,5 GB")
        #expect(Format.shortBytes(-5, locale: en) == Format.bytes(0))
    }
}
