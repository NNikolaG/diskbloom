/// Decides when to warn that a volume is running out of space.
///
/// The warning fires once when free space drops below the threshold (a share of the
/// volume or a fixed amount, whichever is smaller). It fires again only after free space
/// has recovered above the threshold plus a margin, so free space hovering around the
/// threshold does not cause a stream of notifications.
public struct LowSpaceAlert: Sendable, Equatable {
    /// Warn below this share of the volume's capacity…
    public var fraction: Double
    /// …or below this many bytes, whichever is smaller.
    public var limit: Int64
    /// How far above the threshold free space must recover before the alert re-arms,
    /// as a share of the threshold.
    public var marginFraction: Double
    /// Whether the warning was given and space has not recovered since.
    public private(set) var hasNotified: Bool

    public init(fraction: Double = 0.10, limit: Int64 = 20_000_000_000,
                marginFraction: Double = 0.25, hasNotified: Bool = false) {
        self.fraction = fraction
        self.limit = limit
        self.marginFraction = marginFraction
        self.hasNotified = hasNotified
    }

    /// Free space below this is "low": 10% or 20 GB, whichever is smaller, by default.
    public func threshold(total: Int64) -> Int64 {
        guard total > 0 else { return 0 }
        return min(Int64(Double(total) * fraction), limit)
    }

    /// Free space must rise above this before the alert can fire again.
    public func recoveryLevel(total: Int64) -> Int64 {
        let threshold = threshold(total: total)
        return threshold + Int64(Double(threshold) * marginFraction)
    }

    /// Feeds a new reading; returns `true` when the warning should be shown now.
    /// Readings of an unknown volume (`total` zero or less) are ignored.
    public mutating func update(free: Int64, total: Int64) -> Bool {
        guard total > 0 else { return false }
        if hasNotified {
            if free > recoveryLevel(total: total) { hasNotified = false }
            return false
        }
        guard free < threshold(total: total) else { return false }
        hasNotified = true
        return true
    }
}
