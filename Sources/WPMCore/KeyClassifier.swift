import Foundation

/// The only information about a keystroke that ever leaves the event tap.
/// The actual character is never inspected, stored or forwarded, so typed
/// text cannot be reconstructed from anything this app keeps.
public enum KeyKind: Sendable, Equatable {
    /// A printable character (letter, digit, punctuation).
    case character
    /// Space, Return or Tab: ends a word.
    case separator
    /// Delete (backspace). Counted for accuracy, never for speed.
    case backspace
}

/// Modifier state relevant to classification (a subset of CGEventFlags,
/// kept platform-neutral so it can be unit tested).
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// Maps macOS virtual key codes (kVK_* from Carbon's Events.h) to a `KeyKind`.
/// Layout-independent: key codes are physical positions, so this works for any
/// keyboard layout without ever translating to characters.
public enum KeyClassifier {
    public static let delete: UInt16 = 51          // kVK_Delete (backspace)
    public static let space: UInt16 = 49           // kVK_Space
    public static let returnKey: UInt16 = 36       // kVK_Return
    public static let keypadEnter: UInt16 = 76     // kVK_ANSI_KeypadEnter
    public static let tab: UInt16 = 48             // kVK_Tab

    /// Letters, digits and punctuation on the main block (kVK_ANSI_A ... kVK_ANSI_Grave),
    /// ISO section key, JIS extras, and the numeric keypad's printable keys.
    static let printable: Set<UInt16> = {
        var s = Set<UInt16>(0...50)
        s.subtract([returnKey, tab, space])
        s.formUnion([10])                               // kVK_ISO_Section
        s.formUnion([93, 94, 95])                       // JIS Yen, Underscore, KeypadComma
        s.formUnion([65, 67, 69, 75, 78, 81])           // keypad . * + / - =
        s.formUnion(82...92)                            // keypad 0-9
        return s
    }()

    /// Returns nil for keys that should not be counted at all
    /// (arrows, function keys, modifiers, shortcuts, auto-repeat).
    public static func classify(keyCode: UInt16,
                                modifiers: KeyModifiers = [],
                                isAutoRepeat: Bool = false) -> KeyKind? {
        // Holding a key down isn't typing.
        if isAutoRepeat { return nil }
        // Shortcuts like ⌘C or ⌃A aren't typing. Option alone still produces
        // real characters (é, ß, …) on macOS, so it counts.
        if modifiers.contains(.command) || modifiers.contains(.control) { return nil }
        switch keyCode {
        case delete: return .backspace
        case space, returnKey, keypadEnter, tab: return .separator
        default: return printable.contains(keyCode) ? .character : nil
        }
    }
}
