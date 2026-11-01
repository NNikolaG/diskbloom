import SwiftUI

/// A centered placeholder: symbol, title and message.
struct ContentUnavailable: View {
    let title: LocalizedStringKey
    let message: Text
    let symbol: String

    init(title: LocalizedStringKey, message: LocalizedStringKey, symbol: String) {
        self.title = title
        self.message = Text(message)
        self.symbol = symbol
    }

    /// A message that is not translated, such as an error text from the system.
    init(title: LocalizedStringKey, verbatim message: String, symbol: String) {
        self.title = title
        self.message = Text(verbatim: message)
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold())
            message
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
