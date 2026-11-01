/// What the detail area shows.
enum ScanPhase: Equatable {
    /// The overview of the selected place (or the empty state).
    case idle
    case scanning(path: String, scanned: UInt64)
    /// Results of the last scan.
    case ready
    case failed(String)
}
