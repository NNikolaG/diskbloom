import AppKit
import DiskbloomFFI
import DiskbloomKit
import SwiftUI

/// One item in the children list: color key, name, share bar, size and a Trash list toggle.
struct ChildRow: View {
    @EnvironmentObject private var model: AppModel
    let node: NodeInfo
    let total: UInt64
    @State private var hover = false

    var body: some View {
        let collected = model.isCollected(node.id)
        // The whole row is a button: clicking a folder opens it. (.onTapGesture together
        // with dragging on macOS lets the drag swallow the click.)
        HStack(spacing: 8) {
            Button(action: open) { content(collected: collected) }
                .buttonStyle(.plain)
                .onDrag { NSItemProvider(object: String(node.id) as NSString) }
                .accessibilityLabel(Text(verbatim: "\(node.displayName), \(Format.bytes(node.size))"))
                .accessibilityHint(node.hasChildren ? Text("Open") : Text("Show in Finder"))

            IconButton(symbol: collected ? "trash.slash" : "trash",
                       label: collected ? "Remove from Trash list" : "Add to Trash list",
                       tint: collected ? .red : .secondary) {
                model.toggleCollect(node.id)
            }
            .opacity(hover || collected ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hover || model.hovered?.id == node.id ? Color.primary.opacity(0.07) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { inside in
            hover = inside
            if inside { model.lastHoveredID = node.id }
        }
        .help("\(node.displayName) — \(Format.bytes(node.size)) (\(Format.percent(node.size, of: total)))")
        .contextMenu { contextMenu(collected: collected) }
    }

    private var color: Color {
        model.segments.first { $0.id == node.id }.map { Palette.color($0) } ?? Color.gray.opacity(0.35)
    }

    private func content(collected: Bool) -> some View {
        let fraction = total > 0 ? Double(node.size) / Double(total) : 0
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Image(systemName: node.isDir ? "folder.fill" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(collected)
                    .foregroundStyle(collected ? .secondary : .primary)
                ShareBar(fraction: fraction, color: color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(node.size)).monospacedDigit()
                Text(Format.percent(node.size, of: total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func contextMenu(collected: Bool) -> some View {
        if node.hasChildren { Button("Open") { open() } }
        Button("Quick Look") { model.quickLook(node.id) }
        Button(collected ? LocalizedStringKey("Remove from Trash list") : "Add to Trash list") {
            model.toggleCollect(node.id)
        }
        Button("Show in Finder") { model.revealInFinder(node.id) }
        if node.isDir { Button("Refresh this folder") { model.refresh(node.id) } }
    }

    /// A folder opens; a file is shown in Finder.
    private func open() {
        if node.hasChildren { model.zoom(to: node.id) } else { model.revealInFinder(node.id) }
    }
}

/// How much of the focused folder an item takes.
private struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: max(2, proxy.size.width * fraction))
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
