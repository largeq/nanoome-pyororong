import AppKit
import ObjectiveC
import TableConverterMac

@MainActor
private final class GuideChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await UsageGuideIntegrationChecks.execute() }
    }
}

@main
struct UsageGuideIntegrationChecks {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = GuideChecksDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor fileprivate static func execute() async {
        do {
            try await run()
            print("Usage guide integration checks passed: layout, keyboard, playback, accessibility metadata, launch policy, and appearance snapshots.")
            NSApp.terminate(nil)
        } catch {
            fputs("Usage guide integration check failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let suite = "com.phronesis.pyororong.tests.guide.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clipboardRevision = NSPasteboard.general.changeCount
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Use the app's actual icon resources, without launching clipboard polling or global shortcuts.
        try require(CommandLine.arguments.count > 2 && Bundle(path: CommandLine.arguments[2]) != nil,
                    "Pass the built app bundle to verify its identity and resources")
        if CommandLine.arguments.count > 2, let bundle = Bundle(path: CommandLine.arguments[2]) {
            try require(bundle.bundleIdentifier == "com.phronesis.pyororong", "The built app must use the new bundle identifier")
            for key in ["CFBundleName", "CFBundleDisplayName"] {
                try require(bundle.object(forInfoDictionaryKey: key) as? String == "표로롱", "The app name must not include its descriptive subtitle")
            }
            try require(bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "Pyororong", "The executable must use the new internal name")
            try require(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "2.0.0", "The bundle must store the complete release version")
            var openedURL: URL?
            let support = SupportController(bundle: bundle, openURL: { _ in true })
            let about = AboutController(bundle: bundle, support: support, openURL: { openedURL = $0 })
            defer { about.closeAll() }
            let labels = views(about.window!.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
            try require(about.window?.title == "표로롱에 관하여", "The About title must use the short app name")
            try require(labels.contains("표로롱") && labels.contains("한글 표를 네이버 카페·블로그에 맞게 변환합니다.")
                        && !labels.contains("네이버 카페·블로그 표 변환"), "The About view must show one concise description")
            let project = try button("프로젝트 페이지", about.window!.contentView!)
            project.performClick(nil)
            try require(openedURL == AboutController.repositoryURL, "The renamed project button must preserve the repository destination")
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            try require(labels.contains("버전 2.0 (\(build))"), "The user-visible release version must be 2.0")
            for name in ["table-idle", "table-convert-ready", "table-paste-ready", "table-error"] {
                for suffix in ["", "-master"] {
                    if let url = bundle.url(forResource: name + suffix, withExtension: "png"),
                       let image = NSImage(contentsOf: url) { image.setName(name + suffix) }
                }
            }
        }
        let guide = UsageGuideController(defaults: defaults)
        let window = guide.window!
        let root = window.contentView!
        let demo = views(root).compactMap { $0 as? UsageGuideIllustration }.first!
        try require(!views(root).compactMap { $0 as? NSTextField }.contains {
            ["복사한 내용은 이 Mac에서만 처리합니다.", "✓ 현재 단계"].contains($0.stringValue)
        }, "Removed guide labels must not remain in the view hierarchy")
        defer { guide.close() }
        let steps = views(root).compactMap { $0 as? GuideStepButton }.sorted { $0.index < $1.index }
        let checkbox = try button("앱을 시작할 때마다 이 안내 표시", root)
        let start = try button("시작하기", root)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }

        guide.show(shortcut: .default)
        try await makeKey(window)
        try require(checkbox.state == .off, "The first-run checkbox must describe the recurring preference")
        try require(!views(root).compactMap { $0 as? NSButton }.contains { ["다음", "뒤로", "재생", "일시정지"].contains($0.title) }, "Removed navigation and playback buttons must not remain in the view hierarchy")
        let visibleLabels = views(root).compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }
        try require(steps.count == 3 && steps.allSatisfy { !$0.isHiddenOrHasHiddenAncestor }
                    && visibleLabels.contains { $0.stringValue == "사용 방법" }, "The guide must open directly on the three instructions")
        try require(visibleLabels.contains { $0.stringValue.contains("창을 닫아도 메뉴바에서 계속 실행됩니다.") && $0.stringValue.contains("사용법 보기") }, "The footer must explain background operation and reopening the guide")
        try inspect(window, name: "guide-light", directory: directory)
        try require(window.firstResponder === window, "Opening the guide must not automatically focus the default button")
        try require(demo.isPlaying == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Autoplay must respect Reduce Motion")
        let expectedKeys: [NSView] = steps + [checkbox, start]
        for expected in expectedKeys {
            sendKey(window, code: 48, characters: "\t")
            try require(window.firstResponder === expected, "Tab order must follow steps, preference, Start")
        }
        for expected in expectedKeys.reversed().dropFirst() {
            sendKey(window, code: 48, characters: "\t", modifiers: .shift)
            try require(window.firstResponder === expected, "Shift-Tab order must reverse Tab order; expected \((expected as? NSButton)?.title ?? "view"), got \((window.firstResponder as? NSButton)?.title ?? String(describing: window.firstResponder))")
        }
        let reading = root.accessibilityChildren() as? [NSView] ?? []
        try require(reading.filter { $0 is GuideStepButton }.count == 3, "VoiceOver order must include all steps once")
        try require(reading.firstIndex(of: steps[0])! < reading.firstIndex(of: demo)!, "VoiceOver must read instructions before the demonstration")
        try require(steps.allSatisfy { ($0.accessibilityChildren() ?? []).isEmpty }, "Step labels must not be duplicated in VoiceOver")

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            other.makeKeyAndOrderFront(nil)
            try await makeKey(other)
            try require(!demo.isPlaying, "A non-key guide must stop playing")
            window.makeKeyAndOrderFront(nil)
            try await makeKey(window)
            try require(demo.isPlaying, "An automatically suspended guide can resume on activation")
        }

        for step in steps {
            step.performClick(nil)
            try await pause(0.05)
            try require(!demo.isPlaying && demo.selectedStep == step.index && step.isCurrent, "Selecting a step must pause there")
            try require(step.accessibilityValue() as? String == "현재 단계", "The current step must have an accessibility value")
            try require(demo.accessibilityLabel()?.contains("일시정지") == true, "The demonstration must expose paused state")
            let selected = demo.selectedStep
            other.makeKeyAndOrderFront(nil)
            try await makeKey(other)
            window.makeKeyAndOrderFront(nil)
            try await makeKey(window)
            try require(!demo.isPlaying && demo.selectedStep == selected, "Window activation must preserve a user's paused selection")
        }
        guide.show(shortcut: .default)
        try await makeKey(window)
        try require(demo.selectedStep == 2 && !demo.isPlaying, "Reopening a visible guide must preserve the paused selection")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua),
                                   ("contrast-light", .accessibilityHighContrastAqua), ("contrast-dark", .accessibilityHighContrastDarkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for step in steps {
                step.performClick(nil)
                try require(steps.filter(\.isCurrent).count == 1 && step.isCurrent,
                            "Exactly one step must retain its selection outline")
                try inspect(window, name: "step-\(step.index + 1)-\(name)", directory: directory)
            }
        }
        guide.updateShortcut(nil)
        try require(steps[1].detail.contains("표 변환하기") && !steps[1].detail.contains(ConversionShortcut.default.displayName), "Disabled shortcuts need menu guidance")
        let custom = ConversionShortcut(keyCode: 40, modifierFlags: [.control, .shift])!
        guide.updateShortcut(custom)
        try require(steps[1].detail.contains(custom.displayName), "The guide must show a changed shortcut")

