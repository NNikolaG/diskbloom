// CI helper for the menu bar item.
//   swift menubar.swift click      clicks Diskbloom's status item
//   swift menubar.swift settings   sends ⌘, to Diskbloom (opens the Settings window)
import AppKit
import ApplicationServices
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

/// The status item's frame in screen points (origin top left): from the app's
/// accessibility tree (its "extras" menu bar), else from a status-level window of the app.
func statusItemFrame() -> CGRect? {
    let element = AXUIElementCreateApplication(pid)
    var extras: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &extras) == .success,
       let bar = extras {
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement]) ?? [] {
            var position: CFTypeRef?
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &size)
            var origin = CGPoint.zero
            var extent = CGSize.zero
            if let position, let size,
               AXValueGetValue(position as! AXValue, .cgPoint, &origin),
               AXValueGetValue(size as! AXValue, .cgSize, &extent), extent.width > 0 {
                return CGRect(origin: origin, size: extent)
            }
        }
    } else {
        print("No accessibility access to the menu bar extras (trusted: \(AXIsProcessTrusted()))")
    }
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for info in windows where info[kCGWindowOwnerPID as String] as? pid_t == pid {
        print(info[kCGWindowLayer as String] ?? "?", info[kCGWindowBounds as String] ?? "?")
        guard info[kCGWindowLayer as String] as? Int == statusLevel,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.minY < 5, frame.height < 50
        else { continue }
        return frame
    }
    return nil
}

switch CommandLine.arguments.dropFirst().first {
case "click":
    guard let frame = statusItemFrame() else {
        print("No status item found for Diskbloom")
        exit(1)
    }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    print("Status item at \(frame), clicking \(point)")
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
