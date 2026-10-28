import AppKit
import Carbon
import TableConverterMac

@MainActor
class ShortcutSettingsButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        let handled = super.sendAction(action, to: target)
        if handled, let window = window as? ShortcutRecordingWindow, window.isVisible,
           window.isHandlingMouseDown, window.recorder?.isRecording != true {
            window.makeFirstResponder(window)
        }
        return handled
    }
}

@MainActor
final class ShortcutRecorderButton: ShortcutSettingsButton {
    private(set) var shortcut = ConversionShortcut.default
    private(set) var isRecording = false
    var onRecordingChanged: ((Bool) -> Void)?
    var onValidationError: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        target = self
        action = #selector(toggleRecording)
        updateTitle()
        setAccessibilityHelp("클릭한 뒤 원하는 단축키를 누르세요. Esc를 누르면 입력을 취소합니다.")
    }

    required init?(coder: NSCoder) { nil }
    func setShortcut(_ shortcut: ConversionShortcut) {
        cancelRecording()
        self.shortcut = shortcut
        updateTitle()
    }

    @objc private func toggleRecording() {
        if isRecording { cancelRecording(); return }
        guard isEnabled else { return }
        isRecording = true
        updateTitle()
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        updateTitle()
        onRecordingChanged?(false)
    }

    /// Called before normal menu equivalents, so Command shortcuts can be recorded.
    func capture(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return true }
        if event.keyCode == UInt16(kVK_Tab) { cancelRecording(); return false }
        guard let value = ConversionShortcut(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags) else {
            onValidationError?("단축키 조합을 확인해 주세요.")
            return true
        }
        shortcut = value
        cancelRecording()
        return true
    }

    func previewModifiers(_ event: NSEvent) {
        guard isRecording else { return }
        let flags = event.modifierFlags
        let symbols = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
        title = symbols.isEmpty ? "단축키를 누르세요…" : symbols + " …"
    }

    private func updateTitle() {
        title = isRecording ? "단축키를 누르세요…" : shortcut.displayName
        setAccessibilityLabel(isRecording ? "설정할 단축키를 누르세요" : "변환 단축키: \(shortcut.displayName)")
    }

    override func resignFirstResponder() -> Bool {
        if (window as? ShortcutRecordingWindow)?.isHandlingMouseDown != true { cancelRecording() }
        return super.resignFirstResponder()
    }
}

