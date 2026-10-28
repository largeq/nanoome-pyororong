import AppKit
import TableConverterCore
import TableConverterMac

@main
struct AppIntegrationChecks {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let clipboardRevision = NSPasteboard.general.changeCount
        let notifier = ConversionNotifier()
        defer { notifier.stop() }
        let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let partial = try HangulTableConverter().convert("""
            <table style="mso-diagonal-up:solid"><tr><td>일부 확인 <img src="file:///example.png"></td></tr></table>
            """)
        var retryCount = 0
        var guideCount = 0
        notifier.onRetry = { retryCount += 1 }
        notifier.onShowUsageGuide = { guideCount += 1 }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            notifier.showAlreadyConverted(clipboardRevision: 1)
            let success = visiblePanel()
            requireText("변환 완료", in: success)
            requireText(ConversionFeedback.pasteInstruction, in: success)
            try snapshot(success, at: output, name: "\(name)-success")

            notifier.showConverted(partial, clipboardRevision: 1)
            let partialPanel = visiblePanel()
            requireText("변환 완료(확인 필요)", in: partialPanel)
            requireText(ConversionFeedback.pasteInstruction + "\n일부 내용은 원본과 다를 수 있습니다.", in: partialPanel)
            let collapsedHeight = partialPanel.frame.height
            click("자세히 보기", in: partialPanel)
            requireText("그림 1개", in: partialPanel)
            requireText("대각선", in: partialPanel)
            try snapshot(partialPanel, at: output, name: "\(name)-partial-details")
            click("간단히 보기", in: partialPanel)
            precondition(abs(partialPanel.frame.height - collapsedHeight) < 1, "Collapsing details must restore the panel height")

            for error in [ConversionError.noHTMLTable, .clipboardWriteFailed, .invalidColor("#zzzzzz"), .layoutTooComplex] {
                notifier.showFailure(error, clipboardRevision: 1)
                let failure = visiblePanel()
                requireText("변환하지 못했습니다", in: failure)
                let action = error == .clipboardWriteFailed ? "다시 변환" : "사용법 보기"
                precondition(button(action, in: failure) != nil, "Failures must offer the matching recovery action")
                try snapshot(failure, at: output, name: "\(name)-failure-\(error == .clipboardWriteFailed ? "retry" : "guide")")
                click(action, in: failure)
                precondition(!failure.isVisible, "Recovery must close the notice before invoking its action")
            }

            let unknown = NSError(domain: "AppIntegrationChecks", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "확인용 상세 오류"])
            notifier.showFailure(unknown, clipboardRevision: 1)
            let unknownPanel = visiblePanel()
            click("자세히 보기", in: unknownPanel)
            requireText("확인용 상세 오류", in: unknownPanel)
            precondition(button("다시 변환", in: unknownPanel) != nil, "Diagnostic details must not hide recovery")

            // Success, partial success, and failure all use the same stale-result presentation.
            let histories: [() -> Void] = [
                { notifier.showAlreadyConverted(clipboardRevision: 2) },
                { notifier.showConverted(partial, clipboardRevision: 2) },
                { notifier.showFailure(ConversionError.noHTMLTable, clipboardRevision: 2) }
            ]
            for history in histories {
                history()
                notifier.showLatestResult(clipboardRevision: 3)
                let stale = visiblePanel()
                requireText("이전 변환 결과", in: stale)
                requireText("복사한 내용이 바뀌었습니다.\n이 결과는 현재 클립보드와 다릅니다.", in: stale)
                precondition(button("사용법 보기", in: stale) == nil && button("다시 변환", in: stale) == nil,
                             "Old results must not offer actions against new clipboard contents")
                click("당시 결과 보기", in: stale)
                precondition(!fields(in: stale).contains { $0.stringValue.contains("⌘V") },
                             "Even expanded history must not instruct pasting the current clipboard")
                try snapshot(stale, at: output, name: "\(name)-previous-result")
                click("간단히 보기", in: stale)
            }
        }
        precondition(retryCount == 2 && guideCount == 6, "Each recovery callback must be invoked once per click")

        notifier.showAlreadyConverted(clipboardRevision: 10)
        let original = visiblePanel()
        notifier.observeClipboardRevision(11)
        precondition(!original.isVisible, "A new copy must close the original notice")

        notifier.showLatestResult(clipboardRevision: 11)
        let reopened = visiblePanel()
        for _ in 0..<3 { notifier.observeClipboardRevision(11) }
        precondition(reopened.isVisible, "Polling the same clipboard must keep reopened results visible")
        notifier.observeClipboardRevision(12)
        precondition(!reopened.isVisible, "Another new copy must close the reopened result")
        precondition(NSPasteboard.general.changeCount == clipboardRevision, "Checks must not change the general clipboard")
        print("App integration checks passed: approved copy, details, recovery actions, stale-result history, light/dark layout, and clipboard preservation.")
    }

    @MainActor
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor
    private static func fields(in panel: NSPanel) -> [NSTextField] {
        descendants(panel.contentView!).compactMap { $0 as? NSTextField }
    }

    @MainActor
    private static func requireText(_ text: String, in panel: NSPanel) {
        precondition(fields(in: panel).contains { $0.stringValue == text }, "Missing panel text: \(text)")
    }

    @MainActor
    private static func button(_ title: String, in panel: NSPanel) -> NSButton? {
        descendants(panel.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }
    }

    @MainActor
    private static func click(_ title: String, in panel: NSPanel) {
        guard let button = button(title, in: panel) else { preconditionFailure("Missing button: \(title)") }
        button.performClick(nil)
    }

    @MainActor
    private static func snapshot(_ panel: NSPanel, at output: URL?, name: String) throws {
        let view = panel.contentView!
        view.layoutSubtreeIfNeeded()
        for field in fields(in: panel) {
            let required = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000))
            precondition(required.height <= field.bounds.height + 1, "Clipped text: \(field.stringValue)")
        }
        guard let output, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    private static func visiblePanel() -> NSPanel {
        guard let panel = NSApplication.shared.windows.compactMap({ $0 as? NSPanel }).first(where: \.isVisible) else {
            preconditionFailure("The result panel must be visible")
        }
        return panel
    }
}
