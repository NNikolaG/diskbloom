import SwiftUI

/// The path from the scanned root to the focused folder; each part zooms out to it.
struct Breadcrumbs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Button(model.title(node)) { model.zoom(to: node.id) }
                            .buttonStyle(.link)
                            .font(index == model.crumbs.count - 1 ? .headline : .body)
                            .lineLimit(1)
                            .fixedSize()
                            .id(node.id)
                    }
                }
            }
            .onChange(of: model.focus) { id in proxy.scrollTo(id, anchor: .trailing) }
        }
    }
}
