@testable import DiskbloomKit
import Foundation
import Testing

struct SimulatorLabelTests {
    @Test func runtimeIdentifierBecomesVersion() {
        #expect(CandidateLabel.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-2") == "iOS 17.2")
        #expect(CandidateLabel.runtimeName("com.apple.CoreSimulator.SimRuntime.watchOS-10-0") == "watchOS 10.0")
    }

    @Test func simulatorLabelComesFromDevicePlist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plist: [String: Any] = ["name": "iPhone 15 Pro", "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-17-2"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: dir.appendingPathComponent("device.plist"))
        #expect(CandidateLabel.make(category: "simulators", path: dir.path, home: "/nope") == "iPhone 15 Pro · iOS 17.2")
    }
}
