/// How scan results are shown.
enum ResultMode: String, CaseIterable, Identifiable {
    case map, largest, duplicates
    var id: String { rawValue }
}
