import AppKit

@MainActor
public final class MenuBarIconAnimator {
    public static var imageSize: NSSize { MenuBarIconRenderer.size }

    private weak var button: NSStatusBarButton?
    private let renderer: MenuBarIconRenderer
    private var timer: Timer?
    private var animation: Animation?
    private var startedAt: TimeInterval = 0
    private var lastFrame: Int?
    private var conversionFrames: [NSImage] = []
    private var completionFrames: [NSImage] = []
    private var finishDrawingAt: TimeInterval?
    private var generation = 0

    private enum Animation { case converting, completed }
    private static let completionDuration: TimeInterval = 0.42

    public init(button: NSStatusBarButton) {
        self.button = button
        renderer = MenuBarIconRenderer()
    }

    public func show(_ state: ClipboardTableState, animateCompletion: Bool = false) {
        stop()
        if state == .readyToPaste, animateCompletion,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if completionFrames.isEmpty {
                completionFrames = (0...15).map { renderer.completion(progress: Double($0) / 15) }
            }
            start(.completed)
        } else {
            button?.image = renderer.image(for: state)
        }
    }

    public func showConverting() {
        stop()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            button?.image = renderer.conversion(phase: 0.38)
            return
        }
        if conversionFrames.isEmpty {
            conversionFrames = (0..<60).map { renderer.conversion(phase: Double($0) / 60) }
        }
        start(.converting)
    }

    /// Complete the visible drawing before handing off to the success check.
    public func finishDrawingTable() async throws {
        guard animation == .converting else { return }
        let token = generation
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let finishAt = MenuBarAnimationTiming.completedTableTime(after: elapsed)
        finishDrawingAt = finishAt
        let remaining = finishAt - elapsed
        if remaining > 0 {
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        holdCompletedTable()
    }

    public func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        animation = nil
        lastFrame = nil
        finishDrawingAt = nil
    }

    private func start(_ animation: Animation) {
        self.animation = animation
        startedAt = ProcessInfo.processInfo.systemUptime
        tick()
        guard self.animation != nil else { return }
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 1 / 240
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let animation else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if animation == .converting {
                holdCompletedTable()
            } else {
                stop()
                button?.image = renderer.image(for: .readyToPaste)
            }
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let frames: [NSImage]
        let index: Int
        switch animation {
        case .converting:
            if let finishDrawingAt, elapsed >= finishDrawingAt {
                holdCompletedTable()
                return
            }
            frames = conversionFrames
            let duration = MenuBarAnimationTiming.conversionDuration
            let phase = elapsed.truncatingRemainder(dividingBy: duration) / duration
            index = min(Int(phase * Double(frames.count)), frames.count - 1)
        case .completed:
            guard elapsed < Self.completionDuration else {
                stop()
                button?.image = renderer.image(for: .readyToPaste)
                return
            }
            frames = completionFrames
            index = min(Int(elapsed / Self.completionDuration * Double(frames.count)), frames.count - 1)
        }
        guard index != lastFrame else { return }
        button?.image = frames[index]
        lastFrame = index
    }

    private func holdCompletedTable() {
        timer?.invalidate()
        timer = nil
        animation = nil
        finishDrawingAt = nil
        lastFrame = nil
        button?.image = renderer.conversion(phase: 0.38)
    }
}

/// Keeps all frames as template images so macOS supplies the menu bar's current tint.
@MainActor
public struct MenuBarIconRenderer {
    private let idle: NSImage
    private let ready: NSImage
    private let completed: NSImage
    private let failed: NSImage
    private let completionBase: NSImage
    private let checkmark: NSImage
    // Trim horizontal padding without scaling the table or its badges.
    static let size = NSSize(width: 24, height: 22)
    // The neighboring icon in the supplied Retina capture is 17pt high; use 80% of that height.
    private static let scale = 13.6 / (231 * 17.0 / 348)
    // Center the table body itself; badges can extend beyond its lower-right corner.
    static let tableBounds = NSRect(x: (size.width - 295 * 13.6 / 231) / 2,
                                    y: (size.height - 13.6) / 2,
                                    width: 295 * 13.6 / 231, height: 13.6)
    private static let checkmarkBounds = NSRect(x: size.width / 2 + 1.5 * scale,
                                                y: size.height / 2 - 6.75 * scale,
                                                width: 8.5 * scale, height: 8.5 * scale)
    static let lineWidth: CGFloat = scale

