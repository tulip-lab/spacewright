// Read-only: no NSApplication, activation, windows or Apple Events.
import AppKit
import CoreGraphics
import Foundation

let screens: [[String: Any]] = NSScreen.screens.compactMap { screen -> [String: Any]? in
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value) else { return nil }
    let bounds = CGDisplayBounds(id.uint32Value)
    let visible = screen.visibleFrame
    return ["uuid": CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String,
            "frame": ["x": bounds.minX + visible.minX - screen.frame.minX,
                      "y": bounds.minY + screen.frame.maxY - visible.maxY,
                      "w": visible.width, "h": visible.height]]
}
do {
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: screens))
} catch {
    FileHandle.standardError.write(Data("screen geometry unavailable: \(error)\n".utf8))
    exit(1)
}
