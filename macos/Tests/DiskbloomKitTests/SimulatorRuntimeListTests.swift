import DiskbloomKit
import Testing

struct SimulatorRuntimeListTests {
    static let xcode15Image = "/Library/Developer/CoreSimulator/Images/EB213AC6-D0C7-494C-B960-A0888D020599.dmg"
    static let xcode16Bundle =
        "/Library/Developer/CoreSimulator/Cryptex/Images/bundle/SimRuntimeBundle-81A82E90-ACDD-47C8-A3B1-A93E7FC76A93"

    /// Shaped like `xcrun simctl runtime list -j`: keyed by UUID, and the Xcode 16
    /// identifier differs from the UUID in the bundle's name.
    static let list = #"""
    {
      "EB213AC6-D0C7-494C-B960-A0888D020599" : {
        "build" : "22E5216h",
        "deletable" : true,
        "identifier" : "EB213AC6-D0C7-494C-B960-A0888D020599",
        "kind" : "Disk Image",
        "mountPath" : "\/Library\/Developer\/CoreSimulator\/Volumes\/iOS_22E5216h",
        "path" : "\/Library\/Developer\/CoreSimulator\/Images\/EB213AC6-D0C7-494C-B960-A0888D020599.dmg",
        "state" : "Ready",
        "version" : "18.4"
      },
      "40C50016-ECEE-439C-A27D-6F55716AD2F6" : {
        "build" : "22A3351",
        "deletable" : true,
        "identifier" : "40C50016-ECEE-439C-A27D-6F55716AD2F6",
        "kind" : "Disk Image",
        "mountPath" : "\/Library\/Developer\/CoreSimulator\/Volumes\/iOS_22A3351",
        "path" : "\/Library\/Developer\/CoreSimulator\/Cryptex\/Images\/bundle\/SimRuntimeBundle-81A82E90-ACDD-47C8-A3B1-A93E7FC76A93\/Restore\/043-19278-100.dmg",
        "state" : "Ready",
        "version" : "18.0"
      },
      "5CCEADAF-4C3B-4519-BDDC-61E9479A6530" : {
        "deletable" : false,
        "identifier" : "5CCEADAF-4C3B-4519-BDDC-61E9479A6530",
        "kind" : "Bundled with Xcode",
        "path" : "\/Library\/Developer\/CoreSimulator\/Images\/5CCEADAF-4C3B-4519-BDDC-61E9479A6530.dmg",
        "state" : "Ready"
      },
      "all" : {
        "deletable" : true,
        "identifier" : "all",
        "path" : "\/Library\/Developer\/CoreSimulator\/Images\/all.dmg"
      }
    }
    """#

    @Test func identifierComesFromSimctlMatchedByPath() {
        #expect(SimulatorRuntimeList.identifier(forImageAt: Self.xcode15Image, in: Self.list)
            == "EB213AC6-D0C7-494C-B960-A0888D020599")
        // the image inside the bundle folder; the identifier is not the bundle's UUID
        #expect(SimulatorRuntimeList.identifier(forImageAt: Self.xcode16Bundle, in: Self.list)
            == "40C50016-ECEE-439C-A27D-6F55716AD2F6")
    }

    @Test func dataVolumeFormAndTrailingSlashMatchToo() {
        #expect(SimulatorRuntimeList.identifier(forImageAt: "/System/Volumes/Data" + Self.xcode16Bundle + "/",
                                                in: Self.list) == "40C50016-ECEE-439C-A27D-6F55716AD2F6")
    }

    @Test func stderrAroundTheJSONIsIgnored() {
        let output = "2026-11-02 warning: something\n" + Self.list + "\n"
        #expect(SimulatorRuntimeList.identifier(forImageAt: Self.xcode15Image, in: output)
            == "EB213AC6-D0C7-494C-B960-A0888D020599")
    }

    @Test func notDeletableOrNotUUIDIsRefused() {
        // simctl says it ships with Xcode
        #expect(SimulatorRuntimeList.identifier(
            forImageAt: "/Library/Developer/CoreSimulator/Images/5CCEADAF-4C3B-4519-BDDC-61E9479A6530.dmg",
            in: Self.list) == nil)
        // "all" must never reach `simctl runtime delete`
        #expect(SimulatorRuntimeList.identifier(forImageAt: "/Library/Developer/CoreSimulator/Images/all.dmg",
                                                in: Self.list) == nil)
    }

    @Test func unknownPathsAndBadOutputAreRefused() {
        let unlisted = "/Library/Developer/CoreSimulator/Images/00000000-0000-0000-0000-000000000000.dmg"
        #expect(SimulatorRuntimeList.identifier(forImageAt: unlisted, in: Self.list) == nil)
        // a parent folder contains every image: never a match
        #expect(SimulatorRuntimeList.identifier(forImageAt: "/Library/Developer/CoreSimulator/Images",
                                                in: Self.list) == nil)
        #expect(SimulatorRuntimeList.identifier(forImageAt: "/Library/Developer/CoreSimulator/Cryptex/Images/bundle/..",
                                                in: Self.list) == nil)
        #expect(SimulatorRuntimeList.identifier(forImageAt: "/", in: Self.list) == nil)
        #expect(SimulatorRuntimeList.identifier(forImageAt: Self.xcode15Image, in: "xcrun: error: unable to find utility") == nil)
        #expect(SimulatorRuntimeList.identifier(forImageAt: Self.xcode15Image, in: "{ not json }") == nil)
    }

    @Test func twoRuntimesForOnePathAreRefused() {
        let twice = #"""
        {
          "A" : { "deletable" : true, "identifier" : "EB213AC6-D0C7-494C-B960-A0888D020599",
                  "path" : "\/Library\/Developer\/CoreSimulator\/Cryptex\/Images\/bundle\/SimRuntimeBundle-X\/a.dmg" },
          "B" : { "deletable" : true, "identifier" : "40C50016-ECEE-439C-A27D-6F55716AD2F6",
                  "path" : "\/Library\/Developer\/CoreSimulator\/Cryptex\/Images\/bundle\/SimRuntimeBundle-X\/b.dmg" }
        }
        """#
        #expect(SimulatorRuntimeList.identifier(
            forImageAt: "/Library/Developer/CoreSimulator/Cryptex/Images/bundle/SimRuntimeBundle-X", in: twice) == nil)
    }

    @Test func onlyDirectChildrenOfTheImageFoldersAreRuntimes() {
        #expect(SimulatorRuntimeList.isImageLocation(Self.xcode15Image))
        #expect(SimulatorRuntimeList.isImageLocation(Self.xcode16Bundle))
        #expect(!SimulatorRuntimeList.isImageLocation("/Library/Developer/CoreSimulator/Images"))
        #expect(!SimulatorRuntimeList.isImageLocation("/Library/Developer/CoreSimulator/Images/Inbox/x.dmg"))
        #expect(!SimulatorRuntimeList.isImageLocation("/Users/me/Library/Developer/CoreSimulator/Images/x.dmg"))
        #expect(!SimulatorRuntimeList.isImageLocation("/Library/Developer/CoreSimulator/Volumes/iOS_22A3351"))
    }
}
