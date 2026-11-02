import DiskbloomFFI
import SwiftUI

/// Title, symbol and color for each file kind from Rust.
extension FileKind {
    var title: String {
        switch self {
        case .video: String(localized: "Video")
        case .images: String(localized: "Images")
        case .audio: String(localized: "Audio")
        case .archives: String(localized: "Archives & disk images")
        case .documents: String(localized: "Documents")
        case .code: String(localized: "Code & projects")
        case .apps: String(localized: "Apps")
        case .system: String(localized: "System & libraries")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .images: "photo"
        case .audio: "music.note"
        case .archives: "archivebox"
        case .documents: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .apps: "macwindow"
        case .system: "gearshape"
        case .other: "ellipsis.circle"
        }
    }

    /// Distinct hues in the soft tone of the sunburst; "Other" is gray.
    var color: Color {
        let hue: Double
        switch self {
        case .video: hue = 0.97
        case .images: hue = 0.07
        case .audio: hue = 0.78
        case .archives: hue = 0.13
        case .documents: hue = 0.58
        case .code: hue = 0.38
        case .apps: hue = 0.50
        case .system: hue = 0.67
        case .other: return Color(white: 0.6)
        }
        return Color(hue: hue, saturation: 0.55, brightness: 0.88)
    }
}
