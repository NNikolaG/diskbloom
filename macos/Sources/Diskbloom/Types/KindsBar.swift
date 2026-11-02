import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// The whole scan as one bar split by file kind; the list below is its legend.
struct KindsBar: View {
    let kinds: [KindInfo]
    let total: UInt64
    let selected: FileKind?
    let select: (FileKind) -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let width = max(0, proxy.size.width - spacing * CGFloat(max(kinds.count - 1, 0)))
            HStack(spacing: spacing) {
                ForEach(kinds, id: \.kind) { info in
                    Rectangle()
                        .fill(info.kind.color.opacity(selected == nil || selected == info.kind ? 1 : 0.4))
                        .frame(width: max(2, width * share(info)))
                        .contentShape(Rectangle())
                        .onTapGesture { select(info.kind) }
                        .help(Text(verbatim: "\(info.kind.title) — \(Format.bytes(info.size))"
                                + " (\(Format.percent(info.size, of: total)))"))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 20)
        // The rows below say the same for VoiceOver.
        .accessibilityHidden(true)
    }

    private func share(_ info: KindInfo) -> Double {
        total > 0 ? Double(info.size) / Double(total) : 0
    }
}
