import DiskbloomFFI
import SwiftUI

/// A small sunburst of what the scan has finished so far, with a spinner in the middle.
struct ScanPreview: View {
    let segments: [SegmentInfo]
    private static let rings: UInt32 = 3

    var body: some View {
        GeometryReader { proxy in
            let geometry = SunburstGeometry(size: proxy.size, rings: Self.rings)
            ZStack {
                Canvas { context, _ in
                    // An empty ring until the first folder finishes.
                    let track = Path(ellipseIn: CGRect(
                        x: geometry.center.x - geometry.inner - geometry.ring / 2,
                        y: geometry.center.y - geometry.inner - geometry.ring / 2,
                        width: (geometry.inner + geometry.ring / 2) * 2,
                        height: (geometry.inner + geometry.ring / 2) * 2))
                    context.stroke(track, with: .color(.primary.opacity(0.06)), lineWidth: geometry.ring)
                    for segment in segments {
                        let path = geometry.path(segment)
                        context.fill(path, with: .color(Palette.color(segment)))
                        context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 0.8)
                    }
                }
                ProgressView().controlSize(.large)
            }
        }
        .animation(.easeOut(duration: 0.3), value: segments.count)
        .accessibilityHidden(true)
    }
}
