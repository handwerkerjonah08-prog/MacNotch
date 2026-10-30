// Tiny CI helper that drives the real mouse pointer.
// Usage: mouse move <x> <y> | mouse click <x> <y> | mouse drag <x1> <y1> <x2> <y2> | mouse screen | mouse menubar
// Coordinates are in points from the top-left of the main display.
import AppKit
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
if args[1] == "menubar" {
    let screen = NSScreen.screens.first
    let height = (screen?.frame.maxY ?? 0) - (screen?.visibleFrame.maxY ?? 0)
    print(Int(height.rounded()))
    exit(0)
}
if args[1] == "drag", args.count == 6,
   let x1 = Double(args[2]), let y1 = Double(args[3]), let x2 = Double(args[4]), let y2 = Double(args[5]) {
    func send(_ type: CGEventType, _ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
    let start = CGPoint(x: x1, y: y1)
    CGWarpMouseCursorPosition(start)
    send(.mouseMoved, start)
    usleep(200_000)
    send(.leftMouseDown, start)
    usleep(150_000)
    let steps = 30
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        let point = CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
        send(.leftMouseDragged, point)
        usleep(20_000)
    }
    usleep(200_000)
    send(.leftMouseUp, CGPoint(x: x2, y: y2))
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
