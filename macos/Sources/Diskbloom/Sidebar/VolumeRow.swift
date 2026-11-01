import DiskbloomKit
import SwiftUI

/// A disk with its fill level.
struct VolumeRow: View {
    let volume: MountedVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(volume.name, systemImage: volume.icon)
                .lineLimit(1)
            ProgressView(value: volume.usedFraction)
                .tint(volume.usedFraction > 0.9 ? .red : .accentColor)
                .accessibilityHidden(true)
            Text("\(Format.bytes(UInt64(volume.free))) free of \(Format.bytes(UInt64(volume.total)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
