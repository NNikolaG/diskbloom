import DiskbloomKit
import Testing

struct CleanupMethodTests {
    @Test func simulatorNeedsDeviceUUID() {
        let base = "/Users/me/Library/Developer/CoreSimulator/Devices/"
        let udid = "0A1B2C3D-0000-1111-2222-333344445555"
        #expect(CleanupMethod.resolve(category: "simulators", path: base + udid) == .simulator(udid: udid))
        // "all" would make `simctl delete all` remove every simulator
        #expect(CleanupMethod.resolve(category: "simulators", path: base + "all") == .skip)
        #expect(CleanupMethod.resolve(category: "simulators", path: base + "0A1B2C3D-TEST") == .skip)
    }

    @Test func androidEmulatorTakesItsIniAlong() {
        let method = CleanupMethod.resolve(category: "android-emulators", path: "/Users/me/.android/avd/Pixel_8.avd")
        #expect(method == .androidEmulator(ini: "/Users/me/.android/avd/Pixel_8.ini"))
    }

    @Test func dockerDiskAndTrashAreSpecial() {
        let docker = "/Users/me/Library/Containers/com.docker.docker/Data/vms"
        #expect(CleanupMethod.resolve(category: "vms", path: docker) == .docker)
        #expect(CleanupMethod.resolve(category: "trash", path: "/Users/me/.Trash") == .emptyTrash)
        #expect(CleanupMethod.resolve(category: "node-deps", path: "/Users/me/app/node_modules") == .trash)
    }
}
