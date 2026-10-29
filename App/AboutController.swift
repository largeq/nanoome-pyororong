import AppKit

@MainActor
final class AboutController: NSWindowController, NSWindowDelegate {
    static let applicationName = SupportController.applicationName
    static let repositoryURL = SupportController.repositoryURL
    private let bundle: Bundle
    private let openURL: (URL) -> Void
    private let iconImages: [NSImage?]
    private let icon = AboutIconButton(frame: NSRect(x: 198, y: 20, width: 64, height: 64))
    private let nameLabel = AboutNameLabel(labelWithString: SupportController.applicationName)
    private var iconClickCount = 0
    private var resetTask: Task<Void, Never>?
    private var licenses: NSWindowController?

    init(bundle: Bundle = .main,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.bundle = bundle
        self.openURL = openURL
        let defaultIcon = bundle.image(forResource: "AboutAppIcon")
            ?? NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)
        self.iconImages = [defaultIcon] + (6...10).map {
            bundle.image(forResource: "AboutEasterEgg\($0)") ?? defaultIcon
        }
        let window = AppHelpWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "\(Self.applicationName)에 관하여"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = GuideBackgroundView(frame: NSRect(x: 0, y: 0, width: 460, height: 280))
        window.contentView = content
        icon.image = iconImages[0]
        icon.title = ""
        icon.imagePosition = .imageOnly
        icon.isBordered = false
        icon.setButtonType(.momentaryChange)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.target = self
        icon.action = #selector(pressIcon)
        icon.setAccessibilityLabel("표로롱 앱 아이콘")
        icon.wantsLayer = true
        content.addSubview(icon)
        nameLabel.frame = NSRect(x: 24, y: 90, width: 412, height: 28)
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        content.addSubview(nameLabel)
        let versionText = SupportController.applicationVersion(in: bundle).map { "버전 \($0)" } ?? "버전 정보 없음"
        addLabel(versionText, to: content, frame: NSRect(x: 24, y: 120, width: 412, height: 20), size: 13, color: .secondaryLabelColor)
        let introduction = addLabel("""
        표로롱은 서울대학교 프로네시스 나눔실천단 ‘나눔교실’을 준비하는 과정에서 탄생하였습니다.
        네이버 카페에 각종 자료를 올릴 때, Mac용 한글에서 복사한 복잡한 표가 붙여넣기 후 깨지는 문제가 있습니다.
        표로롱은 표를 다시 손보는 수고를 줄이고, Mac에서도 한글 문서를 편리하게 공유할 수 있도록 합니다.
        """, to: content, frame: NSRect(x: 32, y: 158, width: 396, height: 0), size: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6
        let introductionText = NSMutableAttributedString(string: introduction.stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        introductionText.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13),
                                      range: NSRange(location: 0, length: Self.applicationName.utf16.count))
        introduction.attributedStringValue = introductionText
        introduction.alignment = .left
        introduction.frame.size.height = ceil(introduction.cell!.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: 396, height: 10000)).height)
        let credit = addLabel("제작 프로네시스 나눔실천단 38기 재무부장 정근규", to: content,
                              frame: NSRect(x: 32, y: introduction.frame.maxY + 16, width: 396, height: 20), size: 12)
        let creditText = NSMutableAttributedString(string: credit.stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
        ])
        creditText.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 2))
        credit.attributedStringValue = creditText
        let github = NSButton(title: "프로젝트 페이지", target: self, action: #selector(showRepository))
        github.bezelStyle = .rounded
        github.setAccessibilityHelp(Self.repositoryURL.absoluteString)
        let license = NSButton(title: "오픈 소스 라이선스", target: self, action: #selector(showLicenses))
        license.bezelStyle = .rounded
        let githubWidth = ceil(github.intrinsicContentSize.width)
        let licenseWidth = ceil(license.intrinsicContentSize.width)
        let buttonsX = (content.bounds.width - githubWidth - licenseWidth - 12) / 2
        let buttonsY = credit.frame.maxY + 20
        github.frame = NSRect(x: buttonsX, y: buttonsY, width: githubWidth, height: 32)
        license.frame = NSRect(x: buttonsX + githubWidth + 12, y: buttonsY, width: licenseWidth, height: 32)
        content.addSubview(github)
        content.addSubview(license)
        window.setContentSize(NSSize(width: 460, height: buttonsY + 52))
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        resetEasterEgg()
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeAll() {
        licenses?.close()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        resetEasterEgg()
    }

    @objc private func pressIcon() {
        guard iconClickCount < 10 else { return }
        iconClickCount += 1
        if iconClickCount > 5 {
            icon.image = iconImages[iconClickCount - 5]
        }
        if iconClickCount == 10 {
            nameLabel.showEasterEgg()
            resetTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
                self?.resetEasterEgg()
            }
        }
    }

    private func resetEasterEgg() {
        resetTask?.cancel()
        resetTask = nil
        iconClickCount = 0
        icon.image = iconImages[0]
        nameLabel.reset()
    }

    @discardableResult
    private func addLabel(_ text: String, to view: NSView, frame: NSRect, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.allowsEditingTextAttributes = true
        label.frame = frame
        label.alignment = .center
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        view.addSubview(label)
        return label
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

@MainActor
final class AboutNameLabel: NSTextField {
    private var shimmerTask: Task<Void, Never>?
    private(set) var shimmerProgress: CGFloat? { didSet { needsDisplay = true } }

    func showEasterEgg() {
        reset()
        stringValue = "프네프네 포로롱"
        needsDisplay = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        shimmerProgress = 0
        shimmerTask = Task { @MainActor [weak self] in
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self else { return }
                let progress = (ProcessInfo.processInfo.systemUptime - start) / 1.1
                if progress >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.shimmerProgress = nil
                    self.shimmerTask = nil
                    return
                }
                self.shimmerProgress = CGFloat(progress)
                do { try await Task.sleep(nanoseconds: 16_666_667) }
                catch { return }
            }
        }
    }

    func reset() {
        shimmerTask?.cancel()
        shimmerTask = nil
        shimmerProgress = nil
        stringValue = AboutController.applicationName
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard stringValue == "프네프네 포로롱" else {
            super.draw(dirtyRect)
            return
        }
        let title = stringValue
        let titleFont = font ?? .systemFont(ofSize: 20, weight: .bold)
        let progress = shimmerProgress
        let image = NSImage(size: bounds.size, flipped: false) { rect in
            let size = (title as NSString).size(withAttributes: [.font: titleFont])
            let textRect = NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                  width: size.width, height: size.height)
            let maskImage = NSImage(size: rect.size, flipped: false) { _ in
                (title as NSString).draw(in: textRect, withAttributes: [.font: titleFont, .foregroundColor: NSColor.white])
                return true
            }
            guard let context = NSGraphicsContext.current?.cgContext,
                  let mask = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                (title as NSString).draw(in: textRect, withAttributes: [.font: titleFont, .foregroundColor: NSColor.labelColor])
                return true
            }
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: rect, mask: mask)
            let base = NSGradient(colors: [
                NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
                NSColor(srgbRed: 0, green: 0.75, blue: 0.5, alpha: 1),
                NSColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1)
            ])!
            base.draw(in: textRect, angle: -65)
            if let progress {
                let glint = NSGradient(colorsAndLocations:
                    (NSColor.white.withAlphaComponent(0), 0), (NSColor.white.withAlphaComponent(0.65), 0.32),
                    (NSColor.white, 0.5), (NSColor.white.withAlphaComponent(0.65), 0.68), (NSColor.white.withAlphaComponent(0), 1))!
                let halfWidth: CGFloat = 29
                let eased = progress * progress * (3 - 2 * progress)
                let center = textRect.minX - halfWidth + (textRect.width + 2 * halfWidth) * eased
                glint.draw(from: NSPoint(x: center - halfWidth, y: rect.midY),
                           to: NSPoint(x: center + halfWidth, y: rect.midY), options: [])
            }
            return true
        }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class AboutIconButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 64) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDepthEffect()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDepthEffect()
    }

    private func updateDepthEffect() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let effect = NSShadow()
        effect.shadowColor = isDark
            ? NSColor(srgbRed: 0.28, green: 0.60, blue: 0.87, alpha: 0.5)
            : NSColor.black.withAlphaComponent(0.18)
        effect.shadowBlurRadius = isDark ? 10 : 6
        effect.shadowOffset = NSSize(width: 0, height: isDark ? 0 : 2)
        shadow = effect
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let context = NSGraphicsContext.current?.cgContext else {
            super.draw(dirtyRect)
            return
        }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: 0.94, y: 0.94)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        super.draw(dirtyRect)
        context.restoreGState()
    }
}
