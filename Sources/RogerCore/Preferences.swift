import AppKit
import Carbon.HIToolbox

/// The bundle identifier changed with the rename, and preferences live in the
/// bundle's domain, so the old domain is copied across once on first launch.
package enum LegacyPreferences {
    static let domain = "com.george.copyover"

    package static func carryOver(into defaults: UserDefaults = .standard) {
        guard let legacy = UserDefaults(suiteName: domain),
              let values = legacy.persistentDomain(forName: domain) else { return }
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}

@MainActor
final class PreferencesController: NSObject, NSWindowDelegate {
    private let hotKey: HotKey
    private let window: NSWindow
    private let field = ShortcutField()
    private let caption = NSTextField(labelWithString: "")
    private let message = NSTextField(labelWithString: "")
    var onChange: (() -> Void)?

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()

        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let content = window.contentView ?? NSView()

        field.frame = NSRect(x: 20, y: 58, width: 260, height: 40)
        field.shortcut = hotKey.shortcut
        field.onCapture = { [weak self] in self?.apply($0) }
        content.addSubview(field)

        caption.frame = NSRect(x: 20, y: 36, width: 260, height: 16)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        content.addSubview(caption)

        message.frame = NSRect(x: 20, y: 16, width: 260, height: 16)
        message.font = .systemFont(ofSize: 11)
        message.textColor = .systemRed
        message.alignment = .center
        message.lineBreakMode = .byTruncatingTail
        content.addSubview(message)
    }

    func show() {
        field.shortcut = hotKey.shortcut
        field.stopRecording()
        caption.stringValue = hotKey.shortcut.words
        message.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        field.stopRecording()
    }

    private func apply(_ shortcut: Shortcut) {
        guard hotKey.register(shortcut) == noErr else {
            field.stopRecording()
            message.stringValue = "That shortcut is already in use."
            return
        }
        field.shortcut = shortcut
        field.stopRecording()
        caption.stringValue = shortcut.words
        message.stringValue = ""
        NSLog("Roger hotkey changed: %@", shortcut.title)
        onChange?()
    }
}

@MainActor
final class ShortcutField: NSView {
    var shortcut: Shortcut = .standard { didSet { needsDisplay = true } }
    var onCapture: ((Shortcut) -> Void)?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return
        }
        onCapture?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.quaternaryLabelColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "Press a shortcut" : shortcut.title
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}
