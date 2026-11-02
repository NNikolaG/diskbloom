import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// One file kind in the summary: symbol, title, share of the scan, size and count.
/// Clicking it lists the largest items of that kind.
struct KindRow: View {
    let info: KindInfo
    let total: UInt64
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let fraction = total > 0 ? Double(info.size) / Double(total) : 0
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: info.kind.symbol)
                    .foregroundStyle(info.kind.color)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(info.kind.title).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.bytes(info.size)).monospacedDigit()
                    }
                    ShareBar(fraction: fraction, color: info.kind.color)
                    HStack {
                        Text("\(Format.count(info.count)) items")
                        Spacer(minLength: 8)
                        Text(Format.percent(info.size, of: total))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? info.kind.color.opacity(0.18) : hover ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(Text(verbatim: "\(info.kind.title), \(Format.bytes(info.size))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// How much of the scan a kind takes.
private struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, proxy.size.width * fraction))
                }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
