import SwiftUI

/// Filter for files not opened for a while.
enum FileAge: String, CaseIterable, Identifiable {
    case any, sixMonths, year
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .any: return "All"
        case .sixMonths: return "Not opened in 6 months"
        case .year: return "Not opened in a year"
        }
    }
    var cutoff: Date? {
        switch self {
        case .any: return nil
        case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: Date())
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: Date())
        }
    }
}
