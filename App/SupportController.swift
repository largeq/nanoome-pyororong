import AppKit

@MainActor
final class SupportController: NSObject {
    static let applicationName = "표로롱"
    static let repositoryURL = URL(string: "https://github.com/largeq/nanoome-pyororong")!
    static let commandTitle = "피드백 및 지원"
    static let commandHelp = "이메일 또는 GitHub로 문의할 수 있습니다."

    private let bundle: Bundle
    private let configuredEmailAddress: String?
    private let systemVersion: OperatingSystemVersion
    private let pasteboard: NSPasteboard
    private let openURL: @MainActor (URL) -> Bool
    private let runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse

    init(bundle: Bundle = .main, emailAddress: String? = nil,
         systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
         pasteboard: NSPasteboard = .general,
         openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
         runAlert: @escaping @MainActor (NSAlert) -> NSApplication.ModalResponse = {
             NSApp.activate(ignoringOtherApps: true)
             return $0.runModal()
         }) {
        self.bundle = bundle
        self.configuredEmailAddress = emailAddress ?? bundle.object(forInfoDictionaryKey: "PyororongSupportEmail") as? String
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

    var emailAddress: String? {
        guard let address = configuredEmailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              address.rangeOfCharacter(from: CharacterSet(charactersIn: "?,#&<>;")) == nil else { return nil }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return address
    }

    var emailURL: URL? {
        guard let emailAddress else { return nil }
        var url = URLComponents()
        url.scheme = "mailto"
        url.path = emailAddress
        url.queryItems = [
            URLQueryItem(name: "subject", value: "[표로롱] 피드백 및 지원"),
            URLQueryItem(name: "body", value: """
            문의 종류(문제 신고 / 개선 제안 / 사용 문의):

            문의 내용:


            표로롱 버전: \(Self.applicationVersion(in: bundle) ?? "버전 정보 없음")
            macOS 버전: \(macOSVersion)
            """)
        ]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return url.url
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
        let item = NSMenuItem(title: Self.commandTitle, action: nil, keyEquivalent: "")
        item.submenu = makeMenu()
        item.toolTip = Self.commandHelp
        return item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: Self.commandTitle)
        menu.autoenablesItems = false
        let email = NSMenuItem(title: "이메일로 문의…", action: #selector(showEmail(_:)), keyEquivalent: "")
        email.target = self
        email.isEnabled = emailURL != nil
        email.toolTip = email.isEnabled ? "기본 메일 앱에서 초안을 엽니다. 보내기를 눌러야 전송됩니다."
            : "문의 수신 주소가 아직 설정되지 않았습니다."
        menu.addItem(email)
        let github = NSMenuItem(title: "GitHub에 의견 남기기…", action: #selector(showGitHub(_:)), keyEquivalent: "")
        github.target = self
        github.toolTip = "GitHub 로그인이 필요하며, 문의 내용과 첨부파일은 공개됩니다."
        menu.addItem(github)
        return menu
    }

    @objc private func showEmail(_ sender: Any?) {
        guard let url = emailURL, let emailAddress else { return }
        open(url, errorTitle: "메일 앱을 열 수 없습니다",
             errorMessage: "문의 이메일 주소를 복사해 웹메일이나 다른 메일 앱에서 보내 주세요.",
             copyTitle: "문의 이메일 주소 복사", copyText: emailAddress)
    }

    @objc private func showGitHub(_ sender: Any?) {
        let url = githubURL
        open(url, errorTitle: "GitHub 페이지를 열 수 없습니다", errorMessage: "주소를 복사해 브라우저에서 열어 주세요.",
             copyTitle: "GitHub 주소 복사", copyText: url.absoluteString)
    }

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func open(_ url: URL, errorTitle: String, errorMessage: String, copyTitle: String, copyText: String) {
        // Let status-menu tracking finish before activating another app or showing an alert.
        DispatchQueue.main.async { [self] in
            guard !openURL(url) else { return }
            let alert = NSAlert()
            alert.messageText = errorTitle
            alert.informativeText = errorMessage + "\n\n" + copyText
            alert.addButton(withTitle: copyTitle)
            alert.addButton(withTitle: "닫기").keyEquivalent = "\u{1b}"
            if runAlert(alert) == .alertFirstButtonReturn {
                copy(copyText)
            }
        }
    }
}
