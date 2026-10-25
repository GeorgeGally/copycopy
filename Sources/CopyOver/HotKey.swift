import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    static let defaultsKey = "hotKeyShortcut"
    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .option, .control])

    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }

    init?(storedValue: String) {
        let parts = storedValue.split(separator: ":")
        guard parts.count == 2, let key = UInt32(parts[0]), let raw = UInt(parts[1]) else { return nil }
        self.init(keyCode: key, modifiers: NSEvent.ModifierFlags(rawValue: raw))
    }

    var storedValue: String { "\(keyCode):\(modifiers.rawValue)" }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var title: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Shortcut.keyName(for: keyCode)
    }

    var words: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(Shortcut.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    static func stored(in defaults: UserDefaults = .standard) -> Shortcut {
        defaults.string(forKey: defaultsKey).flatMap(Shortcut.init(storedValue:)) ?? .standard
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(storedValue, forKey: Shortcut.defaultsKey)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "Forward Delete", kVK_ANSI_KeypadEnter: "Enter",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"
    ]

    static func keyName(for keyCode: UInt32) -> String {
        if let name = namedKeys[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(-1) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                  characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

@MainActor
final class HotKey {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private(set) var shortcut = Shortcut.stored()
    var onPress: (() -> Void)?

    @discardableResult
    func register() -> OSStatus { register(shortcut) }

    @discardableResult
    func register(_ new: Shortcut) -> OSStatus {
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().onPress?()
                }
                return noErr
            }, 1, &event, context, &handler)
            guard result == noErr else { return result }
        }
        if new == shortcut, !references.isEmpty { return noErr }

        let base = new.carbonModifiers
        let variants: [UInt32] = base & UInt32(shiftKey) == 0 ? [base, base | UInt32(shiftKey)] : [base]
        var fresh: [EventHotKeyRef] = []
        for (index, modifiers) in variants.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x434F5059, id: UInt32(index + 1))
            let status = RegisterEventHotKey(new.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
            guard status == noErr else {
                fresh.forEach { UnregisterEventHotKey($0) }
                return status
            }
            if let reference { fresh.append(reference) }
        }
        references.forEach { UnregisterEventHotKey($0) }
        references = fresh
        shortcut = new
        new.store()
        NSLog("CopyOver hotkey registered: %@", new.title)
        return noErr
    }

    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
