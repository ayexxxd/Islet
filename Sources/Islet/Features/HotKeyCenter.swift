import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts through Carbon hot keys.
/// These need no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let controlOption = UInt32(controlKey | optionKey)

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var isInstalled = false

    private init() {}

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x49534C54), id: id) // "ISLT"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &reference)
        if status == noErr, let reference {
            references[id] = reference
            handlers[id] = handler
        }
    }

    func unregister(id: UInt32) {
        if let reference = references[id] {
            UnregisterEventHotKey(reference)
        }
        references[id] = nil
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            self?.handlers[id]?()
        }
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        _ = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                HotKeyCenter.shared.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
