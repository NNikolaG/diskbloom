import DiskbloomKit
import SwiftUI

/// Shown when the scan could not read some folders.
struct AccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("\(Format.count(model.inaccessible)) folders could not be read. Give Diskbloom Full Disk Access to see everything.")
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Settings") { model.openFullDiskAccessSettings() }
                .fixedSize()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}
