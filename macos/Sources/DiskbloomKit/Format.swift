import Foundation

/// Number formatting shared by all views.
public enum Format {
    /// Decimal units, like Finder: "1.5 GB".
    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    /// Localized integer with grouping: "12,345".
    public static func count<T: BinaryInteger>(_ value: T) -> String {
        Int64(clamping: value).formatted(.number)
    }

    /// Share of `total`, e.g. "12%", "3.4%" or "<0.1%"; empty when `total` is zero.
    public static func percent(_ part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "" }
        let share = Double(part) / Double(total)
        if share > 0, share < 0.001 { return "<0.1%" }
        let digits = share >= 0.1 ? 0 : 1
        return share.formatted(.percent.precision(.fractionLength(digits)))
    }
}
