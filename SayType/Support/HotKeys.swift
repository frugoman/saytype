import AppKit
import Carbon.HIToolbox
import Foundation

/// A key combination, stored in preferences.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32
    var label: String

    /// Builds a shortcut from a key-down event, or nil when the combination isn't usable as a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mask: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) { mask |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { mask |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { mask |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { mask |= UInt32(cmdKey); prefix += "⌘" }
        let isFunctionKey = Self.functionKeyNames[Int(event.keyCode)] != nil
        // Plain letters would break typing; require a modifier unless it's an F-key.
        guard mask != 0 || isFunctionKey else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = mask
        label = prefix + Self.keyName(event)
    }

    init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.label = label
    }

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        let code = Int(event.keyCode)
        if let name = functionKeyNames[code] { return name }
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// The actions that can be bound to a global shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleDictation, pushToTalk, speakSelection, editSelection

    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleDictation: return "Turn dictation on or off"
        case .pushToTalk: return "Push to talk / toggle recording"
        case .speakSelection: return "Read selected text aloud"
        case .editSelection: return "Edit selected text by voice"
        }
    }
    var defaultShortcut: Shortcut {
        switch self {
        case .toggleDictation: return Shortcut(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey, label: "⌃⌥D")
        case .pushToTalk: return Shortcut(keyCode: kVK_Space, modifiers: controlKey | optionKey, label: "⌃⌥Space")
        case .speakSelection: return Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey, label: "⌃⌥S")
        case .editSelection: return Shortcut(keyCode: kVK_ANSI_E, modifiers: controlKey | optionKey, label: "⌃⌥E")
        }
    }
    var prefKey: String { "shortcut." + rawValue }

    var shortcut: Shortcut {
        guard let data = Pref.defaults.data(forKey: prefKey),
              let saved = try? JSONDecoder().decode(Shortcut.self, from: data) else { return defaultShortcut }
        return saved
    }

    func save(_ shortcut: Shortcut?) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            Pref.defaults.set(data, forKey: prefKey)
        } else {
            Pref.defaults.removeObject(forKey: prefKey)
        }
    }
}

/// System-wide keyboard shortcuts via Carbon's RegisterEventHotKey
/// (works in the App Sandbox and needs no extra permission).
final class HotKeys {
    private struct Handlers {
        var pressed: () -> Void
        var released: (() -> Void)?
    }
    private var handlers: [UInt32: Handlers] = [:]
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let handlers = me.handlers[hotKeyID.id] else { return }
                if released { handlers.released?() } else { handlers.pressed() }
            }
            return noErr
        }, specs.count, &specs, selfPtr, &eventHandler)
    }

    /// Registers a shortcut. Returns false when another app already owns that combination.
    @discardableResult
    func register(_ shortcut: Shortcut, onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5654_5950), id: id) // 'VTYP'
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs.append(ref)
        handlers[id] = Handlers(pressed: onPress, released: onRelease)
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
