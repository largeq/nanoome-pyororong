import Carbon
import Foundation

public enum ShortcutRegistrationError: LocalizedError {
    case invalidShortcut
    case handler(OSStatus)
    case registration(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            "사용할 수 없는 단축키입니다. 다른 조합을 선택해주세요."
        case .handler(let status):
            "단축키 처리를 준비하지 못했습니다 (\(status)). 앱을 다시 실행해주세요."
        case .registration(let status) where status == eventHotKeyExistsErr:
            "다른 앱이 이미 사용하는 단축키입니다. 다른 조합을 선택해주세요."
        case .registration(let status):
            "단축키를 등록하지 못했습니다 (\(status)). 다른 조합을 선택해주세요."
        }
    }
}

/// Registers one shortcut, without monitoring all keystrokes or synthesizing input.
/// All registration and event delivery happen on the application's main thread.
public final class GlobalConversionShortcut {
    @MainActor private static var nextID: UInt32 = 1
    let eventIdentifier: EventHotKeyID
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    @MainActor public private(set) var registeredShortcut: ConversionShortcut?
    private var isKeyDown = false

    @MainActor public init(action: @escaping @MainActor () -> Void) {
        self.action = action
        eventIdentifier = EventHotKeyID(signature: 0x5059504F, id: Self.nextID) // PYPO
        Self.nextID += 1
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @MainActor public func register(_ shortcut: ConversionShortcut) throws {
        guard shortcut.isValid else { throw ShortcutRegistrationError.invalidShortcut }
        if registeredShortcut == shortcut { return }
        if eventHandler == nil {
            var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(
                GetApplicationEventTarget(), Self.handleEvent, events.count, &events,
                Unmanaged.passUnretained(self).toOpaque(), &eventHandler
            )
            guard status == noErr else { throw ShortcutRegistrationError.handler(status) }
        }

        // Keep the old shortcut working if the replacement is already taken.
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, eventIdentifier,
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { throw ShortcutRegistrationError.registration(status) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registeredShortcut = shortcut
        isKeyDown = false
    }

    @MainActor public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        registeredShortcut = nil
        isKeyDown = false
    }

    private static let handleEvent: EventHandlerUPP = { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr else { return OSStatus(eventNotHandledErr) }
        // The application event target delivers on the main thread. Transfer
        // only value types into the actor; the C pointers stay in this callback.
        let address = UInt(bitPattern: context)
        let signature = identifier.signature
        let id = identifier.id
        let kind = GetEventKind(event)
        return MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: address)!
            let shortcut = Unmanaged<GlobalConversionShortcut>.fromOpaque(pointer).takeUnretainedValue()
            return shortcut.receive(signature: signature, id: id, kind: kind)
        }
    }

    @MainActor private func receive(signature: OSType, id: UInt32, kind: UInt32) -> OSStatus {
        guard hotKey != nil, signature == eventIdentifier.signature,
              id == eventIdentifier.id else { return OSStatus(eventNotHandledErr) }
        switch kind {
        case UInt32(kEventHotKeyReleased): isKeyDown = false
        case UInt32(kEventHotKeyPressed):
            guard !isKeyDown else { return noErr }
            isKeyDown = true
            action()
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
