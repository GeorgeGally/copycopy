import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private lazy var watcher = ClipboardWatcher(store: store)
    private lazy var bezel = BezelController(store: store)
    private let hotKey = HotKey()
    private lazy var preferences = PreferencesController(hotKey: hotKey)
    private var statusItem: NSStatusItem?
    private var pasteTarget: NSRunningApplication?
    private var hotKeyError: String?
    private static let lastSelectedKey = "lastSelectedItemID"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("CopyCopy history loaded: %d items", store.items.count)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "CopyCopy")
        status.button?.toolTip = "CopyCopy"
        status.button?.setAccessibilityLabel("CopyCopy")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        statusItem = status
        bezel.onSelect = { [weak self] in self?.paste($0) }
        hotKey.onPress = { [weak self] in self?.showBezel() }
        preferences.onChange = { [weak self] in self?.hotKeyError = nil }
        let result = hotKey.register()
        NSLog("CopyCopy hotkey registration status: %d", result)
        NSLog("CopyCopy accessibility trusted: %d", AXIsProcessTrusted() ? 1 : 0)
        if result != noErr {
            hotKeyError = "Shortcut unavailable. Quit another app using \(hotKey.shortcut.title) and reopen CopyCopy."
        }
        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        hotKey.unregister()
    }

    func menuWillOpen(_ menu: NSMenu) {
        pasteTarget = NSWorkspace.shared.frontmostApplication
        menu.removeAllItems()
        menu.minimumWidth = 300
        add("Open history  \(hotKey.shortcut.title)", action: #selector(openFromMenu), to: menu)
        menu.addItem(.separator())
        for item in store.items.prefix(20) {
            let row = add(rowTitle(for: item), action: #selector(selectFromMenu(_:)), to: menu)
            row.representedObject = item.id
            if let url = store.imageURL(for: item), let content = ImageRow.content(for: url) {
                row.image = content.thumbnail
                row.title = content.label
            }
        }
        if store.items.isEmpty {
            menu.addItem(NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: ""))
        }
        if let error = store.errorMessage ?? hotKeyError {
            let item = NSMenuItem(title: rowTitle(error, limit: 40), action: nil, keyEquivalent: "")
            item.toolTip = error
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Clear history", action: #selector(clearHistory), to: menu).isEnabled = !store.items.isEmpty
        add("Preferences…", action: #selector(openPreferences), to: menu)
        add("Quit CopyCopy", action: #selector(quit), to: menu)
    }

    private func rowTitle(for item: HistoryItem, limit: Int = 40) -> String {
        let text: String
        switch item.content {
        case .image(_, let bytes):
            text = "Image \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
        default:
            text = item.label
        }
        return rowTitle(text, limit: limit)
    }

    private func rowTitle(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard line.count > limit else { return line }
        return String(line.prefix(limit)) + "…"
    }

    private func showBezel() {
        if !bezel.isOpen { pasteTarget = NSWorkspace.shared.frontmostApplication }
        watcher.poll()
        bezel.show(items: store.items, selectedID: UserDefaults.standard.string(forKey: Self.lastSelectedKey), frontApp: pasteTarget)
    }

    @objc private func openFromMenu() {
        // Let menu tracking end before making the non-activating panel key.
        DispatchQueue.main.async { [weak self] in self?.showBezel() }
    }

    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = store.items.first(where: { $0.id == id }) else { return }
        DispatchQueue.main.async { [weak self] in self?.paste(item) }
    }

    private func paste(_ item: HistoryItem) {
        UserDefaults.standard.set(item.id, forKey: Self.lastSelectedKey)
        do {
            try watcher.restore(item)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not copy this item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        guard AXIsProcessTrusted() else {
            NSLog("CopyCopy paste: on the clipboard only; Accessibility is not granted to this build")
            offerAccessibilityOnce()
            return
        }
        guard let target = pasteTarget, !target.isTerminated else {
            NSLog("CopyCopy paste: no target app")
            return
        }
        // Let the pasteboard settle before the target reads it.
        sendPaste(to: target, attemptsRemaining: 30)
    }

    private func sendPaste(to target: NSRunningApplication, attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !target.isTerminated else { return }
            // Do not send a modified paste while the invoking hotkey is still held.
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard modifiers.isEmpty, !self.bezel.isVisible else {
                if attemptsRemaining > 0 { self.sendPaste(to: target, attemptsRemaining: attemptsRemaining - 1) }
                else { NSLog("CopyCopy paste: gave up; modifiers held or bezel still visible") }
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                NSLog("CopyCopy paste: %@ is no longer frontmost", target.localizedName ?? "target")
                return
            }
            NSLog("CopyCopy paste: Command-V to %@ with %@", target.localizedName ?? "target",
                  (NSPasteboard.general.types ?? []).map(\.rawValue).joined(separator: " "))
            let source = CGEventSource(stateID: .privateState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func offerAccessibilityOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "hasOfferedAccessibility") else { return }
        defaults.set(true, forKey: "hasOfferedAccessibility")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let alert = NSAlert()
            alert.messageText = "Copied to clipboard"
            alert.informativeText = "Allow CopyCopy in Accessibility to paste directly into other apps. You can also paste this item yourself with Command-V."
            alert.addButton(withTitle: "Open Accessibility")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @discardableResult
    private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func clearHistory() { store.clear() }
    @objc private func openPreferences() { preferences.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
