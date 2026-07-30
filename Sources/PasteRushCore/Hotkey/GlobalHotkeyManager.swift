import AppKit
import Carbon
import Foundation

public final class GlobalHotkeyManager {
    public static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var eventHandlerInstalled = false
    public var onHotkey: (() -> Void)?
    public private(set) var lastError: String?

    public init() {}

    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()
        lastError = nil

        if !eventHandlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        manager.onHotkey?()
                    }
                }
                return noErr
            }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &handlerRef)
            if status != noErr {
                lastError = "Nie udało się zainstalować handlera skrótu (\(status))"
                return false
            }
            eventHandlerInstalled = true
        }

            let hotKeyID = EventHotKeyID(signature: OSType(0x50525348), id: 1) // 'PRSH'
            let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            lastError = "Wybrana kombinacja jest zajęta lub niedostępna (kod \(status))"
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    public func reregisterFromSettings() {
        let settings = SettingsStore.shared
        _ = register(keyCode: settings.openHotkeyKeyCode, modifiers: settings.openHotkeyModifiers)
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    public static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeSymbol(keyCode))
        return parts.joined()
    }

    private static func keyCodeSymbol(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 50: return "`"
        case 49: return "Space"
        case 36: return "↩"
        case 53: return "Esc"
        default: return "Key\(keyCode)"
        }
    }
}
