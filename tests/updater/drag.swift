// A mouse drag with the left button, as a person drags an icon in Finder (live-proof-macos.sh).
// Usage: drag <from x> <from y> <to x> <to y>   (screen points)
import CoreGraphics
import Foundation

let v = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard v.count == 4 else { FileHandle.standardError.write("usage: drag x1 y1 x2 y2\n".data(using: .utf8)!); exit(2) }
let from = CGPoint(x: v[0], y: v[1]), to = CGPoint(x: v[2], y: v[3])
func post(_ type: CGEventType, _ p: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved, from); usleep(400_000)
post(.leftMouseDown, from); usleep(400_000)
for i in 1...40 {
  let t = Double(i) / 40
  post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
  usleep(25_000)
}
// Let go at once: a pause over a folder opens it (spring-loading), and the drop then lands in that
// window instead of on the folder.
usleep(150_000)
post(.leftMouseUp, to)
