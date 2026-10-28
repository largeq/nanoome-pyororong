import XCTest
@testable import TableConverterMac

final class MenuBarAnimationTimingTests: XCTestCase {
    func testFastConversionWaitsForCompletedDrawing() {
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 0.01), 0.8, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 0.5), 0.8, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 0.7), 0.8, accuracy: 0.001)
    }

    func testAlreadyCompleteTableCanTransitionBeforeErasing() {
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 0.85), 0.85, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 2.9), 2.9, accuracy: 0.001)
    }

    func testErasingAndEmptyFramesWaitForNextCompleteTable() {
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 1.1), 2.8, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 1.95), 2.8, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 2.05), 2.8, accuracy: 0.001)
        XCTAssertEqual(MenuBarAnimationTiming.completedTableTime(after: 5.99), 6.8, accuracy: 0.001)
    }
}
