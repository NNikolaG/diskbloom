import SwiftUI

/// A small borderless symbol button with a tooltip and an accessibility label.
struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}
