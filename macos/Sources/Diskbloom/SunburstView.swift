import AppKit
import DiskbloomFFI
import SwiftUI

/// Sunburst mapa. Raspored (uglovi, dubine, boje) racuna Rust; ovde se samo crta i pogadja misem.
struct SunburstView: View {
    @EnvironmentObject var model: AppModel

    struct Geometry {
        let center: CGPoint
        let inner: CGFloat
        let ring: CGFloat

        init(size: CGSize) {
            let maxR = max(10, min(size.width, size.height) / 2 - 8)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            inner = maxR * 0.24
            ring = (maxR - inner) / CGFloat(AppModel.rings)
        }

        /// Ugao kao razlomak kruga: 0 na 12 sati, u smeru kazaljke.
        func point(_ fraction: Double, _ r: CGFloat) -> CGPoint {
            let a = fraction * 2 * .pi
            return CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
        }

        func path(_ s: SegmentInfo) -> Path {
            let r0 = inner + CGFloat(s.depth) * ring + 0.5
            let r1 = r0 + ring - 1
            let span = s.end - s.start
            let steps = max(2, Int(span * 360))
            var p = Path()
            p.move(to: point(s.start, r0))
            for i in 0...steps { p.addLine(to: point(s.start + span * Double(i) / Double(steps), r1)) }
            for i in stride(from: steps, through: 0, by: -1) {
                p.addLine(to: point(s.start + span * Double(i) / Double(steps), r0))
            }
            p.closeSubpath()
            return p
        }

        enum Hit { case center, segment(SegmentInfo), none }

        func hit(_ loc: CGPoint, in segments: [SegmentInfo]) -> Hit {
            let dx = loc.x - center.x, dy = loc.y - center.y
            let r = (dx * dx + dy * dy).squareRoot()
            if r < inner { return .center }
            let depth = UInt32((r - inner) / ring)
            var f = Double(atan2(dx, -dy)) / (2 * .pi)
            if f < 0 { f += 1 }
            if let s = segments.first(where: { $0.depth == depth && $0.start <= f && f < $0.end }) {
                return .segment(s)
            }
            return .none
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let g = Geometry(size: proxy.size)
            ZStack {
                Canvas { ctx, _ in
                    for s in model.segments {
                        let hl = model.hovered.map { $0 == s } ?? false
                        ctx.fill(g.path(s), with: .color(Palette.color(s, highlighted: hl)))
                    }
                    let c = Path(ellipseIn: CGRect(x: g.center.x - g.inner + 4, y: g.center.y - g.inner + 4,
                                                   width: (g.inner - 4) * 2, height: (g.inner - 4) * 2))
                    ctx.fill(c, with: .color(Color(nsColor: .controlBackgroundColor)))
                }
                centerLabel.frame(width: g.inner * 1.6)
                    .position(g.center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    if case .segment(let s) = g.hit(loc, in: model.segments) {
                        if model.hovered != s { model.hovered = s }
                    } else if model.hovered != nil {
                        model.hovered = nil
                    }
                case .ended:
                    model.hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { loc in
                switch g.hit(loc, in: model.segments) {
                case .center: model.zoomOut()
                case .segment(let s): model.open(s)
                case .none: break
                }
            }
            .contextMenu {
                if let s = model.hovered, let id = s.id {
                    Button("Dodaj u Collector") { model.collect(id) }
                    Button("Prikazi u Finder-u") { model.revealInFinder(id) }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }

    @ViewBuilder private var centerLabel: some View {
        let s = model.hovered
        let name = s?.name ?? model.focusInfo?.name ?? ""
        let size = s?.size ?? model.focusInfo?.size ?? 0
        VStack(spacing: 4) {
            Text(name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            Text(Fmt.bytes(size)).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            if s == nil, model.crumbs.count > 1 {
                Text("klik za nazad").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
