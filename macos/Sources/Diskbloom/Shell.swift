import Foundation

/// Pokretanje sistemskih alata (xcrun simctl, docker, tmutil) van glavne niti.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    static func run(_ executable: String, _ args: [String]) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return Result(status: -1, output: error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Prva postojeca putanja alata (GUI aplikacije nemaju PATH iz shell-a).
    static func find(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var docker: String? {
        find(["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
              FileManager.default.homeDirectoryForCurrentUser.path + "/.docker/bin/docker",
              "/Applications/Docker.app/Contents/Resources/bin/docker"])
    }

    /// Komanda sa administratorskim pravima: macOS pita za lozinku.
    static func runAsAdmin(_ command: String) async -> Result {
        await MainActor.run {
            var error: NSDictionary?
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let out = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
                .executeAndReturnError(&error)
            if let error {
                return Result(status: 1, output: (error[NSAppleScript.errorMessage] as? String) ?? "error")
            }
            return Result(status: 0, output: out?.stringValue ?? "")
        }
    }
}
