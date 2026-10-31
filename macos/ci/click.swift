// CI pomocnik: klik misem na (x, y) u tackama ekrana.  swift click.swift 800 200
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let p = CGPoint(x: Double(args[1])!, y: Double(args[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(200_000)
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(100_000)
}
