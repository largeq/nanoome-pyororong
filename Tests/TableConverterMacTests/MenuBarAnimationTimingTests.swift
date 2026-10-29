import AppKit
import XCTest
@testable import TableConverterMac

final class MenuBarAnimationTimingTests: XCTestCase {
    @MainActor
    func testFinishingIsBoundedWhileDrawingErasingOrBetweenCycles() async throws {
        let (item, animator) = try makeAnimator()
        defer { animator.stop(); NSStatusBar.system.removeStatusItem(item) }
        for delay in [0.01, 0.95, 1.1] {
            animator.showConverting()
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let start = ProcessInfo.processInfo.systemUptime
            try await animator.finishDrawingTable()
            let duration = ProcessInfo.processInfo.systemUptime - start
            XCTAssertGreaterThanOrEqual(duration, 0.14)
            XCTAssertLessThan(duration, 0.5, "Finishing must not wait for the next two-second cycle")
        }
    }

    @MainActor
    func testCancellationStopsFinishingFrames() async throws {
        let (item, animator) = try makeAnimator()
        defer { animator.stop(); NSStatusBar.system.removeStatusItem(item) }
        animator.showConverting()
        let finishing = Task { @MainActor in try await animator.finishDrawingTable() }
        try await Task.sleep(nanoseconds: 40_000_000)
        finishing.cancel()
        do {
            try await finishing.value
            XCTFail("Cancelled finishing must throw")
        } catch is CancellationError { }
        let stoppedImage = item.button?.image
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertTrue(item.button?.image === stoppedImage, "Cancelled frames must not keep running")
    }

    @MainActor
    func testOldFinishingCannotOverwriteANewerState() async throws {
        let (item, animator) = try makeAnimator()
        defer { animator.stop(); NSStatusBar.system.removeStatusItem(item) }
        animator.showConverting()
        let finishing = Task { @MainActor in try await animator.finishDrawingTable() }
        try await Task.sleep(nanoseconds: 40_000_000)
        animator.show(.conversionFailed)
        let newerImage = item.button?.image
        do {
            try await finishing.value
            XCTFail("Replaced finishing must throw")
        } catch is CancellationError { }
        XCTAssertTrue(item.button?.image === newerImage)
    }

    @MainActor
    func testFramesContinueDuringMenuTracking() throws {
        let (item, animator) = try makeAnimator()
        defer { animator.stop(); NSStatusBar.system.removeStatusItem(item) }
        animator.showConverting()
        let initialImage = item.button?.image
        let deadline = Date().addingTimeInterval(0.12)
        while Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        XCTAssertFalse(item.button?.image === initialImage, "Menu tracking must not defer animation tasks")
    }

    @MainActor
    private func makeAnimator() throws -> (NSStatusItem, MenuBarIconAnimator) {
        _ = NSApplication.shared
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("Motion is disabled in the system accessibility settings")
        }
        let item = NSStatusBar.system.statusItem(withLength: 0)
        let button = try XCTUnwrap(item.button)
        return (item, MenuBarIconAnimator(button: button))
    }
}
