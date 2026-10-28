import AppKit
import Carbon

public struct ConversionShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        guard !modifierFlags.contains(.function) else { return nil }
        var mask: UInt32 = 0
        for (cocoa, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey),
                                (.shift, shiftKey), (.command, cmdKey)] {
            if modifierFlags.contains(cocoa) { mask |= UInt32(carbon) }
        }
        self.init(keyCode: keyCode, modifiers: mask)
        guard isValid else { return nil }
    }

    public static let `default` = ConversionShortcut(
        keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey | shiftKey)
    )

    // Physical letter keys keep working when the input language is Korean.
    public static let letterKeys: [(name: String, code: UInt32)] = [
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3),
        ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40), ("L", 37),
        ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15),
        ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
        ("Y", 16), ("Z", 6)
    ]

    public static let modifierChoices: [UInt32] = [
        UInt32(cmdKey | optionKey | shiftKey), UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | shiftKey | cmdKey), UInt32(controlKey | optionKey | shiftKey),
        UInt32(optionKey | cmdKey), UInt32(controlKey | cmdKey),
        UInt32(controlKey | optionKey), UInt32(shiftKey | cmdKey), UInt32(controlKey | shiftKey),
        UInt32(controlKey | optionKey | shiftKey | cmdKey)
    ]

    public var isValid: Bool {
        Self.letterKeys.contains { $0.code == keyCode } && Self.modifierChoices.contains(modifiers)
    }

    public var keyEquivalent: String {
        Self.letterKeys.first { $0.code == keyCode }?.name.lowercased() ?? ""
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for (carbon, cocoa) in [(controlKey, NSEvent.ModifierFlags.control), (optionKey, .option),
                                (shiftKey, .shift), (cmdKey, .command)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(cocoa) }
        }
        return flags
    }

    public static func modifierLabel(_ modifiers: UInt32) -> String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
    }

    public var displayName: String { Self.modifierLabel(modifiers) + keyEquivalent.uppercased() }
}

public struct ShortcutPreferences: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var shortcut: ConversionShortcut

    public init(isEnabled: Bool = true, shortcut: ConversionShortcut = .default) {
        self.isEnabled = isEnabled
        self.shortcut = shortcut
    }

    public static let storageKey = "conversionShortcutPreferences"

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(Self.self, from: data), saved.shortcut.isValid else {
            return Self()
        }
        return saved
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard shortcut.isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
