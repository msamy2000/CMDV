import Foundation
import Carbon

public final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    private static weak var activeInstance: HotKeyManager?

    public init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        Self.activeInstance = self
    }

    deinit {
        unregister()
    }

    /// Registers `Cmd + Shift + V` (`kVK_ANSI_V = 0x09`, `cmdKey | shiftKey`) globally via Carbon.
    @discardableResult
    public func registerCmdShiftV() -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == HotKeyManager.signature {
                DispatchQueue.main.async {
                    HotKeyManager.activeInstance?.onTrigger()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_V) // 0x09

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// FourCharCode `'CMDV'` (`0x434D4456`)
    private static let signature: OSType = 0x434D4456
}
