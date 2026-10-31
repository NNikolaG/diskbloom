import AppKit
import DiskbloomFFI
import SwiftUI

/// Red za jedan fajl u listama "Largest files" i "Duplicates".
struct FileRow: View {
    @EnvironmentObject var model: AppModel
    let file: FileInfo
    var detail: String? = nil
    @State private var hover = false

    var body: some View {
        let collected = model.isCollected(file.id)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1).truncationMode(.middle)
                    .strikethrough(collected)
                    .foregroundStyle(collected ? .secondary : .primary)
                Text(detail.map { "\(FileRow.shortPath(file.path)) · \($0)" } ?? FileRow.shortPath(file.path))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.bytes(file.size)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            Group {
                iconButton("eye", help: "Quick Look") { model.quickLook(file.id) }
                iconButton("magnifyingglass", help: "Show in Finder") { model.revealInFinder(file.id) }
            }
            .opacity(hover ? 1 : 0)
            iconButton(collected ? "trash.slash" : "trash",
                       help: collected ? "Remove from Trash list" : "Add to Trash list",
                       tint: collected ? .red : .secondary) {
                model.toggleCollect(file.id)
            }
            .opacity(hover || collected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { h in
            hover = h
            if h { model.lastHoveredID = file.id }
        }
        .onTapGesture(count: 2) { model.quickLook(file.id) }
        .contextMenu {
            Button("Quick Look") { model.quickLook(file.id) }
            Button("Show in Finder") { model.revealInFinder(file.id) }
            Button(collected ? LocalizedStringKey("Remove from Trash list") : "Add to Trash list") { model.toggleCollect(file.id) }
        }
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, tint: Color = .secondary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func shortPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = (p as NSString).deletingLastPathComponent
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }
}
