import AppKit
import Carbon
import XCTest
@testable import TableConverterMac

final class ConversionShortcutTests: XCTestCase {
    func testDefaultShortcutUsesPhysicalPAndCommandOptionShift() {
        let shortcut = ConversionShortcut.default
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(shortcut.modifierFlags, [.command, .option, .shift])
        XCTAssertEqual(shortcut.keyEquivalent, "p")
        XCTAssertTrue(shortcut.isValid)
        XCTAssertEqual(Set(ConversionShortcut.letterKeys.map(\.code)).count, 26)
    }

    func testRecordedShortcutUsesPhysicalKeyAndIgnoresCapsLock() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .shift, .capsLock]
        XCTAssertEqual(ConversionShortcut(keyCode: UInt32(kVK_ANSI_P), modifierFlags: flags), .default)
    }

    func testRecorderSupportsControlShiftAndAllFourModifiers() {
        XCTAssertNotNil(ConversionShortcut(keyCode: UInt32(kVK_ANSI_M), modifierFlags: [.control, .shift]))
        XCTAssertNotNil(ConversionShortcut(keyCode: UInt32(kVK_ANSI_K), modifierFlags: [.control, .option, .shift, .command]))
    }

    func testRecorderRejectsPlainKeysUnsupportedKeysAndFunctionModifier() {
        XCTAssertNil(ConversionShortcut(keyCode: UInt32(kVK_ANSI_P), modifierFlags: []))
        XCTAssertNil(ConversionShortcut(keyCode: UInt32(kVK_ANSI_P), modifierFlags: [.command]))
        XCTAssertNil(ConversionShortcut(keyCode: UInt32(kVK_Escape), modifierFlags: [.command, .shift]))
        XCTAssertNil(ConversionShortcut(keyCode: UInt32(kVK_ANSI_P), modifierFlags: [.command, .shift, .function]))
    }

    func testChangedAndDisabledShortcutSurvivesReload() throws {
        let suite = "com.phronesis.pyororong.tests.shortcuts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ShortcutPreferences.load(from: defaults), ShortcutPreferences())
        let changed = ShortcutPreferences(isEnabled: false,
            shortcut: ConversionShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey)))
        changed.save(to: defaults)
        XCTAssertEqual(ShortcutPreferences.load(from: defaults), changed)
    }

    func testCorruptOrUnsupportedSavedShortcutFallsBackToDefault() throws {
        let suite = "com.phronesis.pyororong.tests.shortcuts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: ShortcutPreferences.storageKey)
        XCTAssertEqual(ShortcutPreferences.load(from: defaults), ShortcutPreferences())
        let unsupported = ShortcutPreferences(shortcut: ConversionShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0))
        defaults.set(try JSONEncoder().encode(unsupported), forKey: ShortcutPreferences.storageKey)
        XCTAssertEqual(ShortcutPreferences.load(from: defaults), ShortcutPreferences())
    }

    @MainActor
    func testRegisteredCarbonEventConvertsNamedClipboardAndIgnoresHeldKeyRepeat() async throws {
        _ = NSApplication.shared
        let generalChangeCount = NSPasteboard.general.changeCount
        let board = NSPasteboard(name: .init("com.phronesis.pyororong.tests.hotkey.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("<table style='mso-test:yes'><tr><td>단축키 검증</td></tr></table>", forType: .html)
        let converter = ClipboardTableConverter(pasteboard: board)
        var calls = 0
        var conversionError: Error?
        let hotkey = GlobalConversionShortcut {
            calls += 1
            if calls == 1 {
                do { _ = try converter.convert() } catch { conversionError = error }
            }
        }
        defer { hotkey.unregister() }
        _ = try registerAvailable(hotkey)
        try send(kEventHotKeyPressed, to: hotkey)
        XCTAssertNil(conversionError)
        let state = await converter.clipboardState()
        XCTAssertEqual(state, .readyToPaste)
        XCTAssertEqual(board.string(forType: .string), "단축키 검증")
        try send(kEventHotKeyPressed, to: hotkey)
        XCTAssertEqual(calls, 1)
        try send(kEventHotKeyReleased, to: hotkey)
        try send(kEventHotKeyPressed, to: hotkey)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(NSPasteboard.general.changeCount, generalChangeCount)
    }

    @MainActor
    func testFailedReplacementKeepsOldShortcutAndSuccessfulReplacementReleasesIt() async throws {
        _ = NSApplication.shared
        var calls = 0
        let first = GlobalConversionShortcut { calls += 1 }
        let second = GlobalConversionShortcut {}
        defer { first.unregister(); second.unregister() }
        let original = try registerAvailable(first)
        let occupied = try registerAvailable(second)
        XCTAssertNotEqual(original, occupied)
        XCTAssertThrowsError(try first.register(occupied))
        XCTAssertEqual(first.registeredShortcut, original)
        try send(kEventHotKeyPressed, to: first)
        XCTAssertEqual(calls, 1)
        second.unregister()
        try first.register(occupied)
        XCTAssertEqual(first.registeredShortcut, occupied)
        try second.register(original)
        XCTAssertEqual(second.registeredShortcut, original)
    }

    @MainActor
    func testUnregisterStopsCallbacksAndReleasesShortcut() async throws {
        _ = NSApplication.shared
        var calls = 0
        let first = GlobalConversionShortcut { calls += 1 }
        let second = GlobalConversionShortcut {}
        defer { first.unregister(); second.unregister() }
        let combination = try registerAvailable(first)
        first.unregister()
        XCTAssertNil(first.registeredShortcut)
        try send(kEventHotKeyPressed, to: first, requireHandled: false)
        XCTAssertEqual(calls, 0)
        try second.register(combination)
    }

    @MainActor
    private func registerAvailable(_ hotkey: GlobalConversionShortcut) throws -> ConversionShortcut {
        for key in ConversionShortcut.letterKeys.reversed() {
            let combination = ConversionShortcut(keyCode: key.code, modifiers: ConversionShortcut.default.modifiers)
            do {
                try hotkey.register(combination)
                return combination
            } catch ShortcutRegistrationError.registration(let status) where status == eventHotKeyExistsErr {
                continue
            }
        }
        throw XCTSkip("All test shortcut combinations are already registered by other applications.")
    }

    @MainActor
    private func send(_ kind: Int, to hotkey: GlobalConversionShortcut, requireHandled: Bool = true) throws {
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), GetCurrentEventTime(),
                                   EventAttributes(kEventAttributeNone), &event), noErr)
        let created = try XCTUnwrap(event)
        defer { ReleaseEvent(created) }
        var identifier = hotkey.eventIdentifier
        XCTAssertEqual(SetEventParameter(created, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
        let status = SendEventToEventTarget(created, GetApplicationEventTarget())
        if requireHandled { XCTAssertEqual(status, noErr) }
    }
}
