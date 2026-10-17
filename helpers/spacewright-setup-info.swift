import AppKit

guard CommandLine.arguments.count == 3 else { exit(2) }
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let alert = NSAlert()
alert.messageText = CommandLine.arguments[1]
alert.informativeText = CommandLine.arguments[2]
alert.alertStyle = .informational
alert.addButton(withTitle: "OK")
application.activate(ignoringOtherApps: true)
alert.runModal()
