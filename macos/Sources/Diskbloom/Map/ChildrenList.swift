import DiskbloomKit
import SwiftUI

/// The focused folder's contents next to the map.
struct ChildrenList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.children, id: \.id) { child in
                        ChildRow(node: child, total: model.focusInfo?.size ?? 1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Breadcrumbs()
            if let focus = model.focusInfo {
                HStack(spacing: 4) {
                    Text("\(Format.bytes(focus.size)) · \(Format.count(focus.files)) files")
                    if model.crumbs.count > 1 {
                        Text("· \(Format.percent(focus.size, of: model.rootSize)) of \(model.rootTitle)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if model.hiddenSpace > 0, model.crumbs.count == 1 {
                Text("Hidden space: \(Format.bytes(model.hiddenSpace))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Used on the volume but not visible to the scan: system volume, snapshots, folders without permission.")
            }
        }
    }
}