        // Override only this test process's workspace query; never change the user's system preference.
        let method = class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("accessibilityDisplayShouldReduceMotion"))!
        let original = method_getImplementation(method)
        let reduced: @convention(block) (AnyObject) -> Bool = { _ in true }
        let replacement = imp_implementationWithBlock(reduced)
        method_setImplementation(method, replacement)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try require(!demo.isPlaying, "Reduce Motion changes must stop playback and offer static steps")
        steps[1].performClick(nil)
        try require(demo.selectedStep == 1 && !demo.isPlaying, "Manual steps must work with Reduce Motion")
        method_setImplementation(method, original)
        imp_removeBlock(replacement)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try require(!demo.isPlaying, "Turning Reduce Motion off must preserve the paused state")

        // Longer content must grow vertically, and Start must fit a longer title.
        for field in views(root).compactMap({ $0 as? NSTextField }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
            field.stringValue += " " + field.stringValue
        }
        let originalTitle = start.title
        start.title = "더 긴 문구로 안내를 완료하고 시작하기"
        guide.updateShortcut(custom)
        try await pause(0.1)
        try inspect(window, name: "long-text", directory: directory)
        try require(start.frame.width >= start.intrinsicContentSize.width, "Start must grow for a longer title")
        start.title = originalTitle

        // Closing an untouched first-run guide completes/skips onboarding without inventing a recurring choice.
        guide.close()
        try require(!demo.isPlaying && !UsageGuidePreferences.shouldShowAtLaunch(from: defaults), "Closing must stop playback and suppress later first-run prompts")
        try require(defaults.object(forKey: UsageGuidePreferences.storageKey) == nil, "Closing must preserve the absence of an explicit choice")
        guide.show(shortcut: nil)
        try await makeKey(window)
        try require(demo.selectedStep == 0 && !steps[0].isHiddenOrHasHiddenAncestor, "A closed guide must reopen directly at the first instruction")
        checkbox.performClick(nil)
        try require(checkbox.state == .on && UsageGuidePreferences.load(from: defaults).showAtLaunch, "Checking the positive label must immediately save true")
        sendKey(window, code: 53, characters: "\u{1b}")
        try require(!window.isVisible && UsageGuidePreferences.shouldShowAtLaunch(from: defaults), "Esc must close while preserving an explicit show choice")
        guide.show(shortcut: nil)
        try await makeKey(window)
        checkbox.performClick(nil)
        try require(!UsageGuidePreferences.load(from: defaults).showAtLaunch, "Unchecking must immediately save false")
        try require(window.performKeyEquivalent(with: event(window, code: 13, characters: "w", modifiers: .command)), "Command-W must close")
        try require(!window.isVisible && !UsageGuidePreferences.shouldShowAtLaunch(from: defaults), "Command-W must preserve the hide choice")
        guide.show(shortcut: nil)
        try await makeKey(window)
        try require(window.performKeyEquivalent(with: event(window, code: 36, characters: "\r")), "Return must activate Start")
        try require(!window.isVisible && !demo.isPlaying, "Start must complete onboarding and stop playback")
        try require(NSPasteboard.general.changeCount == clipboardRevision, "Guide checks must leave the general clipboard unchanged")
    }

    @MainActor
    private static func inspect(_ window: NSWindow, name: String, directory: URL) throws {
        let root = window.contentView!
        root.layoutSubtreeIfNeeded()
        if name != "long-text" {
            try require(root.bounds.width == 840 && root.bounds.height < 500, "The guide must keep its 840pt width and fit the content without the old empty space")
        }
        for view in views(root).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
            try require(!view.hasAmbiguousLayout, "Ambiguous layout in \(name): \(type(of: view)), frame \(view.frame), arranged \((view as? NSStackView)?.arrangedSubviews.map { String(describing: type(of: $0)) + ":" + $0.frame.debugDescription } ?? [])")
            guard let field = view as? NSTextField else { continue }
            let rect = field.convert(field.bounds, to: root)
            try require(rect.minX >= -1 && rect.minY >= -1 && rect.maxX <= root.bounds.width + 1 && rect.maxY <= root.bounds.height + 1,
                        "Text outside the window in \(name): \(field.stringValue)")
            let needed = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000)).height
            try require(needed <= field.bounds.height + 1, "Clipped text in \(name): \(field.stringValue), needs \(needed), has \(field.bounds.height)")
        }
        let buttons = views(root).compactMap { $0 as? NSButton }.filter { $0.keyEquivalent == "\r" && !$0.isHiddenOrHasHiddenAncestor }
        try require(buttons.count == 1, "The guide must have one default completion button")
        for button in views(root).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
            try require(button.frame.width >= button.intrinsicContentSize.width, "Clipped button title in \(name): \(button.title)")
        }
        for button in buttons {
            try require(button.frame.width >= 70 && button.frame.width >= button.intrinsicContentSize.width,
                        "Navigation button below minimum/intrinsic width")
            try require(abs(button.frame.height - button.intrinsicContentSize.height) < 1, "Navigation button height must come from AppKit")
        }
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        print("Verified \(name): \(Int(root.bounds.width))×\(Int(root.bounds.height))")
    }

    @MainActor private static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor private static func button(_ title: String, _ root: NSView) throws -> NSButton {
        guard let button = views(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else {
            throw NSError(domain: "UsageGuideChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing button \(title)"])
        }
        return button
    }
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "UsageGuideChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    @MainActor private static func makeKey(_ window: NSWindow) async throws {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<20 {
            if window.isKeyWindow { return }
            try await pause(0.05)
        }
        try require(window.isKeyWindow, "The test window could not become key")
    }
    @MainActor private static func event(_ window: NSWindow, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil,
                        characters: code == 48 && modifiers.contains(.shift) ? "\u{19}" : characters,
                        charactersIgnoringModifiers: code == 48 && modifiers.contains(.shift) ? "\u{19}" : characters,
                        isARepeat: false, keyCode: code)!
    }
    @MainActor private static func sendKey(_ window: NSWindow, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
        window.sendEvent(event(window, code: code, characters: characters, modifiers: modifiers))
    }
}
