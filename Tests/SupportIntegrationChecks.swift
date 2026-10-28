import AppKit

@MainActor
private final class SupportChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await SupportIntegrationChecks.run()
                print("Support integration checks passed: email and GitHub menus, encoded drafts, missing recipients, explicit clipboard writes, open failures, and About layout.")
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
                    == ["이메일로 문의…", "GitHub에 의견 남기기…", "|", "문의 이메일 주소 복사"],
                    "Email drafts, GitHub feedback, and explicit address copying must remain available")
        try require(menu.items[0].isEnabled && menu.items[1].isEnabled && menu.items[3].isEnabled,
                    "A configured recipient must enable both email actions alongside GitHub")
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
        menu.performActionForItem(at: 3)
        try require(pasteboard.changeCount > revision && pasteboard.string(forType: .string) == recipient
                    && pasteboard.string(forType: .html) == nil,
                    "The explicit address command must copy the recipient without opening another app")
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
            try require(unconfigured.emailURL == nil && !missingMenu.items[0].isEnabled
                        && missingMenu.items[1].isEnabled && !missingMenu.items[3].isEnabled,
                        "Missing or malformed recipients must disable email actions without hiding or removing them")
            let beforeDisabled = opened.count
            let beforeClipboard = pasteboard.changeCount
            missingMenu.performActionForItem(at: 0)
            missingMenu.performActionForItem(at: 3)
            await Task.yield()
            try require(opened.count == beforeDisabled && pasteboard.changeCount == beforeClipboard,
                        "Unconfigured email commands must not open a draft or copy a fallback address")
        }

        if let iconURL = bundle.url(forResource: "table_icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) { icon.setName("table_icon") }
        let about = AboutController(bundle: bundle, support: support, openURL: { _ in })
        defer { about.closeAll() }
        let root = about.window!.contentView!
        let button = root.subviews.compactMap { $0 as? NSPopUpButton }.first!
        try require(button.isEnabled && button.title == SupportController.commandTitle && button.pullsDown,
                    "About must expose a native pull-down with the same support choices")
        try require(button.menu!.items.dropFirst().map(\.title) == menu.items.map(\.title)
                    && button.menu!.items.dropFirst().filter { !$0.isSeparatorItem }.allSatisfy { $0.target === support },
                    "About and the status menu must share the same email, GitHub, and copy commands")
        shouldOpen = true
        let beforeAbout = opened.count
        button.menu!.performActionForItem(at: 2)
        try await wait { opened.count == beforeAbout + 1 }
        try require(opened.last == support.githubURL, "About must open the same issue form with the same environment")
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            about.window?.appearance = NSAppearance(named: name)
            root.layoutSubtreeIfNeeded()
            for view in root.subviews {
                try require(root.bounds.contains(view.frame), "About controls must stay inside the content bounds")
                if let button = view as? NSButton {
                    try require(button.frame.width >= ceil(button.intrinsicContentSize.width), "Support must not clip or widen the existing button labels")
                }
            }
            let frame = root.superview!
            frame.displayIfNeeded()
            let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("about-\(name.rawValue).png"))
        }
        try require(NSPasteboard.general.changeCount == generalRevision, "Support checks must never modify the user's general clipboard")
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
