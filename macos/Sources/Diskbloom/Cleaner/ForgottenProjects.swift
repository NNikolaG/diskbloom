import DiskbloomKit
import SwiftUI

/// Build folders and dependencies of projects nobody changed for six months.
struct ForgottenProjects: View {
    let items: [CleanGroup.Item]
    let selectThese: () -> Void

    var body: some View {
        if !items.isEmpty {
            let size = items.reduce(UInt64(0)) { $0 + $1.candidate.size }
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: 34, height: 34)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forgotten projects").font(.headline)
                    Text("\(Format.bytes(size)) in \(Format.count(items.count)) project folders you haven't changed for 6 months.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select only these", action: selectThese)
            }
            .padding(12)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 4)
        }
    }
}
