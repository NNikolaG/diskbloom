import SwiftUI

/// A centered placeholder: symbol, title and message (the system `ContentUnavailableView`,
/// with a variant for messages that must not be translated).
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
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            message
        }
    }
}
