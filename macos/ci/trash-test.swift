// CI provera: da li macOS pusta u Trash putanje kroz /System/Volumes/Data i kroz /Users.
import AppKit

func recycle(_ path: String) -> String {
    let sem = DispatchSemaphore(value: 0)
    var result = ""
    DispatchQueue.main.async {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: path)]) { moved, error in
            result = error.map { "FAIL: \($0.localizedDescription)" } ?? "OK (\(moved.count) moved)"
            sem.signal()
        }
    }
    while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return result
}

let home = FileManager.default.homeDirectoryForCurrentUser.path
for name in ["via-data", "via-users"] {
    try! FileManager.default.createDirectory(atPath: "\(home)/trtest/\(name)/node_modules", withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(home)/trtest/\(name)/node_modules/x.js", contents: Data("x".utf8))
}
print("/System/Volumes/Data path:", recycle("/System/Volumes/Data\(home)/trtest/via-data/node_modules"))
print("/Users path:              ", recycle("\(home)/trtest/via-users/node_modules"))
