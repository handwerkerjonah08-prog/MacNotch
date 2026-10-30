// Tiny CI helper that drives the real mouse pointer.
// Usage: mouse move <x> <y> | mouse click <x> <y> | mouse screen
// Coordinates are in points from the top-left of the main display.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: mouse move|click x y, or mouse screen")
    exit(1)
}

let display = CGMainDisplayID()
if args[1] == "screen" {
    let bounds = CGDisplayBounds(display)
    print("\(Int(bounds.width)) \(Int(bounds.height))")
    exit(0)
}

guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
    print("usage: mouse move|click x y")
    exit(1)
}
let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

switch args[1] {
case "move":
    CGWarpMouseCursorPosition(point)
    post(.mouseMoved)
case "click":
    CGWarpMouseCursorPosition(point)
    post(.mouseMoved)
    usleep(150_000)
    post(.leftMouseDown)
    usleep(80_000)
    post(.leftMouseUp)
default:
    print("unknown command \(args[1])")
    exit(1)
}
