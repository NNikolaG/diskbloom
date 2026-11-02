import Foundation

/// Number formatting shared by all views.
public enum Format {
    /// Decimal units, like Finder: "1.5 GB".
    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    /// Short form for tight spaces such as the menu bar: "84 GB", "6.5 GB", "1.2 TB".
    /// Decimal units like `bytes`, at most one fraction digit and only below 10.
    public static func shortBytes(_ value: Int64, locale: Locale = .current) -> String {
        let units: [(name: String, size: Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6)]
        let bytes = Double(max(0, value))
        guard var index = units.firstIndex(where: { bytes >= $0.size }) else {
            return Self.bytes(UInt64(max(0, value)))
        }
        // Use the bigger unit once rounding would print "1,000 GB".
        if index > 0, bytes / units[index].size >= 999.5 { index -= 1 }
        let unit = units[index]
        let amount = bytes / unit.size
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...(amount < 9.95 ? 1 : 0)))
            .locale(locale)
        return "\(amount.formatted(style)) \(unit.name)"
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
