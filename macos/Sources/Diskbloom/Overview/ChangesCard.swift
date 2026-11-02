import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// What grew or shrank since the previous scan of this place.
struct ChangesCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.catchingUp, let since = model.scannedAt {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking what changed since \(since.formatted(.relative(presentation: .named)))…")
                    .foregroundStyle(.secondary)
            }
        } else if let since = model.growthSince, let growth = model.growth {
            VStack(alignment: .leading, spacing: 8) {
                header(since: since, growth: growth)
                ForEach(growth, id: \.path) { change in
                    ChangeRow(change: change)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private func header(since: Date, growth: [GrowthInfo]) -> some View {
        let sinceText = since.formatted(date: .abbreviated, time: .shortened)
        if growth.isEmpty {
            Label {
                Text("No big changes since \(sinceText)")
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
            }
            .font(.headline)
        } else {
            Text("Changes since \(sinceText)").font(.headline)
        }
    }
}

/// One place that grew or shrank; clicking it shows it on the map.
private struct ChangeRow: View {
    @EnvironmentObject private var model: AppModel
    let change: GrowthInfo

    private var delta: Int64 {
        Int64(clamping: change.newSize) - Int64(clamping: change.oldSize)
    }

    var body: some View {
        Button { model.showChange(change) } label: {
            HStack(spacing: 10) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(delta >= 0 ? Color.orange : Color.green)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(verbatim: (delta >= 0 ? "+" : "−") + Format.bytes(delta.magnitude))
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .frame(width: 90, alignment: .leading)
                Text(CandidateLabel.abbreviatingHome(change.path, home: NSHomeDirectory()))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if change.id != nil {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(change.id == nil)
        .help(change.path)
    }
}
