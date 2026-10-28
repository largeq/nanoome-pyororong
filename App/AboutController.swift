import AppKit

@MainActor
final class AboutController: NSWindowController {
    static let applicationName = SupportController.applicationName
    static let repositoryURL = SupportController.repositoryURL
    private let bundle: Bundle
    private let openURL: (URL) -> Void
    private let support: SupportController
    private var licenses: NSWindowController?

    init(bundle: Bundle = .main, support: SupportController? = nil,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.bundle = bundle
        self.openURL = openURL
        self.support = support ?? SupportController(bundle: bundle)
        let window = AppHelpWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 312),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "\(Self.applicationName)에 관하여"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = GuideBackgroundView(frame: NSRect(x: 0, y: 0, width: 460, height: 312))
        window.contentView = content
        let icon = NSImageView(frame: NSRect(x: 198, y: 20, width: 64, height: 64))
        let appIcon = (NSImage(named: "table_icon")?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        appIcon?.isTemplate = true
        icon.image = appIcon
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)
        addLabel(Self.applicationName, to: content, frame: NSRect(x: 24, y: 90, width: 412, height: 28), size: 20, weight: .bold)
        let versionText = SupportController.applicationVersion(in: bundle).map { "버전 \($0)" } ?? "버전 정보 없음"
        addLabel(versionText, to: content, frame: NSRect(x: 24, y: 120, width: 412, height: 20), size: 13, color: .secondaryLabelColor)
        addLabel("한글 표를 네이버 카페·블로그에 맞게 변환합니다.",
                 to: content, frame: NSRect(x: 24, y: 158, width: 412, height: 20), size: 13)
        addLabel("복사한 내용은 이 Mac에서만 처리합니다.", to: content,
                 frame: NSRect(x: 32, y: 190, width: 396, height: 18), size: 11, color: .secondaryLabelColor)
        let github = NSButton(title: "프로젝트 페이지", target: self, action: #selector(showRepository))
        github.bezelStyle = .rounded
        github.setAccessibilityHelp(Self.repositoryURL.absoluteString)
        let license = NSButton(title: "오픈 소스 라이선스", target: self, action: #selector(showLicenses))
        license.bezelStyle = .rounded
        let githubWidth = ceil(github.intrinsicContentSize.width)
        let licenseWidth = ceil(license.intrinsicContentSize.width)
        let buttonsX = (content.bounds.width - githubWidth - licenseWidth - 12) / 2
        github.frame = NSRect(x: buttonsX, y: 228, width: githubWidth, height: 32)
        license.frame = NSRect(x: buttonsX + githubWidth + 12, y: 228, width: licenseWidth, height: 32)
        content.addSubview(github)
        content.addSubview(license)
        let supportButton = NSPopUpButton(frame: .zero, pullsDown: true)
        let supportMenu = self.support.makeMenu()
        supportMenu.insertItem(withTitle: SupportController.commandTitle, action: nil, keyEquivalent: "", at: 0)
        supportButton.menu = supportMenu
        supportButton.isBordered = false
        supportButton.setAccessibilityLabel("피드백 및 지원")
        supportButton.setAccessibilityHelp(SupportController.commandHelp)
        let supportWidth = ceil(supportButton.intrinsicContentSize.width)
        supportButton.frame = NSRect(x: (content.bounds.width - supportWidth) / 2, y: 268, width: supportWidth, height: 24)
        content.addSubview(supportButton)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        licenses?.close()
        close()
    }

    private func addLabel(_ text: String, to view: NSView, frame: NSRect, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.alignment = .center
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        view.addSubview(label)
    }

    @objc private func showRepository() { openURL(Self.repositoryURL) }

    @objc private func showLicenses() {
        if licenses == nil {
            let window = AppHelpWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "오픈 소스 라이선스"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 480, height: 320)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 600, height: 440))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textColor = .labelColor
            text.backgroundColor = .textBackgroundColor
            text.textContainerInset = NSSize(width: 14, height: 14)
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            if let url = bundle.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt"),
               let notice = try? String(contentsOf: url, encoding: .utf8) {
                text.string = notice
            } else {
                text.string = "오픈 소스 고지를 불러올 수 없습니다. 앱을 다시 설치한 뒤 확인해 주세요."
            }
            text.setAccessibilityLabel("앱에 포함된 오픈 소스 고지 및 라이선스")
            scroll.documentView = text
            window.contentView?.addSubview(scroll)
            window.center()
            licenses = NSWindowController(window: window)
        }
        licenses?.showWindow(nil)
        licenses?.window?.makeKeyAndOrderFront(nil)
    }
}
