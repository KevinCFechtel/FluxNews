import Carbon
import Foundation

private let fluxNewsHotKeyID = EventHotKeyID(signature: 0x464C5558, id: 1)

enum GlobalShortcutChoice: String, CaseIterable {
    case optionCommandF
    case controlOptionF
    case disabled

    private static let defaultsKey = "FluxNews.globalShortcut"

    static func stored(in defaults: UserDefaults = .standard) -> GlobalShortcutChoice {
        defaults.string(forKey: defaultsKey).flatMap(GlobalShortcutChoice.init(rawValue:)) ?? .optionCommandF
    }

    func store(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }

    var title: String {
        switch self {
        case .optionCommandF: return String(localized: "Option-Command-F")
        case .controlOptionF: return String(localized: "Control-Option-F")
        case .disabled: return String(localized: "Disabled")
        }
    }

    fileprivate var registration: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .optionCommandF: return (UInt32(kVK_ANSI_F), UInt32(optionKey | cmdKey))
        case .controlOptionF: return (UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey))
        case .disabled: return nil
        }
    }
}

@MainActor
final class GlobalShortcutRegistrar {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var eventHandlerStatus = OSStatus(eventNotHandledErr)
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        eventHandlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == fluxNewsHotKeyID.signature, identifier.id == fluxNewsHotKeyID.id else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { registrar.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: GlobalShortcutChoice) -> OSStatus {
        guard eventHandlerStatus == noErr else { return eventHandlerStatus }
        guard let registration = shortcut.registration else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            return noErr
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(registration.keyCode, registration.modifiers, fluxNewsHotKeyID, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { return status }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        return noErr
    }
}
