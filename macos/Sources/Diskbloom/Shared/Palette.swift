import DiskbloomFFI
import SwiftUI

/// Sunburst colors.
enum Palette {
    /// Branch color by angle, darker with depth; aggregate segments are gray.
    static func color(hue: Double, depth: UInt32, aggregated: Bool, highlighted: Bool = false) -> Color {
        if aggregated {
            return Color(white: 0.55).opacity(highlighted ? 0.75 : 0.4)
        }
        // Same palette as the icon: cyan → blue → violet → pink → amber.
        let d = Double(depth)
        return Color(
            hue: (0.52 + hue * 0.6).truncatingRemainder(dividingBy: 1),
            saturation: max(0.42, 0.62 - d * 0.035),
            brightness: min(1, max(0.58, 0.9 - d * 0.055) + (highlighted ? 0.1 : 0))
        )
    }

    static func color(_ segment: SegmentInfo, highlighted: Bool = false) -> Color {
        color(hue: segment.hue, depth: segment.depth, aggregated: segment.id == nil, highlighted: highlighted)
    }
}
