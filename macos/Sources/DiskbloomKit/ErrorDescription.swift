import Foundation

extension Error {
    /// The message plus domain, code and underlying error, so an alert shows exactly
    /// what macOS refused.
    public var detailedDescription: String {
        let error = self as NSError
        var text = "\(error.localizedDescription) [\(error.domain) \(error.code)]"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += "\n← \(underlying.localizedDescription) [\(underlying.domain) \(underlying.code)]"
        }
        return text
    }
}
