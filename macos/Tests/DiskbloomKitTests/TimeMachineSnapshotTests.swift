import DiskbloomKit
import Testing

struct TimeMachineSnapshotTests {
    let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-30-090000.local
        com.apple.TimeMachine.2026-10-31-101500.local
        com.apple.os.update-ABCDEF
        """

    @Test func parseSortsNewestFirst() {
        let snapshots = TimeMachineSnapshot.parse(output)
        #expect(snapshots.count == 3)
        #expect(snapshots.first?.stamp == "2026-10-31-101500")
        #expect(snapshots.filter(\.isTimeMachine).count == 2)
    }

    @Test func onlyValidStampsReachTheAdminCommand() {
        let evil = TimeMachineSnapshot(name: "com.apple.TimeMachine.2026; rm -rf ~.local", date: nil)
        let good = TimeMachineSnapshot(name: "com.apple.TimeMachine.2026-10-31-101500.local", date: nil)
        let system = TimeMachineSnapshot(name: "com.apple.os.update-ABCDEF", date: nil)
        #expect(evil.stamp == nil)
        #expect(system.stamp == nil)
        #expect(TimeMachineSnapshot.deleteCommand(for: [evil, system]) == nil)
        #expect(TimeMachineSnapshot.deleteCommand(for: [evil, good])
                == "/usr/bin/tmutil deletelocalsnapshots 2026-10-31-101500")
    }
}
