import AppKit
import XCTest
@testable import TableConverterMac

final class MenuBarIconAnimatorTests: XCTestCase {
    @MainActor
    func testConversionFramesKeepOutlineAndEqualCellHeights() throws {
        let renderer = MenuBarIconRenderer()
        let empty = try bitmap(renderer.conversion(phase: 0))
        let full = try bitmap(renderer.conversion(phase: 0.38))
        XCTAssertEqual(empty.pixelsWide, 48)
        XCTAssertEqual(full.pixelsHigh, 44)
        // The outer left edge must remain visible while the internal lines change.
        for phase in stride(from: 0.0, to: 1.0, by: 0.05) {
            let image = renderer.conversion(phase: phase)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 24, height: 22))
            let frame = try bitmap(image)
            XCTAssertGreaterThan(alpha(frame, x: 7, y: 22), 0.9)
        }
        XCTAssertNotEqual(alphaValues(empty), alphaValues(full))

        // Count the clear runs between the two horizontal rules and the outline.
        let rows = (11..<33).map { alpha(full, x: 14, y: $0) < 0.5 }
        var heights: [Int] = []
        var length = 0
        for clear in rows + [false] {
            if clear { length += 1 }
            else if length > 0 { heights.append(length); length = 0 }
        }
        XCTAssertEqual(heights.count, 3)
        XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1)
    }

    @MainActor
    func testFinishingPreservesTheVisibleLinesAndFillsWithoutErasing() throws {
        let renderer = MenuBarIconRenderer()
        let full = alphaValues(try bitmap(renderer.conversion(phase: 0.38)))
        for phase in [0.0, 0.1, 0.38, 0.49, 0.75, 0.98] {
            let original = alphaValues(try bitmap(renderer.conversion(phase: phase)))
            let start = alphaValues(try bitmap(renderer.conversion(phase: phase, finishingProgress: 0)))
            XCTAssertEqual(start, original, "Finishing must begin from the visible frame")
            var previous = start
            for progress in [0.25, 0.5, 0.75, 1.0] {
                let image = renderer.conversion(phase: phase, finishingProgress: progress)
                XCTAssertTrue(image.isTemplate)
                let pixels = alphaValues(try bitmap(image))
                for index in pixels.indices {
                    XCTAssertGreaterThanOrEqual(pixels[index] + 0.01, previous[index],
                                               "Visible rules must fill in, never disappear")
                }
                previous = pixels
            }
            XCTAssertEqual(previous, full, "Every phase must finish as the same complete table")
        }
    }

    @MainActor
    func testCompletionRevealsStandaloneCheckWithoutThePendingCircle() throws {
        let renderer = try assetRenderer()
        let start = try bitmap(renderer.completion(progress: 0))
        let middle = try bitmap(renderer.completion(progress: 0.5))
        let finish = try bitmap(renderer.completion(progress: 1))
        XCTAssertLessThan(alphaValues(start).reduce(0, +), alphaValues(middle).reduce(0, +))
        XCTAssertLessThan(alphaValues(middle).reduce(0, +), alphaValues(finish).reduce(0, +))
        XCTAssertLessThan(alpha(start, x: 40, y: 30), 0.05)
        XCTAssertGreaterThan(alpha(try bitmap(renderer.image(for: .readyToConvert)), x: 40, y: 30), 0.9)
        for y in 0..<44 {
            for x in 0..<48 where x < 27 || y < 18 || y >= 39 {
                XCTAssertEqual(alpha(start, x: x, y: y), alpha(middle, x: x, y: y), accuracy: 0.01)
                XCTAssertEqual(alpha(start, x: x, y: y), alpha(finish, x: x, y: y), accuracy: 0.01)
            }
        }
        XCTAssertTrue(renderer.completion(progress: 0.5).isTemplate)
        XCTAssertTrue(renderer.completion(progress: 1) === renderer.image(for: .readyToPaste))
    }

    @MainActor
    func testAllFourStatesUseCenteredTemplateAssetsAtTheirIntendedSize() throws {
        let renderer = try assetRenderer()
        var pixels: [[CGFloat]] = []
        for state in [ClipboardTableState.idle, .readyToConvert, .readyToPaste, .conversionFailed] {
            let image = renderer.image(for: state)
            XCTAssertEqual(image.size, NSSize(width: 24, height: 22))
            XCTAssertTrue(image.isTemplate)
            let frame = try bitmap(image)
            XCTAssertEqual(frame.pixelsWide, 48)
            XCTAssertEqual(frame.pixelsHigh, 44)
            pixels.append(alphaValues(frame))
        }
        for i in pixels.indices { for j in pixels.indices where i != j { XCTAssertNotEqual(pixels[i], pixels[j]) } }

        let idle = try bitmap(renderer.image(for: .idle))
        let columns = (0..<48).filter { x in (0..<44).contains { alpha(idle, x: x, y: $0) > 0.5 } }
        let rows = (0..<44).filter { y in (0..<48).contains { alpha(idle, x: $0, y: y) > 0.5 } }
        XCTAssertEqual(Double(try XCTUnwrap(columns.first) + XCTUnwrap(columns.last) + 1) / 2, 24, accuracy: 0.5)
        XCTAssertEqual(Double(try XCTUnwrap(rows.first) + XCTUnwrap(rows.last) + 1) / 2, 22, accuracy: 0.5)
        // Allow for antialiasing at both edges against the 34px reference icon.
        XCTAssertEqual(Double(rows.count) / 34, 0.8, accuracy: 2.0 / 34)
        XCTAssertEqual(Double(columns.count) / Double(rows.count), 295.0 / 231, accuracy: 0.05)
    }

    @MainActor
    func testGuideUsesTheSameConversionDrawingWithoutStretchingTheTable() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 110,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        MenuBarIconRenderer.drawConversion(phase: 0.38,
            in: NSRect(x: 0, y: 0, width: 160, height: 110), color: .black)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let columns = (0..<160).filter { x in (0..<110).contains { alpha(bitmap, x: x, y: $0) > 0.5 } }
        let rows = (0..<110).filter { y in (0..<160).contains { alpha(bitmap, x: $0, y: y) > 0.5 } }
        XCTAssertEqual(Double(columns.count) / Double(rows.count), 295.0 / 231, accuracy: 0.05)
        XCTAssertEqual(Double(try XCTUnwrap(columns.first) + XCTUnwrap(columns.last) + 1) / 2, 80, accuracy: 0.5)
        XCTAssertEqual(Double(try XCTUnwrap(rows.first) + XCTUnwrap(rows.last) + 1) / 2, 55, accuracy: 0.5)
    }

    @MainActor
    private func assetRenderer() throws -> MenuBarIconRenderer {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Assets/MenuBarIcons")
        func load(_ name: String) throws -> NSImage {
            try XCTUnwrap(NSImage(contentsOf: folder.appendingPathComponent(name + "@2x.png")))
        }
        return try MenuBarIconRenderer(idle: load("table-idle"), ready: load("table-convert-ready"),
                                       completed: load("table-paste-ready"), failed: load("table-error"),
                                       completionBase: load("table-paste-ready-base"), checkmark: load("table-paste-ready-mark"))
    }

    @MainActor
    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide })
    }

    @MainActor
    private func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    @MainActor
    private func alphaValues(_ bitmap: NSBitmapImageRep) -> [CGFloat] {
        (0..<bitmap.pixelsHigh).flatMap { y in (0..<bitmap.pixelsWide).map { x in alpha(bitmap, x: x, y: y) } }
    }
}
