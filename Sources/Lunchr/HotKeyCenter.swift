import AppKit
import Carbon.HIToolbox
import LunchrCore

/// System-wide shortcut. Carbon hot keys need no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    @discardableResult
    func register(_ hotKey: HotKey) -> Bool {
        unregister()
        installHandler()
        let id = EventHotKeyID(signature: 0x4C4E_4348, id: 1) // 'LNCH'
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

extension HotKey {
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var m: UInt32 = 0
        if flags.contains(.command) { m |= HotKey.command }
        if flags.contains(.option) { m |= HotKey.option }
        if flags.contains(.control) { m |= HotKey.control }
        if flags.contains(.shift) { m |= HotKey.shift }
        let isFunctionKey = Self.functionKeys[Int(event.keyCode)] != nil
        // Shift alone would swallow ordinary typing.
        guard m & ~HotKey.shift != 0 || isFunctionKey else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m)
    }

    var label: String {
        var s = ""
        if modifiers & HotKey.control != 0 { s += "⌃" }
        if modifiers & HotKey.option != 0 { s += "⌥" }
        if modifiers & HotKey.shift != 0 { s += "⇧" }
        if modifiers & HotKey.command != 0 { s += "⌘" }
        return s + keyLabel
    }

    private var keyLabel: String {
        let code = Int(keyCode)
        if let f = Self.functionKeys[code] { return f }
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return Self.character(keyCode) ?? "key \(keyCode)"
        }
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func character(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

enum SpotlightShortcut {
    /// Spotlight's own shortcut (symbolic hot key 64), or nil when it's turned off.
    static var current: HotKey? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        guard let entry = all?["64"] as? [String: Any] else { return .commandSpace }
        guard (entry["enabled"] as? NSNumber)?.boolValue ?? true else { return nil }
        guard let value = entry["value"] as? [String: Any],
              let p = value["parameters"] as? [NSNumber], p.count == 3 else { return .commandSpace }
        let flags = NSEvent.ModifierFlags(rawValue: p[2].uintValue)
        var m: UInt32 = 0
        if flags.contains(.command) { m |= HotKey.command }
        if flags.contains(.option) { m |= HotKey.option }
        if flags.contains(.control) { m |= HotKey.control }
        if flags.contains(.shift) { m |= HotKey.shift }
        return HotKey(keyCode: p[1].uint32Value, modifiers: m)
    }

    static func openSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!)
    }
}
