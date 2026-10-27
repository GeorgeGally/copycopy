import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
package final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store: HistoryStore
    private lazy var watcher = ClipboardWatcher(store: store)
    private lazy var bezel = BezelController(store: store)
    private let hotKey = HotKey()
    private lazy var preferences = PreferencesController(hotKey: hotKey, store: store)
    private var statusItem: NSStatusItem?
    private var pasteTarget: NSRunningApplication?
    private var hotKeyError: String?
    private var hasPromptedAccessibility = false

    package init(store: HistoryStore = HistoryStore()) {
        self.store = store
        super.init()
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("Roger history loaded: %d items", store.items.count)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = Self.menuBarIcon()
        status.button?.toolTip = "Roger"
        status.button?.setAccessibilityLabel("Roger")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        statusItem = status
        bezel.onSelect = { [weak self] in self?.paste($0) }
        bezel.onClose = { [weak self] in self?.rememberSelection($0) }
        hotKey.onPress = { [weak self] in self?.showBezel() }
        preferences.onChange = { [weak self] in self?.hotKeyError = nil }
        let result = hotKey.register()
        NSLog("Roger hotkey registration status: %d", result)
        PasteLog.write("launch \(Bundle.main.bundlePath) trusted=\(accessibilityTrusted(prompt: false)) canPostEvents=\(CGPreflightPostEventAccess())")
        if result != noErr {
            hotKeyError = "Shortcut unavailable. Quit another app using \(hotKey.shortcut.title) and reopen Roger."
        }
        watcher.start()
    }

    /// The bowtie from Resources, cut from the app icon by scripts/make-icon.py.
    /// As a template image macOS tints it for light and dark menu bars itself.
    /// roger-shot has no bundle, so it hands the 1x file in and the @2x
    /// beside it is picked up the way a bundle would.
    package static func menuBarIcon(file: URL? = nil) -> NSImage? {
        guard let icon = file.flatMap(Self.image(at:)) ?? NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Roger")
        }
        icon.isTemplate = true
        icon.accessibilityDescription = "Roger"
        return icon
    }

    private static func image(at file: URL) -> NSImage? {
        guard let icon = NSImage(contentsOf: file) else { return nil }
        let doubled = file.deletingLastPathComponent()
            .appendingPathComponent(file.deletingPathExtension().lastPathComponent + "@2x")
            .appendingPathExtension(file.pathExtension)
        if let rep = NSImageRep(contentsOf: doubled) {
            rep.size = icon.size
            icon.addRepresentation(rep)
        }
        return icon
    }

    package func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        hotKey.unregister()
    }

    package func menuWillOpen(_ menu: NSMenu) {
        pasteTarget = NSWorkspace.shared.frontmostApplication
        menu.removeAllItems()
        menu.minimumWidth = 300
        add("Open history  \(hotKey.shortcut.title)", action: #selector(openFromMenu), to: menu)
        menu.addItem(.separator())
        for item in store.items.prefix(20) {
            let row = add(rowTitle(for: item), action: #selector(selectFromMenu(_:)), to: menu)
            row.representedObject = item.id
            if let url = store.imageURL(for: item), let view = ImageRowView(url: url, width: menu.minimumWidth) {
                row.view = view
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
        add("Allow Pasting in Accessibility…", action: #selector(openAccessibilitySettings), to: menu)
        add("Preferences…", action: #selector(openPreferences), to: menu)
        add("Quit Roger", action: #selector(quit), to: menu)
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
        bezel.pasteAvailable = accessibilityTrusted(prompt: false)
        bezel.show(items: store.items, selectedID: selectionOpenID, frontApp: pasteTarget)
    }

    /// What the bezel was last left on, and what was newest then. A capture
    /// newer than that head opens at the top once; otherwise the bezel reopens
    /// on the remembered item, or on the newest when that item has gone.
    private var selectionOpenID: String? {
        SelectionMemory.load().selectedID(in: store.items)
    }

    private func rememberSelection(_ item: HistoryItem?) {
        guard let item else { return }
        var memory = SelectionMemory.load()
        memory.remember(item, in: store.items)
        memory.save()
    }

    @objc private func openFromMenu() {
        // Let menu tracking end before making the non-activating panel key.
        DispatchQueue.main.async { [weak self] in self?.showBezel() }
    }

    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let item = store.items.first(where: { $0.id == id }) else { return }
        DispatchQueue.main.async { [weak self] in self?.paste(item) }
    }

    /// Return in the bezel or a menu row. Copies first; pastes only when macOS
    /// lets this app post keystrokes and the target app is back in front.
    private func paste(_ item: HistoryItem) {
        rememberSelection(item)
        let front = NSWorkspace.shared.frontmostApplication
        let trusted = accessibilityTrusted(prompt: true)
        PasteLog.write("return item=\(item.label.prefix(40).debugDescription) trusted=\(trusted) canPostEvents=\(CGPreflightPostEventAccess()) frontmost=\(Self.describe(front)) target=\(Self.describe(pasteTarget))")
        guard trusted else {
            _ = copy(item)
            PasteLog.write("copied only: Accessibility is not granted to this binary (a listed Roger row may belong to an older build)")
            return
        }
        guard let target = pasteTarget, !target.isTerminated else {
            _ = copy(item)
            PasteLog.write("copied only: no target app")
            return
        }
        if !target.isActive {
            PasteLog.write("activating \(Self.describe(target)) result=\(target.activate())")
        }
        awaitFrontmost(target, waited: 0) { [weak self] in
            guard let self, self.copy(item) else { return }
            PasteLog.write("pasteboard written: \((NSPasteboard.general.types ?? []).map(\.rawValue).joined(separator: " "))")
            self.sendPaste(to: target, attemptsRemaining: 30)
        }
    }

    private static func describe(_ app: NSRunningApplication?) -> String {
        guard let app else { return "none" }
        return "\(app.localizedName ?? "?")(\(app.processIdentifier))"
    }

    private func copy(_ item: HistoryItem) -> Bool {
        do {
            try watcher.restore(item)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not copy this item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    /// The system Accessibility prompt is shown at most once per launch.
    private func accessibilityTrusted(prompt: Bool) -> Bool {
        let shouldPrompt = prompt && !hasPromptedAccessibility
        if shouldPrompt { hasPromptedAccessibility = true }
        // The key is kAXTrustedCheckOptionPrompt, spelled out because the global is not Sendable.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": shouldPrompt] as CFDictionary)
    }

    /// Waits for the target to be frontmost again, at least 60 ms and at most 400 ms.
    private func awaitFrontmost(_ target: NSRunningApplication, waited: TimeInterval, then: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            let waited = waited + 0.02
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
            if (frontmost && waited >= 0.06) || waited >= 0.4 {
                PasteLog.write("target frontmost=\(frontmost) after \(Int(waited * 1_000)) ms")
                then()
            } else {
                self.awaitFrontmost(target, waited: waited, then: then)
            }
        }
    }

    private func sendPaste(to target: NSRunningApplication, attemptsRemaining: Int) {
        // Let the pasteboard settle before the target reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !target.isTerminated else { return }
            // Do not send a modified paste while the invoking hotkey is still held.
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard modifiers.isEmpty, !self.bezel.isVisible else {
                if attemptsRemaining > 0 { self.sendPaste(to: target, attemptsRemaining: attemptsRemaining - 1) }
                else { PasteLog.write("gave up: modifiers=\(modifiers.rawValue) bezelVisible=\(self.bezel.isVisible)") }
                return
            }
            let front = NSWorkspace.shared.frontmostApplication
            guard front?.processIdentifier == target.processIdentifier else {
                PasteLog.write("not posted: frontmost is \(Self.describe(front)), target was \(Self.describe(target))")
                return
            }
            // Posted to the target's pid, so it does not depend on which window
            // the window server believes has keyboard focus.
            let source = CGEventSource(stateID: .privateState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.postToPid(target.processIdentifier)
            up?.postToPid(target.processIdentifier)
            PasteLog.write("posted Command-V created=\(down != nil && up != nil) toPid=\(target.processIdentifier) \(Self.describe(target))")
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        guard !accessibilityTrusted(prompt: false) else { return }
        // A Roger row that is switched on but belongs to an earlier build
        // does not trust this one; only removing and re-adding it does.
        let alert = NSAlert()
        alert.messageText = "This copy of Roger is not trusted yet"
        alert.informativeText = "If Roger is already listed and switched on, that entry belongs to an earlier build. Remove it with the minus button, then add this app again:\n\(Bundle.main.bundlePath)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
