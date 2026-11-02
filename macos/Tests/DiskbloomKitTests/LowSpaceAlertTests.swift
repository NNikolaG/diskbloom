import DiskbloomKit
import Testing

struct LowSpaceAlertTests {
    static let gb: Int64 = 1_000_000_000

    /// Feeds free-space readings (in GB) and returns which of them fired the warning.
    static func fired(_ alert: inout LowSpaceAlert, totalGB: Int64, readings: [Int64]) -> [Bool] {
        readings.map { alert.update(free: $0 * gb, total: totalGB * gb) }
    }

    @Test func thresholdIsTheSmallerOfShareAndLimit() {
        let alert = LowSpaceAlert()
        let gb = Self.gb
        // 10% of 100 GB is 10 GB, below the 20 GB limit.
        #expect(alert.threshold(total: 100 * gb) == 10 * gb)
        // 10% of 1 TB is 100 GB, so the 20 GB limit wins.
        #expect(alert.threshold(total: 1000 * gb) == 20 * gb)
        #expect(alert.threshold(total: 0) == 0)
        #expect(alert.recoveryLevel(total: 1000 * gb) == 25 * gb)
    }

    @Test func notifiesOnceWhenSpaceRunsLow() {
        var alert = LowSpaceAlert()
        // 500 GB disk: threshold 20 GB. Exactly at the threshold is not low yet.
        let fired = Self.fired(&alert, totalGB: 500, readings: [50, 20, 19, 15, 5])
        #expect(fired == [false, false, true, false, false])
        #expect(alert.hasNotified)
    }

    @Test func staysQuietUntilSpaceRecoversPastTheMargin() {
        var alert = LowSpaceAlert()
        // Hovering around the threshold (20 GB) but not above threshold + margin (25 GB).
        let hovering = Self.fired(&alert, totalGB: 500, readings: [19, 21, 19, 25])
        #expect(hovering == [true, false, false, false])
        #expect(alert.hasNotified)
        // Recovered: the next drop warns again.
        let recovered = Self.fired(&alert, totalGB: 500, readings: [30, 18])
        #expect(recovered == [false, true])
    }

    @Test func smallVolumesUseTheShare() {
        var alert = LowSpaceAlert()
        // 128 GB disk: threshold 12.8 GB, recovery 16 GB.
        let low = Self.fired(&alert, totalGB: 128, readings: [13, 12, 15])
        #expect(low == [false, true, false])
        #expect(alert.hasNotified)
        let recovered = Self.fired(&alert, totalGB: 128, readings: [17])
        #expect(recovered == [false])
        #expect(!alert.hasNotified)
    }

    @Test func ignoresUnknownVolumesAndRestoresState() {
        var alert = LowSpaceAlert(hasNotified: true)
        let unknown = Self.fired(&alert, totalGB: 0, readings: [0])
        #expect(unknown == [false])
        #expect(alert.hasNotified)
        // Already warned before a restart: still quiet while space stays low.
        let stillLow = Self.fired(&alert, totalGB: 500, readings: [1])
        #expect(stillLow == [false])
    }
}
