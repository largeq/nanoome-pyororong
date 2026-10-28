import AppKit
import Carbon
import TableConverterMac

@MainActor
private final class ShortcutChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await ShortcutSettingsIntegrationChecks.run()
                print("Shortcut settings integration checks passed: recording, validation, conflict recovery, save/cancel, disabled restore, keyboard, mouse tracking, layout, and appearances.")
                NSApp.terminate(nil)
            } catch {
                fputs("Shortcut settings check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

@main
struct ShortcutSettingsIntegrationChecks {
    @MainActor private static var mouseEventNumber = 0

    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ShortcutChecksDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor fileprivate static func run() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "com.phronesis.pyororong.tests.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clipboardRevision = NSPasteboard.general.changeCount
        let original = ConversionShortcut(keyCode: UInt32(kVK_ANSI_Y), modifierFlags: [.control, .option, .shift, .command])!
        let replacement = ConversionShortcut(keyCode: UInt32(kVK_ANSI_M), modifierFlags: [.control, .shift])!
        var saved = ShortcutPreferences(shortcut: original)
        saved.save(to: defaults)
        var applyCount = 0
        var failRegistration = false
        var recordingChanges: [Bool] = []
        // Exercise the real controller without registering shortcuts or touching the user's preferences.
        let controller = ShortcutSettingsController(onApply: { value in
            if failRegistration { throw ShortcutRegistrationError.registration(OSStatus(eventHotKeyExistsErr)) }
            value.save(to: defaults)
            saved = value
            applyCount += 1
        }, onRecordingChanged: { recordingChanges.append($0) })
        defer { controller.close() }
        let window = controller.window as! ShortcutRecordingWindow
        let recorder: ShortcutRecorderButton = try property("recorder", controller)
        let enabled: NSButton = try property("enabled", controller)
        let label: NSTextField = try property("shortcutLabel", controller)
        let help: NSTextField = try property("helpLabel", controller)
        let error: NSTextField = try property("errorLabel", controller)
        let guidance: NSTextField = try property("inputGuidance", controller)
        let save: NSButton = try property("saveButton", controller)
        let buttons = descendants(window.contentView!).compactMap { $0 as? NSButton }
        let cancel = buttons.first { $0.title == "취소" }!
        let reset = buttons.first { $0.title == "기본 단축키로 복원" }!

        controller.show(preferences: saved)
        try await makeKey(window)
        try require(window.title == "단축키 설정" && !save.isEnabled, "Window title or initial Save state is incorrect")
        try require(recorder.shortcut == original && !help.isHidden && guidance.isHiddenOrHasHiddenAncestor,
                    "The current shortcut must appear without conditions")
        try await inspect(window, save: save, name: "default-light", directory: directory)
        let normalHeight = window.frame.height
        try require(normalHeight < 280, "The default window must stay compact")

        await click(reset, in: window)
        try require(recorder.shortcut == .default, "A mouse click must actually invoke Restore")
        try await inspect(window, save: save, name: "mouse-restored-light", directory: directory)
        try require(window.firstResponder === window,
                    "Mouse restoration must release button focus instead of leaving a persistent focus ring")
        cancel.performClick(nil)
        controller.show(preferences: saved)
        try await makeKey(window)

        recorder.performClick(nil)
        try require(recorder.isRecording && help.isHidden && guidance.isHiddenOrHasHiddenAncestor && !save.isEnabled,
                    "Recording must hide help and disable Save")
        try await inspect(window, save: save, name: "recording-light", directory: directory)
        let recordingHeight = window.frame.height
        let top = window.frame.maxY
        sendKey(window, UInt16(kVK_ANSI_P))
        try require(recorder.isRecording && recorder.shortcut == original && !error.isHiddenOrHasHiddenAncestor
                    && !guidance.isHiddenOrHasHiddenAncestor && help.isHidden, "Invalid input must show only error guidance")
        try require(error.stringValue == "단축키 조합을 확인해 주세요."
                    && guidance.stringValue.contains("영문자가 적힌 키 하나")
                    && !guidance.stringValue.contains("A–Z")
                    && recorder.accessibilityHelp()?.contains("Command + Shift를 누른 채 P") == true,
                    "Input guidance must explain the named keys and one physical letter")
        try require(window.frame.height > recordingHeight && abs(window.frame.maxY - top) < 1,
                    "Errors must grow down from the existing titlebar")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua),
                                   ("contrast-light", .accessibilityHighContrastAqua), ("contrast-dark", .accessibilityHighContrastDarkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await inspect(window, save: save, name: "invalid-\(name)", directory: directory)
        }
        window.appearance = NSAppearance(named: .aqua)
        sendKey(window, UInt16(kVK_Escape), characters: "\u{1b}")
        try require(!recorder.isRecording && guidance.isHiddenOrHasHiddenAncestor && abs(window.frame.height - normalHeight) < 1,
                    "Escape must cancel input, clear guidance, and restore compact layout")
        try require(recordingChanges.suffix(2) == [true, false], "Recording callbacks must restore the app's shortcut state")

        recorder.performClick(nil)
        try require(window.performKeyEquivalent(with: key(window, UInt16(kVK_ANSI_M), [.control, .shift, .capsLock], "ㅡ")),
                    "Command equivalents must pass through the recorder")
        try require(recorder.shortcut == replacement && !recorder.isRecording && save.isEnabled,
                    "A valid physical key must work with Korean input and enable Save")
        controller.show(preferences: saved)
        try require(recorder.shortcut == replacement, "Reopening a visible window must preserve pending edits")
        cancel.performClick(nil)
        try require(applyCount == 0 && ShortcutPreferences.load(from: defaults).shortcut == original,
                    "Cancel must not apply pending changes")
        controller.show(preferences: saved)
        try await makeKey(window)
        try require(recorder.shortcut == original && !save.isEnabled, "Reopening after cancel must restore saved values")

        recorder.performClick(nil)
        sendKey(window, UInt16(kVK_ANSI_M), [.control, .shift])
        failRegistration = true
        save.performClick(nil)
        try require(window.isVisible && !error.isHiddenOrHasHiddenAncestor && guidance.isHiddenOrHasHiddenAncestor
                    && !save.isEnabled && saved.shortcut == original, "A conflict must preserve saved values and show only its own message")
        try await inspect(window, save: save, name: "conflict-light", directory: directory)
        failRegistration = false
        recorder.performClick(nil)
        sendKey(window, UInt16(kVK_ANSI_M), [.control, .shift])
        save.performClick(nil)
        try require(!window.isVisible && saved.shortcut == replacement && applyCount == 1,
                    "Correcting a conflict must allow an explicit Save")

        controller.show(preferences: saved)
        try await makeKey(window)
        enabled.performClick(nil)
        try require(!recorder.isEnabled && label.textColor == .disabledControlTextColor && save.isEnabled
                    && help.stringValue.contains("메뉴의 ‘표 변환하기’"), "Disabled shortcuts must dim the field label and explain menu access")
        reset.performClick(nil)
        try require(enabled.state == .off && !recorder.isEnabled && recorder.shortcut == .default,
                    "Restore must reset only the combination, preserving disabled state")
        try await inspect(window, save: save, name: "disabled-light", directory: directory)
        window.appearance = NSAppearance(named: .darkAqua)
        try await inspect(window, save: save, name: "disabled-dark", directory: directory)
        window.appearance = NSAppearance(named: .aqua)
        cancel.performClick(nil)
        try require(saved.isEnabled && saved.shortcut == replacement, "Cancel must also discard disabling and restoring")
        controller.show(preferences: saved)
        try await makeKey(window)
        enabled.performClick(nil)
        reset.performClick(nil)
        save.performClick(nil)
        try require(!saved.isEnabled && saved.shortcut == .default && applyCount == 2, "Save must persist disabled restoration")
        controller.show(preferences: saved)
        try await makeKey(window)
        reset.performClick(nil)
        try require(!save.isEnabled && enabled.state == .off, "Restoring an unchanged disabled shortcut must leave Save disabled")
        enabled.performClick(nil)
        try require(recorder.isEnabled && label.textColor == .labelColor && save.isEnabled,
                    "Enabling must restore the label color and allow Save")
        save.performClick(nil)

        controller.show(preferences: saved)
        try await makeKey(window)
        recorder.performClick(nil)
        sendKey(window, UInt16(kVK_Tab), [], "\t")
        try require(!recorder.isRecording && window.firstResponder === reset,
                    "Tab must cancel input and move focus to the next control")
        try await inspect(window, save: save, name: "keyboard-focused-light", directory: directory)
        await click(reset, in: window)
        try require(window.firstResponder === window,
                    "A mouse click must clear focus previously left on Restore by keyboard navigation")
        try await inspect(window, save: save, name: "mouse-after-keyboard-light", directory: directory)
        window.makeFirstResponder(reset)
        sendKey(window, UInt16(kVK_Tab), .shift, "\u{19}")
        try require(window.firstResponder === recorder, "Shift-Tab must preserve reverse keyboard navigation")
        await click(recorder, in: window)
        try require(recorder.isRecording && window.firstResponder === recorder,
                    "Mouse recording must keep input focus; recording=\(recorder.isRecording), responder=\(String(describing: window.firstResponder))")
        sendKey(window, UInt16(kVK_Escape), [], "\u{1b}")
        await click(reset, in: window)
        try require(!recorder.isRecording && window.firstResponder === window,
                    "Switching from keyboard to mouse must clear the previous button focus")
        recorder.performClick(nil)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.makeKeyAndOrderFront(nil)
        try await makeKey(other)
        try require(!recorder.isRecording, "Losing window focus must stop recording")
        other.close()
        try await makeKey(window)
        recorder.performClick(nil)
        sendKey(window, UInt16(kVK_ANSI_P))
        try require(recorder.isRecording && !guidance.isHiddenOrHasHiddenAncestor,
                    "The long-error mouse check must begin while recording invalid input")
        // Send mouse events only to this test window, never to the desktop or another app.
        await click(cancel, in: window)
        try require(!window.isVisible && !recorder.isRecording && applyCount == 3,
                    "Clicking Cancel below a long error must close without saving or losing the click; visible=\(window.isVisible), recording=\(recorder.isRecording), applies=\(applyCount)")
        controller.show(preferences: saved)
        try await makeKey(window)
        try require(window.performKeyEquivalent(with: key(window, UInt16(kVK_ANSI_W), .command, "w")) && !window.isVisible,
                    "Command-W must close settings without saving")
        controller.show(preferences: saved)
        try await makeKey(window)
        try require(window.performKeyEquivalent(with: key(window, UInt16(kVK_Escape), [], "\u{1b}")) && !window.isVisible,
                    "Escape outside recording must close settings without saving")
        try require(NSPasteboard.general.changeCount == clipboardRevision, "Settings checks must preserve the general clipboard")
    }

    @MainActor private static func property<T>(_ name: String, _ object: Any) throws -> T {
        guard let value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value as? T else {
            throw NSError(domain: "ShortcutChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing property \(name)"])
        }
        return value
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor private static func key(_ window: NSWindow, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "p") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }

    @MainActor private static func sendKey(_ window: NSWindow, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "p", characters: String? = nil) {
        window.sendEvent(key(window, code, flags, characters ?? text))
    }

    @MainActor private static func makeKey(_ window: NSWindow) async throws {
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<50 {
            if window.isKeyWindow { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(window.isKeyWindow, "Test window did not become key")
    }

    @MainActor private static func click(_ button: NSButton, in window: NSWindow) async {
        try? await Task.sleep(nanoseconds: 60_000_000)
        mouseEventNumber += 1
        let sequence = mouseEventNumber
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) {
                window.contentView?.layoutSubtreeIfNeeded()
                let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                func event(_ type: NSEvent.EventType) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: sequence,
                                       clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                }
                let down = event(.leftMouseDown)
                let release = Timer(timeInterval: 0.03, repeats: false) { _ in
                    MainActor.assumeIsolated { NSApp.postEvent(event(.leftMouseUp), atStart: true) }
                }
                RunLoop.main.add(release, forMode: .common)
                NSApp.sendEvent(down)
                continuation.resume()
            }
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    @MainActor private static func inspect(_ window: NSWindow, save: NSButton, name: String, directory: URL) async throws {
        try await Task.sleep(nanoseconds: 60_000_000)
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        let bottom = save.convert(save.bounds, to: content).minY
        try require(abs(bottom - 20) < 1, "\(name): Save bottom margin must remain 20pt, got \(bottom)")
        for view in descendants(content) where !view.isHiddenOrHasHiddenAncestor && (view is NSTextField || view is NSButton) {
            let frame = view.convert(view.bounds, to: content)
            // NSTextField includes a 2pt optical inset outside its alignment anchors.
            try require(frame.minX >= 17 && frame.maxX <= content.bounds.width - 17 && frame.minY >= 19,
                        "\(name): A control extends beyond the content margins: \(frame)")
            try require(!view.hasAmbiguousLayout, "\(name): A control has ambiguous layout")
            if let text = view as? NSTextField {
                try require(text.bounds.height + 1 >= text.fittingSize.height, "\(name): Text is clipped: \(text.stringValue)")
            }
        }
        let root = content.superview ?? content
        let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png"))
        print("\(name): \(window.frame.size), Save bottom \(bottom)")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "ShortcutChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
