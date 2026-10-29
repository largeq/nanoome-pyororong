import AppKit
import AVKit
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
            print("Usage guide integration checks passed: compact layout, approved copy, hover and keyboard controls, five-second seeking, repeat playback, accessibility, launch policy, and appearances.")
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
            let about = AboutController(bundle: bundle, openURL: { openedURL = $0 })
            defer { about.closeAll() }
            let labels = views(about.window!.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
            try require(about.window?.title == "표로롱에 관하여", "The About title must use the short app name")
            try require(labels.contains("표로롱") && labels.contains("""
                표로롱은 서울대학교 프로네시스 나눔실천단 ‘나눔교실’을 준비하는 과정에서 탄생하였습니다.
                네이버 카페에 각종 자료를 올릴 때, Mac용 한글에서 복사한 복잡한 표가 붙여넣기 후 깨지는 문제가 있습니다.
                표로롱은 표를 다시 손보는 수고를 줄이고, Mac에서도 한글 문서를 편리하게 공유할 수 있도록 합니다.
                """) && labels.contains("제작 프로네시스 나눔실천단 38기 재무부장 정근규"),
                        "About must show the approved introduction and creator credit verbatim")
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
        let bundle = Bundle(path: CommandLine.arguments[2])!
        let guide = UsageGuideController(defaults: defaults, bundle: bundle)
        let window = guide.window!
        let root = window.contentView!
        let demo = views(root).compactMap { $0 as? UsageGuideVideoView }.first!
        try require(demo.videoURL?.isFileURL == true && demo.videoURL == bundle.url(forResource: "usage-guide", withExtension: "mp4"),
                    "The guide must load the approved local video from the app bundle")
        let mediaSize = try FileManager.default.attributesOfItem(atPath: demo.videoURL!.path)[.size] as! NSNumber
        try require(mediaSize.intValue < 1_000_000, "The bundled recording must remain below 1 MB")
        try require(demo.playerView.controlsStyle == .none && !demo.playerView.showsFullScreenToggleButton
                    && demo.playerView.videoGravity == .resizeAspect,
                    "The recording must preserve its aspect ratio without native playback chrome")
        let videoControls = [demo.backwardButton, demo.playbackButton, demo.forwardButton]
        let accessibleVideoChildren = demo.accessibilityChildren() as? [NSView] ?? []
        try require(videoControls.allSatisfy { accessibleVideoChildren.contains($0) },
                    "VoiceOver must be able to reach all three custom video controls")
        try require(demo.backwardButton.accessibilityLabel() == "5초 뒤로"
                    && demo.forwardButton.accessibilityLabel() == "5초 앞으로",
                    "Skip controls must explain their five-second action")
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
        try require(window.title == "표로롱 사용법", "The window title must use the requested wording")
        try require(checkbox.state == .off, "The first-run checkbox must describe the recurring preference")
        try require(!views(root).compactMap { $0 as? NSButton }.contains { ["다음", "뒤로"].contains($0.title) }, "Removed navigation buttons must not remain in the view hierarchy")
        try await waitUntil("The bundled recording must decode and display a frame") {
            demo.player?.currentItem?.status == .readyToPlay && demo.playerView.isReadyForDisplay
        }
        try require(abs((demo.player?.currentItem?.duration.seconds ?? 0) - 12.933333) < 0.1,
                    "The app must contain the user's final 12.9-second edit")
        try require(abs(demo.bounds.width / demo.bounds.height - 1.6) < 0.01,
                    "The recording must keep its 16:10 aspect ratio")
        try await makeKey(window)
        let visibleLabels = views(root).compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }
        let heading = visibleLabels.first { $0.stringValue == "사용법" }
        try require(steps.count == 3 && steps.allSatisfy { !$0.isHiddenOrHasHiddenAncestor } && heading != nil,
                    "The guide must open directly on the requested heading and three instructions")
        try require(steps[0].title == "한글에서 표 복사" && steps[0].detail == "표를 포함한 내용 복사",
                    "The copy instruction must use the approved concise detail")
        try require(steps[2].title == "네이버 카페·블로그 글쓰기에 붙여넣기"
                    && steps[2].detail == "변환 완료 후 붙여넣기(⌘V)",
                    "The paste instruction must use the approved Naver editor wording")
        try require(!visibleLabels.contains { $0.stringValue == "사용 방법" || $0.stringValue.contains("표 또는 문서 전체 복사하기") },
                    "Replaced heading and copy detail must not remain visible")
        let videoRect = demo.convert(demo.bounds, to: root)
        let headingRect = heading!.convert(heading!.bounds, to: root)
        try require(demo.bounds.width > 498 && steps.allSatisfy { $0.bounds.width <= 220 },
                    "The instructions must be narrower so the recording gains width")
        try require(abs(videoRect.minY - headingRect.minY) < 8,
                    "The recording must start beside the heading instead of below the heading gap")
        try require(visibleLabels.contains { $0.stringValue.contains("창을 닫아도 메뉴바에서 계속 실행됩니다.") && $0.stringValue.contains("사용법 보기") }, "The footer must explain background operation and reopening the guide")
        let playbackBeforeHover = demo.isPlaying
        let positionBeforeHover = demo.playbackPosition
        window.makeFirstResponder(window)
        demo.mouseExited(with: pointerEvent(window, type: .mouseExited))
        try await expectControls(demo, visible: false, message: "Controls must hide when the pointer leaves and keyboard focus is outside the recording")
        demo.mouseEntered(with: pointerEvent(window, type: .mouseEntered))
        try await expectControls(demo, visible: true, message: "Entering the recording must reveal all three controls")
        demo.mouseExited(with: pointerEvent(window, type: .mouseExited))
        try await expectControls(demo, visible: false, message: "Leaving the recording must hide the controls again")
        try require(demo.isPlaying == playbackBeforeHover, "Revealing and hiding controls must preserve the playback state")
        if playbackBeforeHover {
            try await waitUntil("The recording must keep advancing while hover controls are hidden") {
                demo.isPlaying && abs(demo.playbackPosition - positionBeforeHover) > 0.01
            }
        }
        try inspect(window, name: "guide-light", directory: directory)
        try require(window.firstResponder === window, "Opening the guide must not automatically focus a control; got \(String(describing: window.firstResponder))")
        try require(demo.isPlaying == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    "Autoplay must respect Reduce Motion; rate \(demo.player?.rate ?? -1), reduced \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), active \(NSApp.isActive), key \(window.isKeyWindow), keyWindow \(String(describing: NSApp.keyWindow))")
        let requiredKeys: [NSView] = steps + videoControls + [checkbox, start]
        for expected in requiredKeys {
            sendKey(window, code: 48, characters: "\t")
            try require(window.firstResponder === expected,
                        "Tab must follow instructions, backward/play/forward, preference, and Start")
            let focusesVideoControl = videoControls.contains { $0 === expected }
            try await expectControls(demo, visible: focusesVideoControl,
                                     message: "Tab must reveal controls only while a video control has keyboard focus")
            if expected === demo.playbackButton {
                demo.mouseExited(with: pointerEvent(window, type: .mouseExited))
                try await expectControls(demo, visible: true,
                                         message: "Pointer exit must preserve controls needed by keyboard focus")
            }
        }
        for expected in requiredKeys.reversed().dropFirst() {
            sendKey(window, code: 48, characters: "\t", modifiers: .shift)
            try require(window.firstResponder === expected,
                        "Shift-Tab must reverse the custom controls and instruction order")
            try await expectControls(demo, visible: videoControls.contains { $0 === expected },
                                     message: "Shift-Tab must keep focused video controls visible and hide them after focus leaves")
        }
        let reading = root.accessibilityChildren() as? [NSView] ?? []
        try require(reading.filter { $0 is GuideStepButton }.count == 3, "VoiceOver order must include all steps once")
        try require(reading.firstIndex(of: steps[0])! < reading.firstIndex(of: demo)!, "VoiceOver must read instructions before the demonstration")
        try require(steps.allSatisfy { ($0.accessibilityChildren() ?? []).isEmpty }, "Step labels must not be duplicated in VoiceOver")

        if demo.isPlaying { demo.playbackButton.performClick(nil) }
        try await waitUntil("The custom pause control must stop playback") { !demo.isPlaying }
        try require(demo.playbackButton.accessibilityLabel() == "재생", "A paused video must expose a Play action")
        window.makeFirstResponder(window)
        window.makeFirstResponder(demo.playerView)
        try require(window.firstResponder === window
                    && !demo.playerView.acceptsFirstResponder && !demo.playerView.canBecomeKeyView,
                    "The display-only AVKit view must reject focus so it cannot bypass the custom controls")
        sendKey(window, code: 49, characters: " ")
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(demo.player?.rate == 0 && !demo.isPlaying
                    && demo.playbackButton.accessibilityLabel() == "재생",
                    "Space after a rejected AVKit focus attempt must preserve the custom paused state")

        let duration = demo.player!.currentItem!.duration.seconds
        steps[0].performClick(nil)
        try await waitUntil("The first instruction must seek to the start") { abs(demo.playbackPosition) < 0.05 }
        let pausedSeeks: [(NSButton, TimeInterval)] = [
            (demo.backwardButton, 0), (demo.forwardButton, 5), (demo.forwardButton, 10),
            (demo.forwardButton, duration), (demo.forwardButton, duration), (demo.backwardButton, duration - 5)
        ]
        for (control, target) in pausedSeeks {
            control.performClick(nil)
            try await waitUntil("Five-second skip controls must seek and clamp at the recording edges") {
                abs(demo.playbackPosition - target) < 0.08
            }
            try require(!demo.isPlaying, "Skipping in a paused recording must preserve the paused state")
        }

        steps[0].performClick(nil)
        try await waitUntil("The first instruction must reset the rapid-seek starting point") { abs(demo.playbackPosition) < 0.05 }
        demo.seek(by: 5)
        demo.seek(by: 5)
        demo.seek(by: -5)
        try await waitUntil("Rapid successive skips must accumulate from the requested target") {
            abs(demo.playbackPosition - 5) < 0.08
        }
        try require(!demo.isPlaying, "Rapid seeking must not invent a Play action")

        demo.playbackButton.performClick(nil)
        try await waitUntil("The custom play control must start playback") { demo.isPlaying }
        try require(demo.playbackButton.accessibilityLabel() == "일시정지", "A playing video must expose a Pause action")
        demo.forwardButton.performClick(nil)
        try await waitUntil("Forward skipping must preserve playback") {
            demo.isPlaying && demo.playbackPosition > 9.9 && demo.playbackPosition < 11
        }
        demo.backwardButton.performClick(nil)
        try await waitUntil("Backward skipping must preserve playback") {
            demo.isPlaying && demo.playbackPosition > 4.9 && demo.playbackPosition < 6
        }

        for cycle in 1...2 {
            demo.playbackButton.performClick(nil)
            try await waitUntil("Pause must allow precise near-end positioning") { !demo.isPlaying }
            demo.seek(by: duration - 0.18 - demo.playbackPosition)
            try await waitUntil("The recording must reach the near-end loop test position") {
                abs(demo.playbackPosition - (duration - 0.18)) < 0.08
            }
            demo.playbackButton.performClick(nil)
            try await waitUntil("Repeat playback must restart from the beginning on cycle \(cycle)") {
                demo.isPlaying && demo.playbackPosition < 1
            }
        }

        other.makeKeyAndOrderFront(nil)
        try await makeKey(other)
        try require(!demo.isPlaying, "A non-key guide must stop repeat playback")
        window.makeKeyAndOrderFront(nil)
        try await makeKey(window)
        try require(demo.isPlaying, "A temporarily suspended repeat can resume on activation")

        demo.playbackButton.performClick(nil)
        try await waitUntil("The custom pause control must stop repeat playback") { !demo.isPlaying }
        try await pause(0.25)
        try require(!demo.isPlaying, "A manual Pause must cancel any pending loop restart")
        other.makeKeyAndOrderFront(nil)
        try await makeKey(other)
        window.makeKeyAndOrderFront(nil)
        try await makeKey(window)
        try require(!demo.isPlaying, "A manual Pause must survive window activation")

        for step in steps {
            step.performClick(nil)
            try await waitUntil("Each instruction must seek to its matching scene") {
                abs(demo.playbackPosition - UsageGuideVideoView.stepTimes[step.index]) < 0.05
            }
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
        demo.playbackButton.performClick(nil)
        try await waitUntil("Explicit Play must work before the motion-preference test") { demo.isPlaying }
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

        let transparencyMethod = class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("accessibilityDisplayShouldReduceTransparency"))!
        let originalTransparency = method_getImplementation(transparencyMethod)
        let opaque: @convention(block) (AnyObject) -> Bool = { _ in true }
        let opaqueReplacement = imp_implementationWithBlock(opaque)
        method_setImplementation(transparencyMethod, opaqueReplacement)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try inspect(window, name: "reduced-transparency", directory: directory)
        try require(videoControls.allSatisfy { !$0.isHiddenOrHasHiddenAncestor && $0.isEnabled },
                    "All playback controls must remain available with reduced transparency")
        method_setImplementation(transparencyMethod, originalTransparency)
        imp_removeBlock(opaqueReplacement)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

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
        demo.playbackButton.performClick(nil)
        try await waitUntil("Repeat playback must be running before the close test") { demo.isPlaying }
        guide.close()
        try await pause(0.25)
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

        let missing = UsageGuideVideoView(frame: .zero, bundle: .main)
        missing.selectStep(2)
        try require(missing.player == nil && !missing.isPlaying
                    && missing.selectedStep == 2
                    && views(missing).compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue.contains("왼쪽 설명") },
                    "Missing video resources must leave readable instructions available")
    }

    @MainActor
    private static func inspect(_ window: NSWindow, name: String, directory: URL) throws {
        let root = window.contentView!
        root.layoutSubtreeIfNeeded()
        if name != "long-text" {
            try require(root.bounds.width == 840 && root.bounds.height < 560, "The compact guide must keep its 840pt width and fit its content; \(name) is \(root.bounds)")
        }
        var ownedViews = views(root)
        for video in ownedViews.compactMap({ $0 as? UsageGuideVideoView }) {
            for control in [video.backwardButton, video.playbackButton, video.forwardButton] where !ownedViews.contains(control) {
                ownedViews.append(control)
            }
        }
        for view in ownedViews.filter({ !$0.isHiddenOrHasHiddenAncestor }) {
            try require(!view.hasAmbiguousLayout, "Ambiguous layout in \(name): \(type(of: view)), frame \(view.frame), arranged \((view as? NSStackView)?.arrangedSubviews.map { String(describing: type(of: $0)) + ":" + $0.frame.debugDescription } ?? [])")
            guard let field = view as? NSTextField else { continue }
            let rect = field.convert(field.bounds, to: root)
            try require(rect.minX >= -1 && rect.minY >= -1 && rect.maxX <= root.bounds.width + 1 && rect.maxY <= root.bounds.height + 1,
                        "Text outside the window in \(name): \(field.stringValue)")
            let needed = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000)).height
            try require(needed <= field.bounds.height + 1, "Clipped text in \(name): \(field.stringValue), needs \(needed), has \(field.bounds.height)")
        }
        let buttons = ownedViews.compactMap { $0 as? NSButton }.filter { $0.keyEquivalent == "\r" && !$0.isHiddenOrHasHiddenAncestor }
        try require(buttons.count == 1, "The guide must have one default completion button")
        for button in ownedViews.compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
            try require(button.frame.width >= button.intrinsicContentSize.width, "Clipped button title in \(name): \(button.title)")
        }
        for video in ownedViews.compactMap({ $0 as? UsageGuideVideoView }) {
            for control in [video.backwardButton, video.playbackButton, video.forwardButton] {
                let rect = control.convert(control.bounds, to: video)
                try require(!control.isHiddenOrHasHiddenAncestor && rect.width >= 44 && rect.height >= 44
                            && rect.minX >= 0 && rect.minY >= 0
                            && rect.maxX <= video.bounds.width + 1 && rect.maxY <= video.bounds.height + 1,
                            "Custom playback controls must retain usable geometry inside the video even while faded in \(name)")
            }
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

    @MainActor private static func views(_ root: NSView) -> [NSView] {
        // Framework materials own their private hierarchy; inspect our public buttons separately.
        if root is AVPlayerView || root is NSVisualEffectView { return [root] }
        if #available(macOS 26.0, *), root is NSGlassEffectView || root is NSGlassEffectContainerView { return [root] }
        return [root] + root.subviews.flatMap(views)
    }
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
    @MainActor private static func waitUntil(_ message: String, condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await pause(0.05)
        }
        try require(condition(), message)
    }
    @MainActor private static func makeKey(_ window: NSWindow) async throws {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<100 {
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
    @MainActor private static func pointerEvent(_ window: NSWindow, type: NSEvent.EventType) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                              trackingNumber: 0, userData: nil)!
    }
    @MainActor private static func expectControls(_ video: UsageGuideVideoView, visible: Bool, message: String) async throws {
        let controls = [video.backwardButton, video.playbackButton, video.forwardButton]
        try await waitUntil(message) {
            video.areControlsVisible == visible && controls.allSatisfy { control in
                var opacity: CGFloat = 1
                var ancestor: NSView? = control
                while let view = ancestor, view !== video {
                    opacity *= view.alphaValue
                    ancestor = view.superview
                }
                return visible ? opacity > 0.99 : opacity < 0.01
            }
        }
        try require(controls.allSatisfy { $0.alphaValue == 1 && !$0.isHiddenOrHasHiddenAncestor },
                    "Hover visibility must fade the shared controls container while preserving focusable buttons")
    }
}
