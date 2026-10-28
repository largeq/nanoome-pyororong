import AppKit
import TableConverterMac

/// A local, self-contained demonstration: it never reads the clipboard or controls other apps.
@MainActor
final class UsageGuideIllustration: NSView {
    var onStepChanged: ((Int) -> Void)?
    var shortcut: ConversionShortcut? { didSet { needsDisplay = true } }
    private var timer: Timer?
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var elapsed: TimeInterval = 0
    private var playing = false
    private(set) var selectedStep = 0
    var isPlaying: Bool { timer != nil }
    private let scene = NSView()
    private let statusCard = NSView()
    private let statusLabel = GuideText.label("기본 상태", size: 14, weight: .bold)
    private let actionLabel = GuideText.label("한글에서 표 또는 문서를 복사하세요.", size: 11, color: .secondaryLabelColor)
    private var accessibilitySummary = ""
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityChildren([])
        let labels = NSStackView(views: [statusLabel, actionLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 8
        labels.setHuggingPriority(.required, for: .vertical)
        labels.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(labels)
        let content = NSStackView(views: [scene, statusCard])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            scene.widthAnchor.constraint(equalTo: content.widthAnchor),
            scene.heightAnchor.constraint(equalToConstant: 166),
            statusCard.widthAnchor.constraint(equalTo: content.widthAnchor),
            statusCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            labels.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 104),
            labels.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -12),
            labels.topAnchor.constraint(greaterThanOrEqualTo: statusCard.topAnchor, constant: 8),
            statusCard.bottomAnchor.constraint(greaterThanOrEqualTo: labels.bottomAnchor, constant: 8),
            labels.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            statusLabel.widthAnchor.constraint(equalTo: labels.widthAnchor),
            actionLabel.widthAnchor.constraint(equalTo: labels.widthAnchor)
        ])
        updateAccessibility()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) { updateTimer() }

    func setPlaying(_ playing: Bool) {
        guard self.playing != playing else { return }
        self.playing = playing
        updateTimer()
    }

    func selectStep(_ step: Int) {
        guard (0...2).contains(step) else { return }
        elapsed = [0.0, 6.0, 11.2][step]
        startedAt = ProcessInfo.processInfo.systemUptime
        tick()
    }

    private var currentTime: TimeInterval {
        let advance = timer == nil ? 0 : ProcessInfo.processInfo.systemUptime - startedAt
        return (elapsed + advance).truncatingRemainder(dividingBy: 16)
    }

    private func updateTimer() {
        if timer != nil { elapsed = currentTime }
        timer?.invalidate()
        timer = nil
        guard playing, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            tick()
            return
        }
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 24, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 1 / 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        let time = currentTime
        let step = time < 6 ? 0 : time < 10 ? 1 : 2
        if step != selectedStep {
            selectedStep = step
            onStepChanged?(step)
        }
        updateAccessibility()
        updateCaptions()
        needsDisplay = true
    }

    private func updateAccessibility() {
        let descriptions = ["한글에서 표 또는 문서 전체를 복사하기(⌘C)하면 표 아이콘에 원 표시가 나타납니다.",
                            "메뉴바의 표 아이콘에서 표 변환하기를 선택합니다.",
                            "체크 표시가 나타나면 네이버 카페·블로그에 붙여넣기(⌘V)합니다."]
        let summary = "사용법 시연, \(selectedStep + 1)/3단계, \(isPlaying ? "재생 중" : "일시정지"). " + descriptions[selectedStep]
        guard summary != accessibilitySummary else { return }
        accessibilitySummary = summary
        setAccessibilityLabel(summary)
    }

    private func updateCaptions() {
        let time = currentTime
        let copied = time >= 3
        let converted = time >= 10
        let converting = time >= 8 && time < 10
        let status = converted ? "붙여넣기 준비" : converting ? "변환 중" : copied ? "변환 대기" : "기본 상태"
        let action = converted ? "체크 표시: ⌘V로 붙여넣으세요." : converting ? "표의 선이 움직이는 동안 기다려 주세요." : copied ? "‘표 변환하기’를 눌러주세요." : "한글에서 표 또는 문서를 복사하세요."
        for (label, text) in [(statusLabel, status), (actionLabel, action)] where label.stringValue != text {
            label.stringValue = text
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let time = currentTime
        let copied = time >= 3
        let converted = time >= 10
        let converting = time >= 8 && time < 10
        let conversionPhase = converting ? min((time - 8) / 2, 0.38) : nil
        let state: ClipboardTableState = converted ? .readyToPaste : copied ? .readyToConvert : .idle
        let sceneRect = scene.convert(scene.bounds, to: self)
        let background = NSBezierPath(roundedRect: sceneRect, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        GuideDrawing.wallpaper(in: sceneRect)
        GuideDrawing.menuBar(width: bounds.width, state: state, converting: conversionPhase)

        if selectedStep == 1 {
            drawMenu(converting: converting)
        } else {
            let pasted = converted && time >= 11.2
            let document = NSRect(x: 24, y: 46, width: bounds.width - 48, height: 112)
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: document, xRadius: 7, yRadius: 7).fill()
            GuideDrawing.text(converted ? "네이버 카페·블로그 · 글쓰기" : "한글 · 예제 문서",
                              in: NSRect(x: 36, y: 55, width: 350, height: 18), size: 11, weight: .medium, color: .secondaryLabelColor)
            if !converted || pasted {
                GuideDrawing.table(in: NSRect(x: 36, y: 80, width: bounds.width - 72, height: 65),
                                   selected: copied && !converted)
            } else {
                GuideDrawing.text("이곳에 붙여넣기(⌘V)", in: NSRect(x: 36, y: 98, width: 350, height: 24),
                                  size: 13, color: .tertiaryLabelColor)
            }
            let key = converted ? "⌘V" : "⌘C"
            let keyOpacity: CGFloat = converted ? (pasted ? 1 : 0.4) : (copied ? 1 : 0.4)
            NSColor.controlAccentColor.withAlphaComponent(0.12 * keyOpacity).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 82, y: 51, width: 42, height: 24), xRadius: 5, yRadius: 5).fill()
            GuideDrawing.text(key, in: NSRect(x: bounds.width - 82, y: 54, width: 42, height: 18),
                              size: 13, weight: .semibold, color: .controlAccentColor, alignment: .center)
        }

        NSGraphicsContext.restoreGraphicsState()
        let enlarged = statusCard.convert(statusCard.bounds, to: self)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: enlarged, xRadius: 9, yRadius: 9).fill()
        (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? NSColor.labelColor : .separatorColor).setStroke()
        NSBezierPath(roundedRect: enlarged.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
        GuideDrawing.icon(state, in: NSRect(x: enlarged.minX + 12, y: enlarged.midY - 27.5, width: 80, height: 55),
                          converting: conversionPhase)
    }

    private func drawMenu(converting: Bool) {
        let frame = NSRect(x: bounds.width - 256, y: 36, width: 228, height: 100)
        NSColor.textBackgroundColor.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        GuideDrawing.text(converting ? "표를 변환하고 있습니다…" : "변환할 표가 있습니다",
                          in: NSRect(x: frame.minX + 14, y: frame.minY + 8, width: 200, height: 16),
                          size: 11, color: .secondaryLabelColor)
        NSColor.separatorColor.setFill()
        NSRect(x: frame.minX + 12, y: frame.minY + 27, width: 204, height: 1).fill()
        if !converting {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.minX + 6, y: frame.minY + 32, width: 216, height: 24), xRadius: 4, yRadius: 4).fill()
        }
        let actionColor: NSColor = converting ? .secondaryLabelColor : .white
        GuideDrawing.text(converting ? "변환 중…" : "표 변환하기",
                          in: NSRect(x: frame.minX + 14, y: frame.minY + 36, width: 130, height: 18), size: 12, color: actionColor)
        if !converting, let shortcut {
            GuideDrawing.text(shortcut.displayName, in: NSRect(x: frame.maxX - 84, y: frame.minY + 36, width: 68, height: 18),
                              size: 12, color: actionColor, alignment: .right)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: frame.minX + 12, y: frame.minY + 64, width: 204, height: 1).fill()
        GuideDrawing.text("단축키 설정…", in: NSRect(x: frame.minX + 14, y: frame.minY + 74, width: 200, height: 18), size: 12)
    }
}

