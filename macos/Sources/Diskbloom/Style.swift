import DiskbloomFFI
import SwiftUI

enum Fmt {
    /// Decimalne jedinice, isto kao Finder.
    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .file)
    }

    static func count(_ n: UInt64) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

enum Palette {
    /// Boja grane po uglu, svetlina opada sa dubinom; zbirni segmenti su sivi.
    static func color(hue: Double, depth: UInt32, aggregated: Bool, highlighted: Bool = false) -> Color {
        let d = Double(depth)
        if aggregated {
            return Color(white: max(0.25, 0.48 - d * 0.03) + (highlighted ? 0.15 : 0))
        }
        return Color(
            hue: hue.truncatingRemainder(dividingBy: 1),
            saturation: max(0.35, 0.72 - d * 0.06),
            brightness: min(1, max(0.45, 0.92 - d * 0.07) + (highlighted ? 0.12 : 0))
        )
    }

    static func color(_ s: SegmentInfo, highlighted: Bool = false) -> Color {
        color(hue: s.hue, depth: s.depth, aggregated: s.id == nil, highlighted: highlighted)
    }
}

extension NodeInfo {
    var displayName: String { isDir && !name.hasSuffix("/") ? name + "/" : name }
}
