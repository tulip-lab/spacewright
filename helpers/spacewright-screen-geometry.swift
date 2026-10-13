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
    // WindowServer bounds are authoritative even when yabai's AX event cache
    // has not caught up with a display rotation or a background window change.
    // Export IDs/PIDs only; never window titles or content.
    let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    let windows: [[String: Any]] = rows.compactMap { row -> [String: Any]? in
        guard let id = row[kCGWindowNumber as String] as? NSNumber,
              let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"] else { return nil }
        return ["id": id, "pid": pid, "frame": ["x": x, "y": y, "w": w, "h": h]]
    }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["displays": screens, "windows": windows]))
} catch {
    FileHandle.standardError.write(Data("screen geometry unavailable: \(error)\n".utf8))
    exit(1)
}
