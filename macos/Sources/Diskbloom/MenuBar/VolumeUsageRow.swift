import DiskbloomKit
import SwiftUI

/// A disk in the menu bar window: name, a small usage bar and free / total space.
struct VolumeUsageRow: View {
    let volume: VolumeUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(volume.name, systemImage: volume.icon)
                    .lineLimit(1)
                Spacer()
                Text("\(Format.percent(UInt64(clamping: volume.total - volume.free), of: UInt64(clamping: volume.total))) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: volume.usedFraction)
                .tint(volume.usedFraction > 0.9 ? .red : .accentColor)
                .accessibilityHidden(true)
            Text("\(Format.bytes(UInt64(clamping: volume.free))) free of \(Format.bytes(UInt64(clamping: volume.total)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
