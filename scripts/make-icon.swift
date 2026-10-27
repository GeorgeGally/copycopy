// Builds the icons from Resources/AppIcon-source.png.
// The mark is that picture, not the geometry that used to live here:
// python3 scripts/make-icon.py writes AppIcon.icns and the menu-bar
// template images. This stays so `swift scripts/make-icon.swift` still
// regenerates them.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let script = root.appendingPathComponent("make-icon.py")
let python = Process()
python.executableURL = URL(fileURLWithPath: "/usr/bin/env")
python.arguments = ["python3", script.path] + Array(CommandLine.arguments.dropFirst())
try python.run()
python.waitUntilExit()
exit(python.terminationStatus)