    init(idle: NSImage? = nil, ready: NSImage? = nil, completed: NSImage? = nil,
         failed: NSImage? = nil, completionBase: NSImage? = nil, checkmark: NSImage? = nil) {
        self.idle = Self.template(idle ?? NSImage(named: "table-idle"), fallback: "tablecells")
        self.ready = Self.template(ready ?? NSImage(named: "table-convert-ready"), fallback: "tablecells")
        self.completed = Self.template(completed ?? NSImage(named: "table-paste-ready"), fallback: "tablecells")
        self.failed = Self.template(failed ?? NSImage(named: "table-error"), fallback: "exclamationmark")
        self.completionBase = Self.template(completionBase ?? NSImage(named: "table-paste-ready-base") ?? idle,
                                            fallback: "tablecells")
        self.checkmark = Self.template(checkmark ?? NSImage(named: "table-paste-ready-mark"), fallback: "checkmark")
    }

    func image(for state: ClipboardTableState) -> NSImage {
        switch state {
        case .idle: idle
        case .readyToConvert: ready
        case .readyToPaste: completed
        case .conversionFailed: failed
        }
    }

    func conversion(phase: Double) -> NSImage {
        Self.rasterize {
            Self.drawConversion(phase: phase, in: NSRect(origin: .zero, size: Self.size), color: .black)
        }
    }

    public static func drawConversion(phase: Double, in rect: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let flipped = NSGraphicsContext.current?.isFlipped == true
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - size.width * scale / 2,
                             yBy: rect.midY + (flipped ? 1 : -1) * size.height * scale / 2)
        transform.scaleX(by: scale, yBy: flipped ? -scale : scale)
        transform.concat()
        color.setFill()
        color.setStroke()
        let stroke = lineWidth
        let outer = tableBounds
        let outline = NSBezierPath(roundedRect: outer.insetBy(dx: stroke / 2, dy: stroke / 2),
                                   xRadius: 1.2 * Self.scale, yRadius: 1.2 * Self.scale)
        outline.lineWidth = stroke
        outline.stroke()
        let inner = outer.insetBy(dx: stroke, dy: stroke)
        let rowHeight = (inner.height - stroke * 2) / 3
        for (delay, y) in [(0.0, inner.maxY - rowHeight - stroke), (0.1, inner.minY + rowHeight)] {
            let segment = segment(at: phase, delay: delay)
            NSRect(x: inner.minX + inner.width * segment.lowerBound, y: y,
                   width: inner.width * (segment.upperBound - segment.lowerBound), height: stroke).fill()
        }
        let segment = segment(at: phase, delay: 0.2)
        NSRect(x: inner.midX - stroke / 2, y: inner.maxY - inner.height * segment.upperBound,
               width: stroke, height: inner.height * (segment.upperBound - segment.lowerBound)).fill()
    }

    func completion(progress: Double) -> NSImage {
        let progress = min(max(progress, 0), 1)
        if progress == 0 { return completionBase }
        if progress == 1 { return completed }
        return Self.rasterize {
            completionBase.draw(in: NSRect(origin: .zero, size: Self.size), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            // Reveal the approved standalone check while preserving its clear gap from the table.
            var reveal = Self.checkmarkBounds
            reveal.size.width *= Self.ease(progress)
            NSBezierPath(rect: reveal).addClip()
            checkmark.draw(in: NSRect(origin: .zero, size: Self.size), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private static func segment(at phase: Double, delay: Double) -> ClosedRange<CGFloat> {
        let local = (phase - delay + 1).truncatingRemainder(dividingBy: 1)
        if local < 0.14 { return 0...CGFloat(ease(local / 0.14)) }
        if local < 0.47 { return 0...1 }
        if local < 0.72 { return CGFloat(ease((local - 0.47) / 0.25))...1 }
        return 0...0
    }

    private static func ease(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }

    private static func template(_ image: NSImage?, fallback: String) -> NSImage {
        let copy = (image?.copy() as? NSImage)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
            ?? NSImage(size: size)
        copy.size = size
        copy.isTemplate = true
        return copy
    }

    private static func rasterize(_ draw: () -> Void) -> NSImage {
        let image = NSImage(size: size)
        for scale in [1, 2] {
            let pixelsWide = Int(size.width) * scale
            let pixelsHigh = Int(size.height) * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            draw()
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        return image
    }
}
