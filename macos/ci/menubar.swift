// CI helper for the menu bar item.
//   swift menubar.swift click      clicks Diskbloom's status item (found by its window)
//   swift menubar.swift settings   sends ⌘, to Diskbloom (opens the Settings window)
import AppKit
import CoreGraphics

let bundleID = "io.github.nnikolag.diskbloom"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("Diskbloom is not running"); exit(1)
}
let pid = app.processIdentifier

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(100_000)
}

switch CommandLine.arguments.dropFirst().first {
case "click":
    // A status item is a small window of the app at the status bar level, at the top of the screen.
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let item = windows.first { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
              info[kCGWindowLayer as String] as? Int == statusLevel,
              let bounds = info[kCGWindowBounds as String] as? [String: Double]
        else { return false }
        return (bounds["Y"] ?? 99) < 5 && (bounds["Height"] ?? 99) < 50
    }
    guard let bounds = item?[kCGWindowBounds as String] as? [String: Double],
          let x = bounds["X"], let width = bounds["Width"], let height = bounds["Height"]
    else {
        print("No status item window found for Diskbloom")
        for info in windows where info[kCGWindowOwnerPID as String] as? pid_t == pid { print(info) }
        exit(1)
    }
    let point = CGPoint(x: x + width / 2, y: (bounds["Y"] ?? 0) + height / 2)
    print("Status item at \(bounds), clicking \(point)")
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
case "settings":
    app.activate(options: [])
    usleep(1_000_000)
    let comma: CGKeyCode = 0x2B
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: comma, keyDown: down)
        event?.flags = .maskCommand
        event?.postToPid(pid)
        usleep(100_000)
    }
default:
    print("usage: swift menubar.swift click|settings"); exit(2)
}
