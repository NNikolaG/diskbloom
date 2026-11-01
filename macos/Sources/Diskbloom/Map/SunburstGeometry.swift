import DiskbloomFFI
import SwiftUI

/// Maps sunburst segments (angles as fractions, ring depths) to points in a view.
struct SunburstGeometry {
    enum Hit { case center, segment(SegmentInfo), none }

    let center: CGPoint
    /// Radius of the center disc.
    let inner: CGFloat
    /// Width of one ring.
    let ring: CGFloat

    init(size: CGSize, rings: UInt32) {
        let outer = max(10, min(size.width, size.height) / 2 - 8)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        inner = outer * 0.24
        ring = (outer - inner) / CGFloat(rings)
    }

    /// `fraction` of the circle from twelve o'clock, clockwise, at radius `radius`.
    func point(_ fraction: Double, _ radius: CGFloat) -> CGPoint {
        let angle = fraction * 2 * .pi
        return CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }

    func path(_ segment: SegmentInfo) -> Path {
        let r0 = inner + CGFloat(segment.depth) * ring + 0.5
        let r1 = r0 + ring - 1
        let span = segment.end - segment.start
        let steps = max(2, Int(span * 360))
        var path = Path()
        path.move(to: point(segment.start, r0))
        for i in 0...steps {
            path.addLine(to: point(segment.start + span * Double(i) / Double(steps), r1))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: point(segment.start + span * Double(i) / Double(steps), r0))
        }
        path.closeSubpath()
        return path
    }

    var centerDisc: Path {
        let r = inner - 4
        return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    func hit(_ location: CGPoint, in segments: [SegmentInfo]) -> Hit {
        let dx = location.x - center.x, dy = location.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        if radius < inner { return .center }
        let depth = UInt32((radius - inner) / ring)
        var fraction = Double(atan2(dx, -dy)) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        if let segment = segments.first(where: { $0.depth == depth && $0.start <= fraction && fraction < $0.end }) {
            return .segment(segment)
        }
        return .none
    }
}