@MainActor
final class ShortcutRecordingWindow: NSWindow {
    weak var recorder: ShortcutRecorderButton?
    weak var recordingFeedback: NSView?
    private(set) var isHandlingMouseDown = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recorder?.capture(event) == true { return true }
        if event.keyCode == UInt16(kVK_ANSI_W),
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, recorder?.capture(event) == true { return }
        if event.type == .flagsChanged { recorder?.previewModifiers(event) }
        if event.type == .leftMouseDown || event.type == .leftMouseUp {
            let outsideRecorder = recorder.map { !$0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? true
            let outsideFeedback = recordingFeedback.map { $0.isHiddenOrHasHiddenAncestor || !$0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? true
            let shouldStop = recorder?.isRecording == true && outsideRecorder && outsideFeedback
            // Finish button tracking before hiding an error moves the buttons under the pointer.
            isHandlingMouseDown = true
            super.sendEvent(event)
            isHandlingMouseDown = false
            if shouldStop { recorder?.cancelRecording() }
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    private let enabled = ShortcutSettingsButton(checkboxWithTitle: "단축키 사용", target: nil, action: nil)
    private let shortcutLabel = NSTextField(labelWithString: "표 변환하기")
    private let recorder = ShortcutRecorderButton()
    private let helpLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let inputGuidance = NSTextField(wrappingLabelWithString:
        "Command(⌘), Control(⌃), Option(⌥), Shift(⇧)는 다른 키와 함께 누르는 키입니다.\n\n이 중 2개 이상을 누른 채, P처럼 영문자가 적힌 키 하나를 누르세요. Command 또는 Control은 꼭 포함하세요.\n\n예: Command + Shift를 누른 채 P")
    private let feedback = NSStackView()
    private let saveButton = ShortcutSettingsButton(title: "저장", target: nil, action: nil)
    private let content = NSStackView()
    private let onApply: (ShortcutPreferences) throws -> Void
    private var savedPreferences = ShortcutPreferences()

    private var pendingPreferences: ShortcutPreferences {
        ShortcutPreferences(isEnabled: enabled.state == .on, shortcut: recorder.shortcut)
    }

    init(onApply: @escaping (ShortcutPreferences) throws -> Void, onRecordingChanged: @escaping (Bool) -> Void) {
        self.onApply = onApply
        let window = ShortcutRecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "단축키 설정"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.recorder = recorder
        window.recordingFeedback = feedback
        recorder.onRecordingChanged = { [weak self] recording in
            self?.clearError()
            onRecordingChanged(recording)
        }
        recorder.onValidationError = { [weak self] message in self?.showError(message, explainInput: true) }
        enabled.target = self
        enabled.action = #selector(updateEnabled)
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for label in [helpLabel, inputGuidance] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
        }
        let explanation = NSTextField(wrappingLabelWithString: "다른 앱을 사용하는 중에도 표를 변환할 수 있습니다.")
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.textColor = .secondaryLabelColor
        explanation.preferredMaxLayoutWidth = 380
        let enableGroup = NSView()
        for view in [enabled, explanation] {
            view.translatesAutoresizingMaskIntoConstraints = false
            enableGroup.addSubview(view)
        }
        for stack in [content, feedback] { configure(stack) }
        feedback.spacing = 6
        feedback.addArrangedSubview(errorLabel)
        feedback.addArrangedSubview(inputGuidance)
        feedback.isHidden = true
        inputGuidance.isHidden = true
        let field = NSStackView(views: [recorder, helpLabel, feedback])
        configure(field)
        field.spacing = 7
        let row = NSView()
        for view in [shortcutLabel, field] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        let reset = ShortcutSettingsButton(title: "기본 단축키로 복원", target: self, action: #selector(resetShortcut))
        let cancel = ShortcutSettingsButton(title: "취소", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let spacer = NSView()
        let buttons = NSStackView(views: [reset, spacer, cancel, saveButton])
        buttons.spacing = 8
        let separator = NSBox()
        separator.boxType = .separator
        let actions = NSStackView(views: [separator, buttons])
        configure(actions)
        actions.spacing = 16
        for view in [enableGroup, row, actions] { content.addArrangedSubview(view) }
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(content)
        if let view = window.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
                content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
                enableGroup.widthAnchor.constraint(equalTo: content.widthAnchor),
                enabled.leadingAnchor.constraint(equalTo: enableGroup.leadingAnchor),
                enabled.topAnchor.constraint(equalTo: enableGroup.topAnchor),
                explanation.leadingAnchor.constraint(equalTo: enableGroup.leadingAnchor, constant: 20),
                explanation.trailingAnchor.constraint(equalTo: enableGroup.trailingAnchor),
                explanation.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 5),
                explanation.bottomAnchor.constraint(equalTo: enableGroup.bottomAnchor),
                row.widthAnchor.constraint(equalTo: content.widthAnchor),
                shortcutLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                shortcutLabel.widthAnchor.constraint(equalToConstant: 96),
                shortcutLabel.topAnchor.constraint(equalTo: recorder.topAnchor, constant: 7),
                field.leadingAnchor.constraint(equalTo: shortcutLabel.trailingAnchor, constant: 12),
                field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                field.topAnchor.constraint(equalTo: row.topAnchor),
                field.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                recorder.widthAnchor.constraint(equalTo: field.widthAnchor),
                recorder.heightAnchor.constraint(equalToConstant: 32),
                helpLabel.widthAnchor.constraint(equalTo: field.widthAnchor),
                feedback.widthAnchor.constraint(equalTo: field.widthAnchor),
                errorLabel.widthAnchor.constraint(equalTo: feedback.widthAnchor),
                inputGuidance.widthAnchor.constraint(equalTo: feedback.widthAnchor),
                actions.widthAnchor.constraint(equalTo: content.widthAnchor),
                separator.widthAnchor.constraint(equalTo: actions.widthAnchor),
                buttons.widthAnchor.constraint(equalTo: actions.widthAnchor)
            ])
        }
        for label in [helpLabel, errorLabel, inputGuidance] { label.preferredMaxLayoutWidth = 292 }
        recorder.setAccessibilityTitleUIElement(shortcutLabel)
        let keyViews: [NSView] = [enabled, recorder, reset, cancel, saveButton]
        window.autorecalculatesKeyViewLoop = false
        for (index, view) in keyViews.enumerated() { view.nextKeyView = keyViews[(index + 1) % keyViews.count] }
        window.initialFirstResponder = enabled
        populate(ShortcutPreferences())
        resizeToFit()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    private func configure(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.detachesHiddenViews = true
    }

    func show(preferences: ShortcutPreferences) {
        // Keep unsaved edits if the user opens the already-visible settings again.
        if window?.isVisible != true { populate(preferences) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func populate(_ preferences: ShortcutPreferences) {
        savedPreferences = preferences
        enabled.state = preferences.isEnabled ? .on : .off
        recorder.setShortcut(preferences.shortcut)
        updateEnabled()
    }

    @objc private func updateEnabled() {
        recorder.cancelRecording()
        clearError()
    }

    @objc private func resetShortcut() {
        recorder.setShortcut(.default)
        clearError()
    }
    @objc private func cancel() { close() }

    @objc private func save() {
        guard saveButton.isEnabled else { return }
        recorder.cancelRecording()
        let preferences = pendingPreferences
        do {
            try onApply(preferences)
            savedPreferences = preferences
            close()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func windowDidResignKey(_ notification: Notification) { recorder.cancelRecording() }
    func windowWillClose(_ notification: Notification) { recorder.cancelRecording() }

    private func showError(_ message: String, explainInput: Bool = false) {
        errorLabel.stringValue = message
        feedback.isHidden = false
        inputGuidance.isHidden = !explainInput
        updateControls()
        let announcement = message + (explainInput ? "\n" + inputGuidance.stringValue : "")
        recorder.setAccessibilityHelp(announcement)
        NSAccessibility.post(element: errorLabel, notification: .announcementRequested,
                             userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func clearError() {
        errorLabel.stringValue = ""
        feedback.isHidden = true
        inputGuidance.isHidden = true
        recorder.setAccessibilityHelp("클릭한 뒤 원하는 단축키를 누르세요. Esc를 누르면 입력을 취소합니다.")
        updateControls()
    }

    private func updateControls() {
        let isEnabled = enabled.state == .on
        recorder.isEnabled = isEnabled
        shortcutLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        helpLabel.stringValue = isEnabled ? "클릭한 뒤 사용할 단축키를 누르세요." : "메뉴의 ‘표 변환하기’는 계속 사용할 수 있습니다."
        helpLabel.isHidden = recorder.isRecording
        saveButton.isEnabled = !recorder.isRecording && feedback.isHidden && pendingPreferences != savedPreferences
        resizeToFit()
    }

    private func resizeToFit() {
        guard let window else { return }
        // Size to visible rows rather than leaving space for a hidden error row.
        window.contentView?.layoutSubtreeIfNeeded()
        let rows = content.arrangedSubviews.filter { !$0.isHidden }
        let height = rows.reduce(CGFloat(40)) { $0 + $1.fittingSize.height }
            + CGFloat(max(0, rows.count - 1)) * content.spacing
        let old = window.frame
        let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 440, height: ceil(height)))
        window.setFrame(NSRect(x: old.minX, y: old.maxY - frame.height, width: frame.width, height: frame.height), display: true)
    }
}
