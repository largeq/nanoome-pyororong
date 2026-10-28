import AppKit

@MainActor
private final class SupportChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await SupportIntegrationChecks.run()
                print("Support integration checks passed: direct GitHub actions, no email recipient, form fields, explicit clipboard writes, open failures, and About layout.")
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
        let revision = pasteboard.changeCount
        try require(bundle.object(forInfoDictionaryKey: "PyororongSupportEmail") == nil,
                    "The built app must not contain a support recipient address")
        var opened: [URL] = []
        var alerts: [NSAlert] = []
        var shouldOpen = true
        var response: NSApplication.ModalResponse = .alertSecondButtonReturn
        let support = SupportController(bundle: bundle,
                                        systemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1),
                                        pasteboard: pasteboard,
                                        openURL: { opened.append($0); return shouldOpen },
                                        runAlert: { alerts.append($0); return response })
        let menu = NSMenu(title: "Support checks")
        menu.autoenablesItems = false
        let item = support.makeMenuItem()
        menu.addItem(item)
        try require(item.title == "피드백 및 지원…" && item.isEnabled && item.target === support && item.submenu == nil,
                    "The only support channel must open directly without an email submenu")
        try require(item.toolTip?.contains("로그인") == true && item.toolTip?.contains("공개") == true,
                    "The support entry must explain sign-in and public visibility")
        menu.performActionForItem(at: 0)
        try require(opened.isEmpty, "External activation must wait until the menu action returns")
        try await wait { opened.count == 1 }
        let github = URLComponents(url: opened[0], resolvingAgainstBaseURL: false)!
        let fields = Dictionary(uniqueKeysWithValues: (github.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let version = SupportController.applicationVersion(in: bundle)!
        try require(github.scheme == "https" && github.host == "github.com" && github.path == "/largeq/nanoome-pyororong/issues/new",
                    "Support must open this project's issue form")
        try require(fields == ["template": "feedback.yml", "app-version": version, "macos-version": "27.0.1"],
                    "Only the template ID and actual app/OS versions may be prefilled")
        try require(alerts.isEmpty && pasteboard.changeCount == revision,
                    "Opening support must not show a submission confirmation or rewrite the clipboard")

        shouldOpen = false
        menu.performActionForItem(at: 0)
        try await wait { alerts.count == 1 }
        let alert = alerts[0]
        try require(alert.messageText == "GitHub 페이지를 열 수 없습니다"
                    && alert.informativeText.contains(support.githubURL.absoluteString),
                    "A browser failure must explain recovery with the actual issue URL")
        try require(alert.buttons.map(\.title) == ["GitHub 주소 복사", "닫기"] && alert.buttons[1].keyEquivalent == "\u{1b}",
                    "The failure must offer explicit copy and an Escape dismissal")
        try require(pasteboard.changeCount == revision && pasteboard.string(forType: .html) == originalHTML,
                    "Dismissing a failure must preserve copied table content")
        response = .alertFirstButtonReturn
        menu.performActionForItem(at: 0)
        try await wait { alerts.count == 2 && pasteboard.changeCount > revision }
        try require(pasteboard.string(forType: .string) == support.githubURL.absoluteString
                    && pasteboard.string(forType: .html) == nil,
                    "Only choosing copy may replace the pasteboard with the issue URL")

        if let iconURL = bundle.url(forResource: "table_icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) { icon.setName("table_icon") }
        let about = AboutController(bundle: bundle, support: support, openURL: { _ in })
        defer { about.closeAll() }
        let root = about.window!.contentView!
        let button = root.subviews.compactMap { $0 as? NSButton }.first { $0.title == SupportController.commandTitle }!
        try require(button.isEnabled && button.target === support && button.action == item.action,
                    "About and the status menu must use the same direct support command")
        try require(!root.subviews.contains { $0 is NSPopUpButton }, "About must not keep a one-item support dropdown")
        shouldOpen = true
        let beforeAbout = opened.count
        button.performClick(nil)
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
