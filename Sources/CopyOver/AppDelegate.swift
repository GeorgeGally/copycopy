import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let demo: DemoShot.Invocation?
    private let store: HistoryStore
    private lazy var watcher = ClipboardWatcher(store: store)
    private lazy var bezel = BezelController(store: store)
    private let hotKey = HotKey()
    private lazy var preferences = PreferencesController(hotKey: hotKey)
    private var statusItem: NSStatusItem?
    private var pasteTarget: NSRunningApplication?
    private var hotKeyError: String?
    private var hasPromptedAccessibility = false
    private static let lastSelectedKey = "lastSelectedItemID"

    init(demo: DemoShot.Invocation? = nil) {
        self.demo = demo
        if let demo { try? FileManager.default.removeItem(at: demo.kind.directory) }
        store = HistoryStore(directory: demo?.kind.directory)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("CopyOver history loaded: %d items", store.items.count)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "CopyOver")
        status.button?.toolTip = "CopyOver"
        status.button?.setAccessibilityLabel("CopyOver")
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        statusItem = status
        bezel.onSelect = { [weak self] in self?.paste($0) }
        if let demo {
            runDemo(demo)
            return
        }
        hotKey.onPress = { [weak self] in self?.showBezel() }
        preferences.onChange = { [weak self] in self?.hotKeyError = nil }
        let result = hotKey.register()
        NSLog("CopyOver hotkey registration status: %d", result)
        PasteLog.write("launch \(Bundle.main.bundlePath) trusted=\(accessibilityTrusted(prompt: false)) canPostEvents=\(CGPreflightPostEventAccess())")
        if result != noErr {
            hotKeyError = "Shortcut unavailable. Quit another app using \(hotKey.shortcut.title) and reopen CopyOver."
        }
        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        hotKey.unregister()
        if let demo { try? FileManager.default.removeItem(at: demo.kind.directory) }
    }

    private func runDemo(_ demo: DemoShot.Invocation) {
        let kind = demo.kind
        kind.seed(into: store)
        switch kind {
        case .bezelText, .bezelImage:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                let selected = self.store.items.indices.contains(kind.selection) ? self.store.items[kind.selection].id : nil
                self.bezel.show(items: self.store.items, selectedID: selected, frontApp: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let view = self.bezel.snapshotSurface {
                        DemoRender.write(view, radius: DemoRender.bezelRadius, light: false, to: demo.output)
                    }
                    NSApp.terminate(nil)
                }
            }
        case .menu:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.popDemoMenu(demo)
            }
        }
    }

    private func popDemoMenu(_ demo: DemoShot.Invocation) {
        guard statusItem?.button?.window != nil else { return }
        let shoot = Timer(timeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if let view = NSApp.windows.first(where: { $0.level == .popUpMenu && $0.isVisible })?.contentView {
                    DemoRender.write(view, radius: DemoRender.menuRadius, light: true, to: demo.output)
                }
                self?.statusItem?.menu?.cancelTracking()
            }
        }
        let stop = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem?.menu?.cancelTracking() }
        }
        RunLoop.main.add(shoot, forMode: .common)
        RunLoop.main.add(stop, forMode: .common)
        statusItem?.button?.performClick(nil)
        NSApp.terminate(nil)
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
        add("Quit CopyOver", action: #selector(quit), to: menu)
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

    /// Return in the bezel or a menu row. Copies first; pastes only when macOS
    /// lets this app post keystrokes and the target app is back in front.
    private func paste(_ item: HistoryItem) {
        UserDefaults.standard.set(item.id, forKey: Self.lastSelectedKey)
        let front = NSWorkspace.shared.frontmostApplication
        let trusted = accessibilityTrusted(prompt: true)
        PasteLog.write("return item=\(item.label.prefix(40).debugDescription) trusted=\(trusted) canPostEvents=\(CGPreflightPostEventAccess()) frontmost=\(Self.describe(front)) target=\(Self.describe(pasteTarget))")
        guard trusted else {
            _ = copy(item)
            PasteLog.write("copied only: Accessibility is not granted to this binary (a listed CopyOver row may belong to an older build)")
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
        // A CopyOver row that is switched on but belongs to an earlier build
        // does not trust this one; only removing and re-adding it does.
        let alert = NSAlert()
        alert.messageText = "This copy of CopyOver is not trusted yet"
        alert.informativeText = "If CopyOver is already listed and switched on, that entry belongs to an earlier build. Remove it with the minus button, then add this app again:\n\(Bundle.main.bundlePath)"
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
