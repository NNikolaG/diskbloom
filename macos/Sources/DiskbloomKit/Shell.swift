import Foundation

/// Runs command line tools (xcrun simctl, docker, tmutil) off the main thread.
public enum Shell {
    /// Exit status and combined stdout + stderr.
    public struct Result: Sendable, Equatable {
        public let status: Int32
        public let output: String
        public var succeeded: Bool { status == 0 }

        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// Runs `executable` (an absolute path) with `arguments`. No shell is involved, so
    /// arguments are never interpreted.
    public static func run(_ executable: String, _ arguments: [String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return Result(status: -1, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// The first of `candidates` that is an executable file. Apps started from Finder do
    /// not get the shell's `PATH`, so tools are looked up in their usual locations.
    public static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
