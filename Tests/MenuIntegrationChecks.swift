import AppKit
import TableConverterCore
import TableConverterMac

@MainActor
private final class MenuChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await MenuIntegrationChecks.run()
                print("Menu integration checks passed: native left/right clicks, accessibility activation, transient menu cleanup, reentry protection, noninteractive status header, stable updates, clipboard states, action routing, grouping, Command-comma, and clicks during/after utility windows.")
                NSApp.terminate(nil)
            } catch {
                fputs("Menu integration check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

@main
struct MenuIntegrationChecks {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuChecksDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    fileprivate static func run() async throws {
        let suite = "com.phronesis.pyororong.tests.menu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        ShortcutPreferences(isEnabled: false).save(to: defaults)
        UsageGuidePreferences(showAtLaunch: false).save(to: defaults)
        let clipboardRevision = NSPasteboard.general.changeCount
        let pasteboard = NSPasteboard(name: .init(suite))
        defer { pasteboard.releaseGlobally() }
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        var supportURLs: [URL] = []
        let support = SupportController(pasteboard: pasteboard,
                                        openURL: { supportURLs.append($0); return true })
        let delegate = AppDelegate(converter: converter, shortcutDefaults: defaults, supportController: support)
        let oldMainMenu = NSApp.mainMenu
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            NSApp.mainMenu = oldMainMenu
        }
        let statusItem: NSStatusItem = try property("statusItem", of: delegate)
        let menu: NSMenu = try property("statusMenu", of: delegate)
        if #available(macOS 27.0, *) {
            try require(statusItem.menu == nil && statusItem.button?.target === delegate
                        && statusItem.button?.action != nil,
                        "macOS 27 must deliver clicks to the button action before attaching the menu")
        } else {
            try require(statusItem.menu === menu, "Earlier macOS versions must keep native menu handling")
        }
        let primary = menu.items[2]
        let notifier: ConversionNotifier = try property("notifier", of: delegate)
        try require(menu.items.map { $0.isSeparatorItem ? "|" : $0.title } == [
            "변환할 표가 있습니다", "|", "표 변환하기", "|", "단축키 설정…", "|",
            "사용법 보기", "피드백 및 지원…", "표로롱에 관하여", "|", "표로롱 종료"
        ], "Menu commands must be grouped by task")
        try require(!menu.items[0].isEnabled && menu.items[0].action == nil, "The state explanation must not be actionable")
        if #available(macOS 14.0, *) {
            try require(menu.items[0].isSectionHeader, "Status text must use a noninteractive native section header")
        }
        try await wait { menu.items[0].title == "한글에서 표를 복사하세요" }
        try require(!primary.isEnabled, "Empty clipboard must disable conversion")
        try require(menu.items[7].isEnabled && menu.items[7].submenu == nil, "Support must open directly even with no convertible table")
        menu.performActionForItem(at: 7)
        try await wait { supportURLs.count == 1 }
        try require(supportURLs[0].scheme == "https" && supportURLs[0].host == "github.com",
                    "The real status menu must open GitHub support")
        for rightClick in [false, true] {
            try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "한글에서 표를 복사하세요")
        }
        try await trackStatusButton(statusItem, menu: menu, rightClick: false, expectedState: "한글에서 표를 복사하세요", accessibilityPress: true)

        pasteboard.clearContents()
        pasteboard.setString("<table style='mso-test:yes'><tr><td>메뉴 변환 검사</td></tr></table>", forType: .html)
        delegate.menuWillOpen(menu)
        try require(!primary.isEnabled && menu.items[0].title == "변환할 표가 있습니다",
                    "Preparation must share the ready status text while keeping the old command disabled")
        try await trackStatusButton(statusItem, menu: menu, rightClick: false, expectedState: "변환할 표가 있습니다") {
            pasteboard.clearContents()
            pasteboard.setString("<table style='mso-test:yes'><tr><td>메뉴 갱신 검사</td></tr></table>", forType: .html)
        }
        try await wait { primary.isEnabled && menu.items[0].title == "변환할 표가 있습니다" }
        var unchangedNotifications = 0
        let unchangedObserver = NotificationCenter.default.addObserver(forName: NSMenu.didChangeItemNotification,
                                                                       object: menu, queue: nil) { _ in
            MainActor.assumeIsolated { unchangedNotifications += 1 }
        }
        for _ in 0..<3 { delegate.menuWillOpen(menu) }
        try await Task.sleep(nanoseconds: 600_000_000)
        NotificationCenter.default.removeObserver(unchangedObserver)
        try require(unchangedNotifications == 0,
                    "Unchanged clipboard polling must not disable and re-enable menu items; changes: \(unchangedNotifications)")
        try require(primary.title == "표 변환하기" && primary.keyEquivalent.isEmpty,
                    "A disabled global shortcut must not appear on the conversion command")
        menu.performActionForItem(at: 2)
        try require(!primary.isEnabled && primary.title == "변환 중…" && menu.items[0].title == "표를 변환하고 있습니다…",
                    "Running conversion must explain the busy state and prevent another execution")
        let conversionTask: Task<Void, Never> = try property("conversionTask", of: delegate)
        menu.performActionForItem(at: 2)
        try require(!primary.isEnabled, "Another invocation must not enable a running conversion")
        for rightClick in [false, true] {
            try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "표를 변환하고 있습니다…")
        }
        await conversionTask.value
        try await wait { primary.title == "변환 결과 보기" && primary.isEnabled }
        try require(converter.isReadyToPaste && menu.items[0].title == "변환 완료",
                    "A completed conversion must offer its current result")
        try require(primary.keyEquivalent.isEmpty, "The result command must not claim the conversion shortcut")
        for rightClick in [false, true] {
            for _ in 0..<6 {
                menu.performActionForItem(at: 2)
                try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "변환 완료")
                try require(!NSApp.windows.contains { $0 is NSPanel && $0.isVisible },
                            "Opening the menu must dismiss a result without cancelling the menu")
            }
        }
        let convertedRevision = pasteboard.changeCount
        menu.performActionForItem(at: 2)
        try require(pasteboard.changeCount == convertedRevision && notifier.latestResult?.outcome == .success,
                    "Opening a completed result must not reconvert or rewrite the clipboard")
        try require(NSApp.windows.contains { $0 is NSPanel && $0.isVisible },
                    "The primary result command must reopen the current conversion notice")

        pasteboard.clearContents()
        pasteboard.setString("새로 복사한 일반 글", forType: .string)
        let replacementRevision = pasteboard.changeCount
        menu.performActionForItem(at: 2)
        try require(!primary.isEnabled && pasteboard.changeCount == replacementRevision,
                    "An outdated result command must not run against replacement clipboard content")
        try await wait { menu.items[0].title == "한글에서 표를 복사하세요" }
        try require(!primary.isEnabled && primary.title == "표 변환하기",
                    "A new empty clipboard must return to the disabled conversion command")
        try require(!NSApp.windows.contains { $0 is NSPanel && $0.isVisible },
                    "New clipboard content must close the previous conversion notice")

        // A global shortcut may still report invalid input; the menu then opens that error instead of retrying.
        _ = delegate.perform(NSSelectorFromString("convertTable:"), with: nil)
        try await wait { primary.title == "오류 안내 보기" && primary.isEnabled }
        try require(menu.items[0].title == "변환하지 못했습니다" && notifier.latestResult?.outcome == .failure,
                    "Failure must be described separately from the empty state")
        for rightClick in [false, true] {
            menu.performActionForItem(at: 2)
            try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "변환하지 못했습니다")
        }
        delegate.menuWillOpen(menu)
        menu.performActionForItem(at: 2)
        try require(pasteboard.changeCount == replacementRevision && notifier.latestResult?.outcome == .failure,
                    "Opening error details must preserve the original clipboard and error")
        try require(NSApp.windows.contains { $0 is NSPanel && $0.isVisible }, "The failure command must reopen its notice")
        let taskValue = Mirror(reflecting: delegate).children.first { $0.label == "conversionTask" }!.value
        try require(Mirror(reflecting: taskValue).children.isEmpty, "Opening error details must not start a retry")
        let failurePanel = NSApp.windows.compactMap { $0 as? NSPanel }.first { $0.isVisible }!
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let guideButton = descendants(failurePanel.contentView!).compactMap { $0 as? NSButton }
            .first { $0.title == "사용법 보기" }
        try require(guideButton != nil, "Missing input must offer usage guidance instead of a blind retry")
        guideButton?.performClick(nil)
        let guide: UsageGuideController = try property("usageGuide", of: delegate)
        try require(guide.window?.isVisible == true && !failurePanel.isVisible,
                    "The result's usage action must open the real guide and close the notice")
        guide.close()
        for rightClick in [false, true] {
            try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "변환하지 못했습니다")
        }
        try await trackStatusButton(statusItem, menu: menu, rightClick: false, expectedState: "변환하지 못했습니다", accessibilityPress: true)

        pasteboard.clearContents()
        pasteboard.setString("<table style='mso-test:yes'><tr><td>복구 후 표</td></tr></table>", forType: .html)
        delegate.menuWillOpen(menu)
        try await wait { primary.isEnabled && primary.title == "표 변환하기" }
        try require(menu.items[0].title == "변환할 표가 있습니다", "A new valid copy must clear the failed menu state")

        let settingsCommand = menu.items[4]
        try require(settingsCommand.keyEquivalent == "," && settingsCommand.keyEquivalentModifierMask == .command,
                    "Settings must expose the standard Command-comma shortcut")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                    windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
                                    isARepeat: false, keyCode: 43)!
        try require(NSApp.mainMenu?.performKeyEquivalent(with: event) == true, "Command-comma must route through the application menu")
        let settings: ShortcutSettingsController = try property("shortcutSettings", of: delegate)
        try require(settings.window?.isVisible == true, "Command-comma must open the shortcut settings window")
        settings.close()
        for rightClick in [false, true] {
            try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick, expectedState: "변환할 표가 있습니다")
        }
        for (index, propertyName) in [(6, "usageGuide"), (4, "shortcutSettings"), (8, "about")] {
            menu.performActionForItem(at: index)
            let controller: NSWindowController = try property(propertyName, of: delegate)
            try await wait { controller.window?.isVisible == true && controller.window?.isKeyWindow == true }
            for rightClick in [false, true] {
                try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick,
                                            expectedState: "변환할 표가 있습니다", context: "\(propertyName) visible")
            }
            controller.close()
            try require(controller.window?.isVisible == false, "\(propertyName) must close before testing the next click")
            for rightClick in [false, true] {
                try await trackStatusButton(statusItem, menu: menu, rightClick: rightClick,
                                            expectedState: "변환할 표가 있습니다", context: "\(propertyName) closed")
            }
        }
        try require(NSPasteboard.general.changeCount == clipboardRevision, "Menu checks must not change the general clipboard")
    }

    @MainActor
    private static func trackStatusButton(_ statusItem: NSStatusItem, menu: NSMenu, rightClick: Bool, expectedState: String,
                                         accessibilityPress: Bool = false,
                                         context: String = "clipboard state",
                                         beforeOpening: @escaping @MainActor @Sendable () -> Void = {}) async throws {
        let result = await withCheckedContinuation { continuation in
            let openMenu: @MainActor @Sendable () -> Void = {
                // Call the native status button in this test app; do not post events to the desktop.
                beforeOpening()
                let button = statusItem.button!
                var openings = 0
                var highlightedDisabledItem = false
                var observedState = ""
                var reentryChecked = false
                let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                                       object: menu, queue: nil) { _ in
                    MainActor.assumeIsolated { openings += 1 }
                }
                let earliestClose = Date(timeIntervalSinceNow: 0.08)
                let deadline = Date(timeIntervalSinceNow: 5)
                let closeMenu: @MainActor @Sendable () -> Void = {
                    if #available(macOS 27.0, *), !reentryChecked, openings > 0 {
                        reentryChecked = true
                        // Repeated activation during tracking must not recursively present a second menu.
                        _ = button.sendAction(button.action, to: button.target)
                    }
                    observedState = menu.items[0].title
                    if let highlighted = menu.highlightedItem, !highlighted.isEnabled {
                        highlightedDisabledItem = true
                    }
                    if (observedState == expectedState && Date() >= earliestClose) || Date() >= deadline {
                        menu.cancelTracking()
                    }
                }
                let timer = Timer(timeInterval: 0.01, repeats: true) { _ in MainActor.assumeIsolated(closeMenu) }
                RunLoop.main.add(timer, forMode: .common)
                let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                let event = NSEvent.mouseEvent(with: rightClick ? .rightMouseDown : .leftMouseDown,
                    location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: button.window!.windowNumber, context: nil, eventNumber: 1,
                    clickCount: 1, pressure: 1)!
                if #available(macOS 27.0, *), !accessibilityPress {
                    let release = NSEvent.mouseEvent(with: rightClick ? .rightMouseUp : .leftMouseUp,
                        location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: button.window!.windowNumber, context: nil, eventNumber: 2,
                        clickCount: 1, pressure: 0)!
                    // Pair the press in this test app's queue; never send input to another process.
                    NSApp.postEvent(release, atStart: false)
                }
                if accessibilityPress {
                    _ = button.accessibilityPerformPress()
                } else if rightClick {
                    button.rightMouseDown(with: event)
                } else {
                    button.mouseDown(with: event)
                }
                timer.invalidate()
                NotificationCenter.default.removeObserver(observer)
                continuation.resume(returning: (openings, observedState, highlightedDisabledItem))
            }
            RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated(openMenu) }
        }
        let route = "\(accessibilityPress ? "accessibility" : (rightClick ? "right" : "left")) / \(context) / \(expectedState)"
        try require(result.0 == 1, "Each activation must open exactly one menu (\(route)); openings: \(result.0)")
        try require(result.1 == expectedState, "Menu state did not settle while tracking (\(route)); observed: \(result.1)")
        try require(!result.2, "Disabled rows must not become highlighted while tracking (\(route))")
        if #available(macOS 27.0, *) {
            try require(statusItem.menu == nil, "Closing must detach the menu so the next click reaches the action")
            try require(statusItem.button?.state == .off && statusItem.button?.isHighlighted == false,
                        "Closing must clear the status button's selection and pressed appearance")
            try require(statusItem.button?.target != nil && statusItem.button?.action != nil,
                        "Closing must keep the button action connected for the next activation (\(route))")
        }
    }

    @MainActor
    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try require(condition(), "Menu state did not settle before the timeout")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "MenuIntegrationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func property<T>(_ name: String, of object: Any) throws -> T {
        let value = Mirror(reflecting: object).children.first { $0.label == name }?.value
        if let value = value as? T { return value }
        if let value, let unwrapped = Mirror(reflecting: value).children.first?.value as? T { return unwrapped }
        throw NSError(domain: "MenuIntegrationChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing property: \(name)"])
    }
}
