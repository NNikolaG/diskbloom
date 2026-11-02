import SwiftUI

/// The path from the scanned root to the focused folder; each part zooms out to it.
struct Breadcrumbs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
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
            .scrollIndicators(.hidden)
            .onChange(of: model.focus) { _, id in proxy.scrollTo(id, anchor: .trailing) }
        }
    }
}
