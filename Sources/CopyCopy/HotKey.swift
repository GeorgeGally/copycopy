import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKey {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register() -> OSStatus {
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
        for (index, extra) in [UInt32(0), UInt32(shiftKey)].enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x434F5059, id: UInt32(index + 1))
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | optionKey | controlKey) | extra,
                                             id, GetApplicationEventTarget(), 0, &reference)
            guard status == noErr else {
                unregister()
                return status
            }
            if let reference { references.append(reference) }
        }
        return noErr
    }

    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
