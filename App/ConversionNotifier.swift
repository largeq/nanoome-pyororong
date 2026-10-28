import AppKit
import TableConverterCore
import TableConverterMac

@MainActor
final class ConversionNotifier: NSObject {
    weak var anchor: NSStatusBarButton?
    var onRetry: (() -> Void)?
    var onShowUsageGuide: (() -> Void)?
    private(set) var latestResult: ConversionFeedback?
    private var current: ConversionFeedback?
    private var currentClipboardRevision: Int?
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var dismissDeadline: TimeInterval?
    private var remainingTime: TimeInterval?
    private var isExpanded = false
    private var isHovered = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var presentationRevision = 0
    private static let width: CGFloat = 344

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func showConverted(_ result: ConversionResult, clipboardRevision: Int) {
        showConversion(.completed(result, clipboardRevision: clipboardRevision))
    }

    func showFailure(_ error: any Error, clipboardRevision: Int) {
        showConversion(.failed(error, clipboardRevision: clipboardRevision))
    }

    func showAlreadyConverted(clipboardRevision: Int) {
        if let latestResult, latestResult.clipboardRevision == clipboardRevision,
           latestResult.outcome != .failure {
            present(latestResult)
        } else {
            showConversion(.completed(clipboardRevision: clipboardRevision))
        }
    }

    // Settings errors use the same surface, without replacing the last conversion result.
    func show(title: String, message: String, isError: Bool = false) {
        present(ConversionFeedback(outcome: isError ? .failure : .success,
            title: title, message: message))
    }

    func showLatestResult(clipboardRevision: Int) {
        currentClipboardRevision = clipboardRevision
        guard let latestResult else { return }
        present(latestResult, automaticallyDismiss: false)
    }

    func observeClipboardRevision(_ revision: Int) {
        let changed = currentClipboardRevision != revision
        currentClipboardRevision = revision
        // Hide the old actionable notice when the user copies something new.
        if changed, panel?.isVisible == true, let shownRevision = current?.clipboardRevision,
           shownRevision != revision {
            dismiss()
        }
    }

    private func showConversion(_ feedback: ConversionFeedback) {
        latestResult = feedback
        currentClipboardRevision = feedback.clipboardRevision
        present(feedback)
    }

    private var isStale: Bool {
        guard let revision = current?.clipboardRevision,
              let currentClipboardRevision else { return false }
        return revision != currentClipboardRevision
    }

    private func present(_ feedback: ConversionFeedback, automaticallyDismiss: Bool = true) {
        dismiss()
        current = feedback
        isExpanded = false
        isHovered = false
        remainingTime = automaticallyDismiss ? feedback.autoDismissInterval : nil
        let panel = ConversionResultPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.setAccessibilityLabel("표로롱 변환 결과")
        self.panel = panel
        rebuildContent()
        // A nonactivating panel leaves the insertion point in Hangul or the browser.
        panel.orderFrontRegardless()
        isHovered = panel.frame.contains(NSEvent.mouseLocation)
        installEventMonitors()
        resumeAutoDismiss()
    }

    func dismiss() {
        presentationRevision += 1
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismissDeadline = nil
        remainingTime = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        current = nil
    }

