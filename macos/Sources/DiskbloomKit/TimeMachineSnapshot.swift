import Foundation

/// A local APFS snapshot as listed by `tmutil listlocalsnapshots /`.
public struct TimeMachineSnapshot: Identifiable, Hashable, Sendable {
    /// For example `com.apple.TimeMachine.2026-10-31-101500.local`.
    public let name: String
    public let date: Date?
    public var id: String { name }

    /// Time Machine snapshots can be deleted; other system snapshots are managed by macOS.
    public var isTimeMachine: Bool { name.hasPrefix(Self.prefix) }

    /// `2026-10-31-101500`, the argument for `tmutil deletelocalsnapshots`. That command
    /// runs with administrator rights, so only this exact format is accepted.
    public var stamp: String? {
        guard isTimeMachine else { return nil }
        let stamp = String(name.dropFirst(Self.prefix.count)).replacing(".local", with: "")
        return stamp.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$", options: .regularExpression) != nil
            ? stamp : nil
    }

    public init(name: String, date: Date?) {
        self.name = name
        self.date = date
    }

    private static let prefix = "com.apple.TimeMachine."

    /// Parses `tmutil listlocalsnapshots` output, newest first.
    public static func parse(_ output: String) -> [TimeMachineSnapshot] {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
            .map { name in
                let stamp = name.components(separatedBy: ".").dropFirst(3).first ?? ""
                return TimeMachineSnapshot(name: name, date: format.date(from: stamp))
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The shell command that deletes `snapshots`, or `nil` if none can be deleted.
    /// Only validated stamps are used, since the command runs as administrator.
    public static func deleteCommand(for snapshots: [TimeMachineSnapshot]) -> String? {
        let stamps = snapshots.compactMap(\.stamp)
        guard !stamps.isEmpty else { return nil }
        return stamps.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: " && ")
    }
}
