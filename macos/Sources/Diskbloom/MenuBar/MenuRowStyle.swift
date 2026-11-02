import SwiftUI

/// A full-width row that highlights under the pointer, like a menu item.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(hovering && isEnabled ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering && isEnabled ? Color.accentColor : .clear)
                        .opacity(configuration.isPressed ? 0.8 : 1)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
