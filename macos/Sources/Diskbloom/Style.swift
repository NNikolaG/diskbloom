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
            return Color(white: 0.55).opacity(highlighted ? 0.75 : 0.4)
        }
        // Ista paleta kao ikonica: cijan -> plava -> ljubicasta -> roze -> cilibar.
        let h = (0.52 + hue * 0.6).truncatingRemainder(dividingBy: 1)
        return Color(
            hue: h,
            saturation: max(0.42, 0.62 - d * 0.035),
            brightness: min(1, max(0.58, 0.9 - d * 0.055) + (highlighted ? 0.1 : 0))
        )
    }

    static func color(_ s: SegmentInfo, highlighted: Bool = false) -> Color {
        color(hue: s.hue, depth: s.depth, aggregated: s.id == nil, highlighted: highlighted)
    }
}

extension NodeInfo {
    var displayName: String { isDir && !name.hasSuffix("/") ? name + "/" : name }
}
