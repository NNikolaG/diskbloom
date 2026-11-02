import AppKit
import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// One file in the largest-files, duplicates, file types and search lists.
struct FileRow: View {
    @Environment(AppModel.self) private var model
    let file: FileInfo
    var detail: String?
    /// A click runs this (e.g. a folder opens on the map); without it a double click
    /// opens Quick Look.
    var onOpen: (() -> Void)?
    @State private var hover = false

    var body: some View {
        let collected = model.isCollected(file.id)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(collected)
                    .foregroundStyle(collected ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(file.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            Group {
                IconButton(symbol: "eye", label: "Quick Look") { model.quickLook(file.id) }
                IconButton(symbol: "magnifyingglass", label: "Show in Finder") { model.revealInFinder(file.id) }
            }
            .opacity(hover ? 1 : 0)
            IconButton(symbol: collected ? "trash.slash" : "trash",
                       label: collected ? "Remove from Trash list" : "Add to Trash list",
                       tint: collected ? .red : .secondary) {
                model.toggleCollect(file.id)
            }
            .opacity(hover || collected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.06) : .clear)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hover = inside
            if inside { model.lastHoveredID = file.id }
        }
        .onTapGesture(count: onOpen == nil ? 2 : 1) {
            if let onOpen { onOpen() } else { model.quickLook(file.id) }
        }
        .contextMenu {
            if let onOpen { Button("Show on Map", action: onOpen) }
            Button("Quick Look") { model.quickLook(file.id) }
            Button("Show in Finder") { model.revealInFinder(file.id) }
            Button(collected ? LocalizedStringKey("Remove from Trash list") : "Add to Trash list") {
                model.toggleCollect(file.id)
            }
        }
    }

    private var subtitle: String {
        let folder = CandidateLabel.abbreviatingHome((file.path as NSString).deletingLastPathComponent,
                                                     home: NSHomeDirectory())
        return detail.map { "\(folder) · \($0)" } ?? folder
    }
}
