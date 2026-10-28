import AppKit

@MainActor
final class SupportController: NSObject {
    static let applicationName = "표로롱"
    static let repositoryURL = URL(string: "https://github.com/largeq/nanoome-pyororong")!
    static let commandTitle = "피드백 및 지원…"
    static let commandHelp = "GitHub 로그인이 필요하며, 문의 내용과 첨부파일은 공개됩니다."

    private let bundle: Bundle
    private let systemVersion: OperatingSystemVersion
    private let pasteboard: NSPasteboard
    private let openURL: @MainActor (URL) -> Bool
    private let runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse

    init(bundle: Bundle = .main,
         systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
         pasteboard: NSPasteboard = .general,
         openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
         runAlert: @escaping @MainActor (NSAlert) -> NSApplication.ModalResponse = {
             NSApp.activate(ignoringOtherApps: true)
             return $0.runModal()
         }) {
        self.bundle = bundle
        self.systemVersion = systemVersion
        self.pasteboard = pasteboard
        self.openURL = openURL
        self.runAlert = runAlert
        super.init()
    }

    static func applicationVersion(in bundle: Bundle) -> String? {
        guard var version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        if version.split(separator: ".").count == 3, version.hasSuffix(".0") { version = String(version.dropLast(2)) }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String { version += " (\(build))" }
        return version
    }

    private var macOSVersion: String {
        let version = systemVersion
        return "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion == 0 ? "" : ".\(version.patchVersion)")
    }

    var githubURL: URL {
        var url = URLComponents(url: Self.repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "template", value: "feedback.yml"),
            URLQueryItem(name: "app-version", value: Self.applicationVersion(in: bundle) ?? "버전 정보 없음"),
            URLQueryItem(name: "macos-version", value: macOSVersion)
        ]
        return url.url!
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: Self.commandTitle, action: #selector(showSupport(_:)), keyEquivalent: "")
        item.target = self
        item.toolTip = Self.commandHelp
        return item
    }

    @objc func showSupport(_ sender: Any?) {
        // Let status-menu tracking finish before activating another app or showing an alert.
        DispatchQueue.main.async { [self] in
            let url = githubURL
            guard !openURL(url) else { return }
            let alert = NSAlert()
            alert.messageText = "GitHub 페이지를 열 수 없습니다"
            alert.informativeText = "주소를 복사해 브라우저에서 열어 주세요.\n\n" + url.absoluteString
            alert.addButton(withTitle: "GitHub 주소 복사")
            alert.addButton(withTitle: "닫기").keyEquivalent = "\u{1b}"
            if runAlert(alert) == .alertFirstButtonReturn {
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)
            }
        }
    }
}
