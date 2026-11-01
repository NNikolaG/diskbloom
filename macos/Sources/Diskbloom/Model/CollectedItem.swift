/// An item in the Trash list (the collector).
struct CollectedItem: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let path: String
    let size: UInt64
}
