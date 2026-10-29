import AppKit

@MainActor
private final class SupportChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await SupportIntegrationChecks.run()
                print("Support integration checks passed: email and GitHub menus, encoded drafts, missing recipients, explicit clipboard writes, open failures, About layout, and the ten-click Easter egg.")
                NSApp.terminate(nil)
            } catch {
                fputs("Support integration check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

@main
struct SupportIntegrationChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SupportChecksDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor fileprivate static func run() async throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let generalRevision = NSPasteboard.general.changeCount
        let pasteboard = NSPasteboard(name: .init("com.phronesis.pyororong.tests.support.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let originalHTML = "<table><tr><td>문의에서 보내지 않을 표 & + #</td></tr></table>"
        pasteboard.setString(originalHTML, forType: .html)
        var revision = pasteboard.changeCount
        let recipient = "support+qa@example.com"
        let builtSupport = SupportController(bundle: bundle)
        try require(builtSupport.emailURL != nil && builtSupport.makeMenu().items[0].isEnabled,
                    "The shipped app must wire its configured recipient to an enabled email command")
        var opened: [URL] = []
        var alerts: [NSAlert] = []
        var shouldOpen = true
        var response: NSApplication.ModalResponse = .alertSecondButtonReturn
        let support = SupportController(bundle: bundle, emailAddress: recipient,
                                        systemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1),
                                        pasteboard: pasteboard,
                                        openURL: { opened.append($0); return shouldOpen },
                                        runAlert: { alerts.append($0); return response })
        let item = support.makeMenuItem()
        try require(item.title == "피드백 및 지원" && item.isEnabled && item.submenu != nil,
                    "Support must keep both agreed contact channels in a submenu")
        let menu = item.submenu!
        try require(menu.items.map { $0.isSeparatorItem ? "|" : $0.title }
                    == ["이메일로 문의…", "GitHub에 의견 남기기…"],
                    "Support must offer only email and GitHub without an address-copy item or trailing separator")
        try require(menu.items[0].isEnabled && menu.items[1].isEnabled,
                    "A configured recipient must enable email alongside GitHub")
        try require(menu.items[1].toolTip?.contains("로그인") == true && menu.items[1].toolTip?.contains("공개") == true,
                    "Only the GitHub entry must explain sign-in and public visibility")
        menu.performActionForItem(at: 0)
        try require(opened.isEmpty, "External activation must wait until the menu action returns")
        try await wait { opened.count == 1 }
        let email = URLComponents(url: opened[0], resolvingAgainstBaseURL: false)!
        let emailFields = Dictionary(uniqueKeysWithValues: (email.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let version = SupportController.applicationVersion(in: bundle)!
        try require(email.scheme == "mailto" && email.path == recipient,
                    "Email must address the configured recipient, preserving plus addressing")
        try require(Set(emailFields.keys) == ["subject", "body"] && emailFields["subject"] == "[표로롱] 피드백 및 지원"
                    && emailFields["body"]?.contains("표로롱 버전: \(version)") == true
                    && emailFields["body"]?.contains("macOS 버전: 27.0.1") == true
                    && emailFields["body"]?.contains("문의 내용:\n") == true,
                    "An editable Korean draft must contain the actual app and OS versions")
        try require(!opened[0].absoluteString.contains("\n") && !emailFields.values.contains { $0.contains(originalHTML) },
                    "Draft fields must be URL encoded and must not include copied documents")
        try require(alerts.isEmpty && pasteboard.changeCount == revision,
                    "Opening a draft must neither claim delivery nor replace the clipboard")

        shouldOpen = false
        menu.performActionForItem(at: 0)
        try await wait { alerts.count == 1 }
        try require(alerts[0].messageText == "메일 앱을 열 수 없습니다"
                    && alerts[0].informativeText.contains(recipient)
                    && alerts[0].buttons.map(\.title) == ["문의 이메일 주소 복사", "닫기"],
                    "An unavailable mail client must offer the recipient for webmail")
        try require(pasteboard.changeCount == revision, "Dismissing a mail failure must preserve copied content")
        response = .alertFirstButtonReturn
        menu.performActionForItem(at: 0)
        try await wait { alerts.count == 2 }
        try require(pasteboard.string(forType: .string) == recipient && pasteboard.string(forType: .html) == nil,
                    "Mail failure recovery may copy only the recipient after an explicit choice")
        pasteboard.setString(originalHTML, forType: .html)
        revision = pasteboard.changeCount
        shouldOpen = true
        response = .alertSecondButtonReturn
        let beforeGitHub = opened.count
        menu.performActionForItem(at: 1)
        try require(opened.count == beforeGitHub, "GitHub must also wait until menu tracking ends")
        try await wait { opened.count == beforeGitHub + 1 }
        let github = URLComponents(url: opened.last!, resolvingAgainstBaseURL: false)!
        let fields = Dictionary(uniqueKeysWithValues: (github.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try require(github.scheme == "https" && github.host == "github.com" && github.path == "/largeq/nanoome-pyororong/issues/new",
                    "Support must open this project's issue form")
        try require(fields == ["template": "feedback.yml", "app-version": version, "macos-version": "27.0.1"],
                    "Only the template ID and actual app/OS versions may be prefilled")
        try require(alerts.count == 2 && pasteboard.changeCount == revision,
                    "Opening support must not show a submission confirmation or rewrite the clipboard")

        shouldOpen = false
        menu.performActionForItem(at: 1)
        try await wait { alerts.count == 3 }
        let alert = alerts[2]
        try require(alert.messageText == "GitHub 페이지를 열 수 없습니다"
                    && alert.informativeText.contains(support.githubURL.absoluteString),
                    "A browser failure must explain recovery with the actual issue URL")
        try require(alert.buttons.map(\.title) == ["GitHub 주소 복사", "닫기"] && alert.buttons[1].keyEquivalent == "\u{1b}",
                    "The failure must offer explicit copy and an Escape dismissal")
        try require(pasteboard.changeCount == revision && pasteboard.string(forType: .html) == originalHTML,
                    "Dismissing a failure must preserve copied table content")
        response = .alertFirstButtonReturn
        menu.performActionForItem(at: 1)
        try await wait { alerts.count == 4 && pasteboard.changeCount > revision }
        try require(pasteboard.string(forType: .string) == support.githubURL.absoluteString
                    && pasteboard.string(forType: .html) == nil,
                    "Only choosing copy may replace the pasteboard with the issue URL")

        for address in ["", "invalid", "one@example.com?cc=other@example.com", "one@example.com\r\nBcc: other@example.com"] {
            let unconfigured = SupportController(bundle: bundle, emailAddress: address, pasteboard: pasteboard,
                                                 openURL: { opened.append($0); return true })
            let missingMenu = unconfigured.makeMenu()
            try require(unconfigured.emailURL == nil && missingMenu.items.count == 2
                        && !missingMenu.items[0].isEnabled && missingMenu.items[1].isEnabled,
                        "Missing or malformed recipients must disable email while keeping GitHub available")
            let beforeDisabled = opened.count
            let beforeClipboard = pasteboard.changeCount
            missingMenu.performActionForItem(at: 0)
            await Task.yield()
            try require(opened.count == beforeDisabled && pasteboard.changeCount == beforeClipboard,
                        "Unconfigured email commands must not open a draft or copy a fallback address")
        }

        try require(bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "Pyororong"
                    && bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "Pyororong",
                    "The built app must register its Icon Composer app icon")
        guard let fallbackURL = bundle.url(forResource: "Pyororong", withExtension: "icns"),
              let fallback = NSImage(contentsOf: fallbackURL),
              let fallbackCG = fallback.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "SupportChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fallback app icon"])
        }
        let fallbackBitmap = NSBitmapImageRep(cgImage: fallbackCG)
        let defaultTable = fallbackBitmap.colorAt(x: fallbackBitmap.pixelsWide / 2,
                                                 y: fallbackBitmap.pixelsHigh * 40 / 100)!.usingColorSpace(.sRGB)!
        try require(defaultTable.redComponent < 0.35,
                    "The compiled default icon must have a black table, without an overlapping white table")
        let about = AboutController(bundle: bundle, openURL: { _ in })
        defer { about.closeAll() }
        let root = about.window!.contentView!
        let icon = root.subviews.compactMap { $0 as? AboutIconButton }.first!
        try require(icon.image != nil && icon.image?.isTemplate == false && icon.contentTintColor == nil,
                    "About must show the colored app icon without template tinting")
        try require(!root.subviews.contains { $0 is NSPopUpButton },
                    "Support choices must stay in the status menu without a duplicate About control")
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua] {
            about.window?.appearance = NSAppearance(named: name)
            root.layoutSubtreeIfNeeded()
            let iconBitmap = icon.bitmapImageRepForCachingDisplay(in: icon.bounds)!
            icon.effectiveAppearance.performAsCurrentDrawingAppearance {
                icon.cacheDisplay(in: icon.bounds, to: iconBitmap)
            }
            let table = iconBitmap.colorAt(x: iconBitmap.pixelsWide / 2, y: iconBitmap.pixelsHigh * 28 / 100)!.usingColorSpace(.sRGB)!
            let isDark = icon.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            try require(isDark ? table.redComponent > 0.85 : table.redComponent < 0.15,
                        "About must switch the table from black to white in Dark Mode and back without reopening")
            let hand = iconBitmap.colorAt(x: iconBitmap.pixelsWide * 78 / 100, y: iconBitmap.pixelsHigh * 70 / 100)!.usingColorSpace(.sRGB)!
            try require(hand.blueComponent > hand.redComponent + 0.1,
                        "Both appearances must preserve the blue hand's color")
            for view in root.subviews {
                try require(root.bounds.contains(view.frame), "About controls must stay inside the content bounds")
                if let button = view as? NSButton {
                    try require(button.frame.width >= ceil(button.intrinsicContentSize.width), "Support must not clip or widen the existing button labels")
                }
                if let field = view as? NSTextField {
                    let needed = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000)).height
                    try require(needed <= field.bounds.height + 1, "About must not clip its introduction or creator credit")
                }
            }
            for field in root.subviews.compactMap({ $0 as? NSTextField })
                where field.stringValue.hasPrefix("표로롱은 ") || field.stringValue.hasPrefix("제작 ") {
                let original = NSAttributedString(attributedString: field.attributedStringValue)
                field.selectText(nil)
                guard let editor = field.currentEditor() as? NSTextView else {
                    throw NSError(domain: "SupportChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "About text must remain selectable"])
                }
                try require(editor.attributedString().isEqual(to: original) && !editor.isEditable,
                            "Selecting About text must preserve bold text and paragraph spacing without allowing edits")
                pasteboard.clearContents()
                let didCopy = editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes)
                let copiedText = pasteboard.string(forType: .string)
                try require(didCopy && copiedText == original.string,
                            "Selected About text must remain copyable")
                about.window?.makeFirstResponder(about.window)
                try require(field.attributedStringValue.isEqual(to: original),
                            "Deselecting About text must preserve its original formatting")
            }
            let frame = root.superview!
            frame.displayIfNeeded()
            let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("about-\(name.rawValue).png"))
            try checkIconDepth(icon, in: root)
        }
        let title = root.subviews.compactMap { $0 as? AboutNameLabel }.first!
        let defaultImage = icon.image
        var stageImages: [NSImage] = []
        for stage in 6...10 {
            guard let image = bundle.image(forResource: "AboutEasterEgg\(stage)") else {
                throw NSError(domain: "SupportChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Easter egg stage \(stage)"])
            }
            stageImages.append(image)
        }
        try require(icon.acceptsFirstResponder && icon.canBecomeKeyView,
                    "The native icon button must accept keyboard focus")
        func captureIcon(_ state: String) throws -> Data {
            let bitmap = icon.bitmapImageRepForCachingDisplay(in: icon.bounds)!
            icon.cacheDisplay(in: icon.bounds, to: bitmap)
            let data = bitmap.representation(using: .png, properties: [:])!
            try data.write(to: directory.appendingPathComponent("about-icon-\(state).png"))
            return data
        }
        let released = try captureIcon("released")
        icon.highlight(true)
        let pressed = try captureIcon("pressed")
        icon.highlight(false)
        let releasedAgain = try captureIcon("released-again")
        try require(releasedAgain == released,
                    "Releasing the icon must restore its original drawing")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require(pressed != released, "The icon must give immediate visual feedback while held down")
        }
        for click in 1...10 {
            icon.performClick(nil)
            let expectedImage = click <= 5 ? defaultImage : stageImages[click - 6]
            try require(icon.image?.tiffRepresentation == expectedImage?.tiffRepresentation,
                        "Clicks 1–5 must keep the default icon, then each click must select its matching stage (click \(click))")
            try require(title.stringValue == (click == 10 ? "프네프네 포로롱" : "표로롱"),
                        "Only the tenth click may change the app name")
            try require(click == 10 || title.shimmerProgress == nil,
                        "Clicks before the tenth must not start the title shimmer")
            if click >= 6 {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    about.window?.appearance = NSAppearance(named: appearance)
                    try checkIconDepth(icon, in: root)
                    let frame = root.superview!
                    frame.displayIfNeeded()
                    let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
                    frame.cacheDisplay(in: frame.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to:
                        directory.appendingPathComponent("about-stage-\(click)-\(appearance.rawValue).png"))
                }
            }
        }
        let completedAt = Date()
        try require((title.shimmerProgress == nil) == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    "The title must shimmer once on appearance, respecting Reduce Motion")
        for frameIndex in 0..<7 {
            let bitmap = title.bitmapImageRepForCachingDisplay(in: title.bounds)!
            title.effectiveAppearance.performAsCurrentDrawingAppearance {
                title.cacheDisplay(in: title.bounds, to: bitmap)
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to:
                directory.appendingPathComponent("title-shimmer-\(frameIndex).png"))
            try await Task.sleep(nanoseconds: 220_000_000)
        }
        try require(title.shimmerProgress == nil && title.stringValue == "프네프네 포로롱",
                    "The shimmer must end after one pass while the gradient title remains")
        let remaining = 4 - Date().timeIntervalSince(completedAt)
        if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        try require(title.stringValue == "프네프네 포로롱", "The final state must stay visible for five seconds")
        icon.performClick(nil)
        try await wait { title.stringValue == "표로롱" }
        try require(Date().timeIntervalSince(completedAt) < 6 && icon.image === defaultImage && title.shimmerProgress == nil,
                    "Further clicks must not extend the five-second reset")
        for _ in 1...5 { icon.performClick(nil) }
        try require(icon.image === defaultImage, "Automatic reset must restart the click count")
        icon.performClick(nil)
        about.close()
        try require(icon.image === defaultImage && title.stringValue == "표로롱",
                    "Closing About must immediately reset a partial sequence")
        about.show()
        for _ in 1...10 { icon.performClick(nil) }
        about.close()
        try require(icon.image === defaultImage && title.stringValue == "표로롱" && title.shimmerProgress == nil,
                    "Closing About must immediately reset the completed sequence")
        about.show()
        for _ in 1...6 { icon.performClick(nil) }
        try await Task.sleep(nanoseconds: 5_100_000_000)
        try require(icon.image?.tiffRepresentation == stageImages[0].tiffRepresentation && title.stringValue == "표로롱",
                    "Closing About must cancel its old timer so it cannot reset a new sequence")
        about.show()
        try require(icon.image === defaultImage && title.stringValue == "표로롱",
                    "Opening About again must start a fresh sequence")
        try require(NSPasteboard.general.changeCount == generalRevision, "Support checks must never modify the user's general clipboard")
    }

    @MainActor private static func checkIconDepth(_ icon: NSButton, in root: NSView) throws {
        let frame = root.superview!
        let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
        frame.effectiveAppearance.performAsCurrentDrawingAppearance {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
        }
        let scale = CGFloat(bitmap.pixelsWide) / frame.bounds.width
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            let point = root.convert(NSPoint(x: x, y: y), to: frame)
            let imageY = frame.isFlipped ? point.y : frame.bounds.maxY - point.y
            return bitmap.colorAt(x: Int(point.x * scale), y: Int(imageY * scale))!.usingColorSpace(.sRGB)!
        }
        let side = color(icon.frame.maxX + 4, icon.frame.midY)
        if root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            try require(side.blueComponent > side.greenComponent + 0.015 && side.greenComponent > side.redComponent + 0.015,
                        "Dark Mode must draw a soft blue-cyan halo outside every icon stage")
        } else {
            let above = color(icon.frame.midX, icon.frame.minY - 3)
            let below = color(icon.frame.midX, icon.frame.maxY + 3)
            try require(below.redComponent < above.redComponent - 0.005 && abs(side.blueComponent - side.redComponent) < 0.02,
                        "Light Mode must restore a neutral shadow cast below the icon")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "SupportChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func wait(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(condition(), "Timed out waiting for the deferred support command")
    }
}
