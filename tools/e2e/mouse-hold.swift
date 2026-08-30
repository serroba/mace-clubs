// Synthesizes a mouse press-and-hold at a global screen coordinate - the
// only way to trigger a held button (MENU on this device) in the Connect IQ
// simulator. Keyboard events can't do it: the simulator maps key events to
// taps only, no matter how they're synthesized (AppleScript key down/up
// pairs, raw CGEvents with correct arrow-key flags at any tap point, and
// OS-style autorepeat trains were all tried - a fast down/up pair lands as
// a tap, anything held longer is ignored outright). A human triggers MENU
// by press-and-holding the mouse on the skin's UP-button hotspot, so the
// driver does exactly that.
//
// Usage: swift tools/e2e/mouse-hold.swift <x> <y> <hold-ms>

import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 3,
    let x = Double(CommandLine.arguments[1]),
    let y = Double(CommandLine.arguments[2]),
    let holdMs = UInt32(CommandLine.arguments[3])
else {
    FileHandle.standardError.write("usage: mouse-hold.swift <x> <y> <hold-ms>\n".data(using: .utf8)!)
    exit(1)
}

let point = CGPoint(x: x, y: y)
guard
    let down = CGEvent(
        mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
    let up = CGEvent(
        mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
else {
    FileHandle.standardError.write("could not create mouse events\n".data(using: .utf8)!)
    exit(1)
}

down.post(tap: .cghidEventTap)
usleep(holdMs * 1000)
up.post(tap: .cghidEventTap)
