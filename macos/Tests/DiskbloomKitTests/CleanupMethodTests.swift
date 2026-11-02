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

    @Test func simulatorRuntimesNeverGoToTheTrash() {
        let image = "/Library/Developer/CoreSimulator/Images/EB213AC6-D0C7-494C-B960-A0888D020599.dmg"
        #expect(CleanupMethod.resolve(category: "sim-runtimes", path: image) == .simulatorRuntime(path: image))
        // anywhere else the category is not trusted: skipped, not trashed
        #expect(CleanupMethod.resolve(category: "sim-runtimes", path: "/Users/me/Downloads/iOS.dmg") == .skip)
        #expect(CleanupMethod.resolve(category: "sim-runtimes", path: "/Library/Developer/CoreSimulator/Images") == .skip)
    }

    @Test func newCacheCategoriesGoToTheTrash() {
        for (category, path) in [
            ("jetbrains-cache", "/Users/me/Library/Caches/JetBrains/IntelliJIdea2025.2"),
            ("editor-cache", "/Users/me/Library/Application Support/Code/CachedData"),
            ("node-versions", "/Users/me/.nvm/versions/node/v18.20.4"),
        ] {
            #expect(CleanupMethod.resolve(category: category, path: path) == .trash)
        }
    }

    @Test func dockerDiskAndTrashAreSpecial() {
        let docker = "/Users/me/Library/Containers/com.docker.docker/Data/vms"
        #expect(CleanupMethod.resolve(category: "vms", path: docker) == .docker)
        #expect(CleanupMethod.resolve(category: "trash", path: "/Users/me/.Trash") == .emptyTrash)
        #expect(CleanupMethod.resolve(category: "node-deps", path: "/Users/me/app/node_modules") == .trash)
    }
}
