import SwiftUI

/// A checkbox with a mixed state, for category rows.
struct CheckBox: View {
    enum State { case off, on, mixed }

    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Select"))
        .accessibilityValue(Text(state == .on ? "On" : state == .mixed ? "Mixed" : "Off"))
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}
