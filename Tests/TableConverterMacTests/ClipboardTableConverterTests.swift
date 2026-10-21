import AppKit
import XCTest
import TableConverterCore
@testable import TableConverterMac

final class ClipboardTableConverterTests: XCTestCase {
    @MainActor
    func testHancomClipboardBecomesHTMLAndPlainTextInOneItem() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let sourceType = NSPasteboard.PasteboardType("com.hancom.office.XHTML032Format")
        pasteboard.setString("<table style='mso-test:yes'><tr><td><p><span>변환 성공</span></p></td></tr></table>", forType: sourceType)
        let result = try ClipboardTableConverter(pasteboard: pasteboard).convert()
        XCTAssertEqual(pasteboard.string(forType: .html), result.html)
        XCTAssertEqual(pasteboard.string(forType: .string), "변환 성공")
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertFalse(pasteboard.types?.contains(sourceType) ?? true)
    }

    @MainActor
    func testPublicHTMLIsSupported() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<table style='mso-test:yes'><tr><td>공통 HTML</td></tr></table>", forType: .html)
        XCTAssertEqual(try ClipboardTableConverter(pasteboard: pasteboard).convert().plainText, "공통 HTML")
    }

    @MainActor
    func testPlainTextClipboardIsNotChangedOnFailure() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("사용자의 원래 텍스트", forType: .string)
        let changeCount = pasteboard.changeCount
        XCTAssertThrowsError(try ClipboardTableConverter(pasteboard: pasteboard).convert()) {
            XCTAssertEqual($0 as? ConversionError, .noHTMLTable)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "사용자의 원래 텍스트")
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }

    @MainActor
    func testForeignTableClipboardIsNotChangedOnFailure() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let html = "<table><tr><td>다른 앱</td></tr></table>"
        pasteboard.setString(html, forType: .html)
        let changeCount = pasteboard.changeCount
        XCTAssertThrowsError(try ClipboardTableConverter(pasteboard: pasteboard).convert()) {
            XCTAssertEqual($0 as? ConversionError, .notHangulTable)
        }
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }

    @MainActor
    func testEmptyClipboardIsHandled() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        XCTAssertThrowsError(try ClipboardTableConverter(pasteboard: pasteboard).convert()) {
            XCTAssertEqual($0 as? ConversionError, .noHTMLTable)
        }
    }

    @MainActor
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("com.phronesis.tableconverter.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }
}
