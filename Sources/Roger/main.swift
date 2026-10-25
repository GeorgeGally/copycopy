import AppKit
import RogerCore

LegacyPreferences.carryOver()
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