@MainActor
enum GuideDrawing {
    private static var tintedImages: [String: NSImage] = [:]

    static func text(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                        .foregroundColor: color, .paragraphStyle: paragraph])
    }

    static func wallpaper(in rect: NSRect) {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let start = dark ? NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.23, alpha: 1)
                         : NSColor(calibratedRed: 0.72, green: 0.70, blue: 0.67, alpha: 1)
        let end = dark ? NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.46, alpha: 1)
                       : NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.83, alpha: 1)
        NSGradient(starting: start, ending: end)?.draw(in: rect, angle: 35)
    }

    static func menuBar(width: CGFloat, state: ClipboardTableState, converting: Double? = nil) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSRect(x: 0, y: 0, width: width, height: 34).fill()
        icon(state, in: NSRect(x: width - 278, y: 6, width: 32, height: 22), color: .white, converting: converting)
        for (name, x) in [("wifi", width - 228), ("magnifyingglass", width - 194), ("switch.2", width - 162)] {
            if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                tinted(symbol, key: name, size: NSSize(width: 16, height: 16), color: .white)
                    .draw(in: NSRect(x: x, y: 9, width: 16, height: 16), from: .zero, operation: .sourceOver,
                          fraction: 0.95, respectFlipped: true, hints: nil)
            }
        }
        text("오후 2:30", in: NSRect(x: width - 128, y: 10, width: 110, height: 18),
             size: 12, weight: .medium, color: .white, alignment: .right)
    }

    static func icon(_ state: ClipboardTableState, in rect: NSRect, color: NSColor = .labelColor, converting: Double? = nil) {
        if let converting {
            MenuBarIconRenderer.drawConversion(phase: converting, in: rect, color: color)
            return
        }
        let name: String
        switch state {
        case .idle: name = "table-idle"
        case .readyToConvert: name = "table-convert-ready"
        case .readyToPaste: name = "table-paste-ready"
        case .conversionFailed: name = "table-error"
        }
        let enlarged = rect.width > 40 ? NSImage(named: name + "-master") : nil
        guard let source = enlarged ?? NSImage(named: name)
            ?? NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil) else { return }
        tinted(source, key: name, size: rect.size, color: color)
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func tinted(_ source: NSImage, key: String, size: NSSize, color: NSColor) -> NSImage {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        let cacheKey = "\(key)-\(size)-\(resolved)"
        if let cached = tintedImages[cacheKey] { return cached }
        // Tint an isolated image; source-in must not recolor the surrounding illustration.
        let image = NSImage(size: size)
        image.lockFocus()
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let imageSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let imageRect = NSRect(x: (size.width - imageSize.width) / 2, y: (size.height - imageSize.height) / 2,
                               width: imageSize.width, height: imageSize.height)
        source.draw(in: imageRect)
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        image.unlockFocus()
        tintedImages[cacheKey] = image
        return image
    }

    static func table(in rect: NSRect, selected: Bool) {
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        rect.fill()
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath(rect: rect)
        for index in 1..<3 {
            let x = rect.minX + rect.width * CGFloat(index) / 3
            let y = rect.minY + rect.height * CGFloat(index) / 3
            grid.move(to: NSPoint(x: x, y: rect.minY)); grid.line(to: NSPoint(x: x, y: rect.maxY))
            grid.move(to: NSPoint(x: rect.minX, y: y)); grid.line(to: NSPoint(x: rect.maxX, y: y))
        }
        grid.lineWidth = 1
        grid.stroke()
        for (row, values) in [["항목", "내용", "수량"], ["노트", "예제", "2"], ["펜", "예제", "3"]].enumerated() {
            for (column, value) in values.enumerated() {
                text(value, in: NSRect(x: rect.minX + CGFloat(column) * rect.width / 3 + 10,
                                      y: rect.minY + CGFloat(row) * rect.height / 3 + 5,
                                      width: rect.width / 3 - 20, height: 16), size: 10, weight: row == 0 ? .semibold : .regular)
            }
        }
    }
}
