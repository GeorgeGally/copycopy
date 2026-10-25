import AppKit

LegacyPreferences.carryOver()
let application = NSApplication.shared
let delegate = AppDelegate(demo: DemoShot.parse(CommandLine.arguments))
application.delegate = delegate
application.run()
