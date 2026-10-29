import AppKit
import TableConverterMac

@MainActor
final class AppHelpWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class GuideActionButton: NSButton {
    var onFocusChanged: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChanged?(false) }
        return accepted
    }
}

@MainActor
final class UsageGuideController: NSWindowController, NSWindowDelegate {
    private let defaults: UserDefaults
    private let page = GuideBackgroundView()
    private let content = NSStackView()
    private let instructions = NSStackView()
    private let demo: UsageGuideVideoView
    private let showAtLaunch = GuideActionButton(checkboxWithTitle: "앱을 시작할 때마다 이 안내 표시", target: nil, action: nil)
    private let start = GuideActionButton(title: "시작하기", target: nil, action: nil)
    private var steps: [GuideStepButton] = []
    private var instructionsReadingOrder: [NSView] = []
    private var footerReadingOrder: [NSView] = []
    private var wantsPlayback = true

    init(defaults: UserDefaults, bundle: Bundle = .main) {
        self.defaults = defaults
        demo = UsageGuideVideoView(frame: .zero, bundle: bundle)
        let window = AppHelpWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 420),
                                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "표로롱 사용법"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = page
        configureStack(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(content)
        // Size the window to its content while allowing text to wrap and grow.
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -18)
        ])
        buildInstructions()
        content.addArrangedSubview(instructions)
        instructions.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        buildFooter()
        let keyViews: [NSView] = steps + [demo.backwardButton, demo.playbackButton, demo.forwardButton, showAtLaunch, start]
        window.autorecalculatesKeyViewLoop = false
        for (index, view) in keyViews.enumerated() { view.nextKeyView = keyViews[(index + 1) % keyViews.count] }
        window.initialFirstResponder = start
        window.makeFirstResponder(window)
        page.setAccessibilityChildren(instructionsReadingOrder + footerReadingOrder + [start])
        resizeToFit()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show(shortcut: ConversionShortcut?) {
        updateShortcut(shortcut)
        showAtLaunch.state = UsageGuidePreferences.load(from: defaults).showAtLaunch ? .on : .off
        let wasVisible = window?.isVisible == true
        if !wasVisible {
            wantsPlayback = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            demo.setPlaying(false)
            demo.selectStep(0)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if !wasVisible, let window { window.makeFirstResponder(window) }
        updatePlayback()
    }

    func updateShortcut(_ shortcut: ConversionShortcut?) {
        steps[1].detail = shortcut.map { "‘표 변환하기’ 또는 \($0.displayName)" } ?? "원 표시 확인 → ‘표 변환하기’"
        resizeToFit()
    }

    private func configureStack(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        // WWDC20 10219 uses 12pt row spacing for text groups.
        stack.spacing = 12
        stack.detachesHiddenViews = true
    }

    private func buildInstructions() {
        configureStack(instructions)
        instructions.setHuggingPriority(.required, for: .vertical)
        let title = GuideText.label("사용법", size: 26, weight: .bold)
        let titles = ["한글에서 표 복사", "메뉴바에서 표 변환", "네이버 카페·블로그 글쓰기에 붙여넣기"]
        let details = ["표를 포함한 내용 복사", "원 표시 확인 → ‘표 변환하기’", "변환 완료 후 붙여넣기(⌘V)"]
        let stepList = NSStackView()
        configureStack(stepList)
        stepList.spacing = 8
        stepList.setHuggingPriority(.required, for: .vertical)
        for index in 0..<3 {
            let step = GuideStepButton(index: index, title: titles[index], detail: details[index])
            step.target = self
            step.action = #selector(selectStep(_:))
            stepList.addArrangedSubview(step)
            step.widthAnchor.constraint(equalTo: stepList.widthAnchor).isActive = true
            steps.append(step)
        }
        let explanation = NSStackView(views: [title, stepList])
        configureStack(explanation)
        explanation.spacing = 16
        explanation.setHuggingPriority(.required, for: .vertical)
        let body = NSStackView(views: [explanation, demo])
        body.alignment = .top
        body.spacing = 18
        instructions.addArrangedSubview(body)
        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(equalTo: explanation.widthAnchor),
            stepList.widthAnchor.constraint(equalTo: explanation.widthAnchor),
            body.widthAnchor.constraint(equalTo: instructions.widthAnchor),
            explanation.widthAnchor.constraint(equalToConstant: 210),
            demo.widthAnchor.constraint(equalToConstant: 564)
        ])
        instructionsReadingOrder = [title] + steps + [demo]
        demo.onStepChanged = { [weak self] selected in self?.highlightStep(selected) }
        demo.onPlaybackRequested = { [weak self] playing in
            self?.wantsPlayback = playing
            self?.updatePlayback()
        }
        highlightStep(0)
    }

    private func buildFooter() {
        showAtLaunch.target = self
        showAtLaunch.action = #selector(changeStartupPreference)
        showAtLaunch.setContentCompressionResistancePriority(.required, for: .horizontal)
        let hint = GuideText.label("창을 닫아도 메뉴바에서 계속 실행됩니다. ‘사용법 보기’로 다시 열 수 있습니다.", size: 11, color: .secondaryLabelColor)
        let preferences = NSStackView(views: [showAtLaunch, hint])
        configureStack(preferences)
        preferences.setHuggingPriority(.required, for: .vertical)
        hint.widthAnchor.constraint(equalTo: preferences.widthAnchor).isActive = true
        start.bezelStyle = .rounded
        start.controlSize = .regular
        start.target = self
        start.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 70pt is this project's minimum, not an Apple-mandated button width.
        start.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        start.action = #selector(finish)
        start.keyEquivalent = "\r"
        let footer = NSView()
        for view in [preferences, start] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        content.addArrangedSubview(footer)
        content.setCustomSpacing(16, after: instructions)
        NSLayoutConstraint.activate([
            footer.widthAnchor.constraint(equalTo: content.widthAnchor),
            preferences.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            preferences.topAnchor.constraint(equalTo: footer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: preferences.bottomAnchor),
            start.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: preferences.trailingAnchor, multiplier: 2),
            start.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            start.topAnchor.constraint(greaterThanOrEqualTo: footer.topAnchor),
            start.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])
        footerReadingOrder = [showAtLaunch, hint]
        window?.defaultButtonCell = start.cell as? NSButtonCell
    }

    private func resizeToFit() {
        guard let window else { return }
        page.layoutSubtreeIfNeeded()
        let size = page.fittingSize
        window.setContentSize(NSSize(width: max(840, size.width), height: size.height))
        page.layoutSubtreeIfNeeded()
    }

    private func updatePlayback() {
        demo.setPlaying(wantsPlayback && NSApp.isActive && window?.isVisible == true && window?.isKeyWindow == true)
    }

    private func highlightStep(_ selected: Int) {
        for (index, step) in steps.enumerated() { step.isCurrent = index == selected }
    }

    private func announcePlayback() {
        // Announce only an explicit user action, never timer-driven progress.
        NSAccessibility.post(element: demo, notification: .announcementRequested,
            userInfo: [.announcement: demo.accessibilityLabel() ?? "", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func finish() { close() }

    @objc private func selectStep(_ sender: GuideStepButton) {
        wantsPlayback = false
        demo.setPlaying(false)
        demo.selectStep(sender.index)
        highlightStep(sender.index)
        resizeToFit()
        announcePlayback()
    }

    @objc private func changeStartupPreference() {
        UsageGuidePreferences(showAtLaunch: showAtLaunch.state == .on).save(to: defaults)
    }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { wantsPlayback = false }
        updatePlayback()
        page.needsDisplay = true
        for step in steps { step.needsDisplay = true }
        resizeToFit()
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        demo.setPlaying(false)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        updatePlayback()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updatePlayback()
    }

    func windowDidResignKey(_ notification: Notification) {
        demo.setPlaying(false)
    }
    func windowWillClose(_ notification: Notification) {
        wantsPlayback = false
        demo.setPlaying(false)
        UsageGuidePreferences.markCompleted(in: defaults)
    }
}

@MainActor
final class GuideBackgroundView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor
enum GuideText {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
}

@MainActor
final class GuideStepButton: NSButton {
    let index: Int
    private let titleField: NSTextField
    private let detailField: NSTextField
    var detail: String {
        get { detailField.stringValue }
        set { detailField.stringValue = newValue; updateAccessibility() }
    }
    var isCurrent = false {
        didSet {
            guard oldValue != isCurrent else { return }
            needsDisplay = true
            setAccessibilityValue(isCurrent ? "현재 단계" : "")
        }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    // The wrapping labels determine size instead of the unused, single-line button cell.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    init(index: Int, title: String, detail: String) {
        self.index = index
        titleField = GuideText.label("\(index + 1). \(title)", weight: .semibold)
        detailField = GuideText.label(detail, size: 11, color: .secondaryLabelColor)
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        let labels = NSStackView(views: [titleField, detailField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.distribution = .fill
        labels.spacing = 4
        labels.setHuggingPriority(.required, for: .vertical)
        labels.detachesHiddenViews = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            titleField.widthAnchor.constraint(equalTo: labels.widthAnchor),
            detailField.widthAnchor.constraint(equalTo: labels.widthAnchor)
        ])
        setAccessibilityChildren([])
        updateAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    private func updateAccessibility() {
        setAccessibilityLabel("\(index + 1)단계: \(title). \(detail)")
        setAccessibilityHelp("선택하면 해당 단계에서 시연을 일시정지합니다.")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill() }

    override func draw(_ dirtyRect: NSRect) {
        if isCurrent {
            NSColor.controlBackgroundColor.setFill()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            outline.fill()
            NSColor.labelColor.setStroke()
            outline.lineWidth = 2
            outline.stroke()
        }
    }
}
