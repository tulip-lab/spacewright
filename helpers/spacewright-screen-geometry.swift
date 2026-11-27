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

func usableDisplayFrame(bounds: CGRect, screen: CGRect, visible: CGRect, menuInset: CGFloat) -> [String: CGFloat]? {
    let appKitTop = screen.maxY - visible.maxY
    let top = max(appKitTop, menuInset)
    return finiteDisplayFrame(
        x: bounds.minX + visible.minX - screen.minX,
        y: bounds.minY + top,
        w: visible.width,
        h: visible.height - (top - appKitTop)
    )
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
let secondary = CGRect(x: 1920, y: 0, width: 1314, height: 985)
let belowMenu = CGRect(x: 1920, y: 0, width: 1314, height: 954)
let dockOnly = CGRect(x: 1920, y: 50, width: 1314, height: 935)
let expected: [String: CGFloat] = ["x": 1920, "y": 31, "w": 1314, "h": 954]
guard validDisplay != nil, invalidDisplay == nil,
      validWindow != nil, invalidWindow == nil,
      usableDisplayFrame(bounds: secondary, screen: secondary, visible: secondary, menuInset: 31) == expected,
      usableDisplayFrame(bounds: secondary, screen: secondary, visible: belowMenu, menuInset: 31) == expected,
      usableDisplayFrame(bounds: secondary, screen: secondary, visible: dockOnly, menuInset: 31)?["h"] == 904,
      usableDisplayFrame(bounds: secondary, screen: secondary, visible: secondary, menuInset: 0)?["y"] == 0 else {
    FileHandle.standardError.write(Data("screen geometry self-test failed\n".utf8))
    exit(1)
}
print("OK      screen geometry rejects non-finite frames")
#else
// yabai reserves the configured menu bar on each display. AppKit can omit it
// from visibleFrame on an unfocused display, including Sidecar.
func menuBarInsets() -> ((UInt32, CFUUID) -> CGFloat)? {
    guard let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let connectionSymbol = dlsym(skylight, "SLSMainConnectionID"),
          let autohideSymbol = dlsym(skylight, "SLSGetMenuBarAutohideEnabled") else { return nil }
    let connection = unsafeBitCast(connectionSymbol, to: (@convention(c) () -> Int32).self)()
    let getAutohide = unsafeBitCast(autohideSymbol, to: (@convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32).self)
    var autohide: Int32 = 0
    guard getAutohide(connection, &autohide) == 0, autohide == 0 else { return nil }

    #if arch(arm64)
    guard let heightSymbol = dlsym(skylight, "SLSGetDisplayMenubarHeight") else { return nil }
    let getHeight = unsafeBitCast(heightSymbol, to: (@convention(c) (UInt32, UnsafeMutablePointer<UInt32>) -> Int32).self)
    return { id, _ in
        var height: UInt32 = 0
        return getHeight(id, &height) == 0 ? CGFloat(height) + 1 : 0
    }
    #elseif arch(x86_64)
    guard let spaceSymbol = dlsym(skylight, "SLSManagedDisplayGetCurrentSpace"),
          let boundsSymbol = dlsym(skylight, "SLSGetRevealedMenuBarBounds") else { return nil }
    let getSpace = unsafeBitCast(spaceSymbol, to: (@convention(c) (Int32, CFString) -> UInt64).self)
    let getBounds = unsafeBitCast(boundsSymbol, to: (@convention(c) (UnsafeMutablePointer<CGRect>, Int32, UInt64) -> Int32).self)
    return { _, uuid in
        guard let identifier = CFUUIDCreateString(nil, uuid) else { return 0 }
        let space = getSpace(connection, identifier)
        var bounds = CGRect.zero
        return space != 0 && getBounds(&bounds, connection, space) == 0 ? bounds.height + 1 : 0
    }
    #else
    return nil
    #endif
}

let menuBarInset = menuBarInsets()
let screens: [[String: Any]] = NSScreen.screens.compactMap { screen -> [String: Any]? in
    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value) else { return nil }
    let bounds = CGDisplayBounds(id.uint32Value)
    let identifier = uuid.takeRetainedValue()
    let inset = menuBarInset?(id.uint32Value, identifier) ?? 0
    guard let frame = usableDisplayFrame(
        bounds: bounds, screen: screen.frame, visible: screen.visibleFrame,
        menuInset: inset > 0 && inset < bounds.height ? inset : 0
    ) else { return nil }
    return ["uuid": CFUUIDCreateString(nil, identifier) as String,
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