    func stop() {
        dismiss()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func rebuildContent(animate: Bool = false) {
        guard let panel, let feedback = current else { return }
        let body = ResultHoverView()
        body.onHover = { [weak self] inside in
            guard let self else { return }
            self.isHovered = inside
            if inside { self.pauseAutoDismiss() } else { self.resumeAutoDismiss() }
        }
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalToConstant: Self.width - 40)
        ])

        let appName = label("표로롱", size: 11, weight: .medium, color: .secondaryLabelColor)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "닫기")!,
                             target: self, action: #selector(closeNotice))
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = "닫기"
        close.setAccessibilityLabel("결과 안내 닫기")
        close.widthAnchor.constraint(equalToConstant: 16).isActive = true
        close.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let header = NSStackView(views: [appName, NSView(), close])
        header.spacing = 8
        add(header, to: content)

        let symbolName = isStale ? "clock" : feedback.outcome == .failure ? "exclamationmark" : "checkmark"
        let symbol = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))!)
        symbol.contentTintColor = isStale ? .secondaryLabelColor : feedback.outcome == .failure ? .systemRed
            : feedback.outcome == .partialSuccess ? NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 1, green: 0.773, blue: 0.416, alpha: 1)
                    : NSColor(srgbRed: 0.612, green: 0.373, blue: 0.027, alpha: 1)
            }) : .systemGreen
        symbol.widthAnchor.constraint(equalToConstant: 20).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 22).isActive = true
        symbol.setAccessibilityElement(false)
        let heading = label(isStale ? "이전 변환 결과" : feedback.title, size: 16, weight: .semibold)
        heading.preferredMaxLayoutWidth = Self.width - 68
        let message: String
        if isStale {
            message = "복사한 내용이 바뀌었습니다.\n이 결과는 현재 클립보드와 다릅니다."
        } else {
            message = feedback.message
        }
        let description = label(message, size: 13)
        description.preferredMaxLayoutWidth = Self.width - 68
        let text = NSStackView(views: [heading, description])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        heading.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        description.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        let result = NSStackView(views: [symbol, text])
        result.alignment = .top
        result.spacing = 8
        add(result, to: content)

        if isExpanded {
            let separator = NSBox()
            separator.boxType = .separator
            add(separator, to: content)
            if isStale {
                add(label("당시 결과: \(feedback.title)", size: 13, weight: .semibold), to: content)
                if feedback.outcome == .failure {
                    add(label(feedback.message, size: 13, color: .secondaryLabelColor), to: content)
                }
            }
            for detail in feedback.details {
                let title = label(detail.title, size: 13, weight: .semibold)
                let message = label(detail.message, size: 13, color: .secondaryLabelColor)
                let row = NSStackView(views: [title, message])
                row.orientation = .vertical
                row.alignment = .leading
                row.spacing = 5
                title.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
                message.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
                add(row, to: content)
            }
        }

        let footer = NSStackView()
        footer.spacing = 8
        if isStale || !feedback.details.isEmpty {
            let more = button(isExpanded ? "간단히 보기" : isStale ? "당시 결과 보기" : "자세히 보기",
                              action: #selector(toggleDetails))
            more.setAccessibilityValue(isExpanded ? "펼쳐짐" : "접힘")
            footer.addArrangedSubview(more)
        }
        if !isStale {
            switch feedback.recoveryAction {
            case .retry:
                let retry = button("다시 변환", action: #selector(retryConversion))
                retry.bezelColor = .controlAccentColor
                retry.contentTintColor = .white
                footer.addArrangedSubview(retry)
            case .usageGuide:
                footer.addArrangedSubview(button("사용법 보기", action: #selector(showUsageGuide)))
            case .none:
                break
            }
        }
        if !footer.arrangedSubviews.isEmpty {
            footer.addArrangedSubview(NSView())
            add(footer, to: content)
        }

        let height = ceil(content.fittingSize.height) + 34
        let size = NSSize(width: Self.width, height: height)
        body.frame = NSRect(origin: .zero, size: size)
        panel.contentView = background(containing: body)
        // Assigning contentView can resize its descendants to the OLD window size.
        positionPanel(size: size,
                      animate: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func background(containing body: ResultHoverView) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            body.surface = .solid
            return body
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: body.frame)
            glass.style = .regular
            glass.cornerRadius = 20
            // Keep the system glass contour while attenuating the backdrop under text.
            body.surface = .readable
            glass.contentView = body
            return glass
        }
        let effect = NSVisualEffectView(frame: body.frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.masksToBounds = true
        body.autoresizingMask = [.width, .height]
        effect.addSubview(body)
        return effect
    }

    private func positionPanel(size: NSSize, animate: Bool = false) {
        guard let panel else { return }
        let visible = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let origin = anchor.flatMap { button in
            button.window?.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let x = min(max((origin?.midX ?? visible.maxX) - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = max(visible.minY + 8, min((origin?.minY ?? visible.maxY) - size.height - 6, visible.maxY - size.height - 6))
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: animate)
    }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = Self.width - 40
        return field
    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .medium)
        return button
    }

    @objc private func closeNotice() { dismiss() }

    @objc private func retryConversion() {
        dismiss()
        onRetry?()
    }

    @objc private func showUsageGuide() {
        dismiss()
        onShowUsageGuide?()
    }

    @objc private func toggleDetails() {
        pauseAutoDismiss()
        isExpanded.toggle()
        rebuildContent(animate: true)
        isHovered = panel?.frame.contains(NSEvent.mouseLocation) == true
        resumeAutoDismiss()
    }

    @objc private func accessibilityOptionsChanged() {
        guard panel?.isVisible == true else { return }
        rebuildContent()
    }

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        positionPanel(size: panel.frame.size)
    }

    private func pauseAutoDismiss() {
        if let dismissDeadline {
            remainingTime = max(0, dismissDeadline - ProcessInfo.processInfo.systemUptime)
        }
        dismissTimer?.invalidate()
        dismissTimer = nil
        dismissDeadline = nil
    }

    private func resumeAutoDismiss() {
        guard !isHovered, !isExpanded, dismissTimer == nil, let remainingTime else { return }
        dismissDeadline = ProcessInfo.processInfo.systemUptime + remainingTime
        let revision = presentationRevision
        let timer = Timer(timeInterval: max(0.1, remainingTime), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.presentationRevision == revision,
                      self.dismissDeadline != nil, !self.isHovered, !self.isExpanded else { return }
                self.dismiss()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func installEventMonitors() {
        let revision = presentationRevision
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.presentationRevision == revision else { return }
                self.dismiss()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53, event.window === panel { self.dismiss(); return true }
                } else if event.window !== panel {
                    self.dismiss()
                }
                return false
            }
            return consumed ? nil : event
        }
    }
}

@MainActor
private final class ConversionResultPanel: NSPanel {
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.18 }
}

@MainActor
private final class ResultHoverView: NSView {
    enum Surface { case transparent, readable, solid }
    var surface: Surface = .transparent { didSet { updateSurface() } }
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }

    private func updateSurface() {
        guard surface != .transparent else { return }
        wantsLayer = true
        layer?.cornerRadius = 20
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor
            if surface == .solid {
                color = .windowBackgroundColor
            } else {
                let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let base: NSColor = dark ? NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1) : .white
                color = base.withAlphaComponent(0.65)
            }
            layer?.backgroundColor = color.cgColor
        }
    }

    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
