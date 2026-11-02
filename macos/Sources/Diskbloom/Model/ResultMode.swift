/// How scan results are shown.
enum ResultMode: String, CaseIterable, Identifiable {
    case map, largest, duplicates, types
    var id: String { rawValue }
}
