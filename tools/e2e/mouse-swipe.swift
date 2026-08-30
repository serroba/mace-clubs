// A synthetic swipe across the watch screen, for the 30 manifest devices
// that have no physical UP/DOWN keys (the venu 4 family, venux1, vivoactive6,
// the vivoactive3 variants, and everything else in that class).
//
// On those, an arrow key event is simply dropped - the driver's press("down")
// was a silent no-op, which showed up as every test wedging on the equipment
// picker unable to move the Menu2 selection. A swipe raises the same
// next/previous-page behaviour the keys do (confirmed in the simulator on
// vivoactive6: a swipe up cycles the workout preset exactly as DOWN does on
// the Instinct), so that is what stands in.
//
// Sibling of mouse-hold.swift, and for the same underlying reason: the
// simulator takes synthetic *mouse* input reliably and synthetic keyboard
// input only for plain taps. See that file's header for the eight keyboard
// approaches ruled out.
//
// The intermediate drag events matter. A bare down/up pair at two different
// points is a click at the second point, not a swipe - the simulator needs to
// see the pointer travel to recognize the gesture.

import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 4,
    let x1 = Double(CommandLine.arguments[1]),
    let y1 = Double(CommandLine.arguments[2]),
    let x2 = Double(CommandLine.arguments[3]),
    let y2 = Double(CommandLine.arguments[4])
else {
    FileHandle.standardError.write("usage: mouse-swipe.swift <x1> <y1> <x2> <y2>\n".data(using: .utf8)!)
    exit(1)
}

let steps = 14
let stepDelayMicroseconds: UInt32 = 12_000

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

post(.leftMouseDown, CGPoint(x: x1, y: y1))
for step in 1...steps {
    let progress = Double(step) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * progress, y: y1 + (y2 - y1) * progress))
    usleep(stepDelayMicroseconds)
}
post(.leftMouseUp, CGPoint(x: x2, y: y2))
