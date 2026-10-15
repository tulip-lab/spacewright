// Read-only: no NSApplication, activation, windows or Apple Events.
import AppKit
import CoreGraphics
import Foundation

func finiteNumber(_ value: Any?) -> NSNumber? {
    guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
    return number
}

func finiteDisplayFrame(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> [String: CGFloat]? {
    guard x.isFinite, y.isFinite, w.isFinite, h.isFinite else { return nil }
    return ["x": x, "y": y, "w": w, "h": h]
}

func finiteWindowFrame(_ bounds: [String: Any]) -> [String: NSNumber]? {
    guard let x = finiteNumber(bounds["X"]),
          let y = finiteNumber(bounds["Y"]),
          let w = finiteNumber(bounds["Width"]),
          let h = finiteNumber(bounds["Height"]) else { return nil }
    return ["x": x, "y": y, "w": w, "h": h]
}

#if SPACEWRIGHT_GEOMETRY_SELF_TEST
let validDisplay = finiteDisplayFrame(x: 0, y: 0, w: 1620, h: 2025)
let invalidDisplay = finiteDisplayFrame(x: .infinity, y: 0, w: 1620, h: 2025)
let validWindow = finiteWindowFrame([
    "X": NSNumber(value: 10), "Y": NSNumber(value: 20),
    "Width": NSNumber(value: 800), "Height": NSNumber(value: 600),
])
let invalidWindow = finiteWindowFrame([
    "X": NSNumber(value: Double.infinity), "Y": NSNumber(value: Double.nan),
    "Width": NSNumber(value: 800), "Height": NSNumber(value: 600),
])
guard validDisplay != nil, invalidDisplay == nil,
      validWindow != nil, invalidWindow == nil else {
    FileHandle.standardError.write(Data("screen geometry finite-value self-test failed\n".utf8))
    exit(1)
}
print("OK      screen geometry rejects non-finite frames")
#else
let screens: [[String: Any]] = NSScreen.screens.compactMap { screen -> [String: Any]? in
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value) else { return nil }
    let bounds = CGDisplayBounds(id.uint32Value)
    let visible = screen.visibleFrame
    guard let frame = finiteDisplayFrame(
        x: bounds.minX + visible.minX - screen.frame.minX,
        y: bounds.minY + screen.frame.maxY - visible.maxY,
        w: visible.width,
        h: visible.height
    ) else { return nil }
    return ["uuid": CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String,
            "frame": frame]
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
              let frame = finiteWindowFrame(bounds) else { return nil }
        return ["id": id, "pid": pid, "frame": frame]
    }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["displays": screens, "windows": windows]))
} catch {
    FileHandle.standardError.write(Data("screen geometry unavailable: \(error)\n".utf8))
    exit(1)
}
#endif
