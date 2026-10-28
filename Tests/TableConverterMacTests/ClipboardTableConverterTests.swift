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
        XCTAssertEqual(pasteboard.string(forType: .init("com.phronesis.pyororong.converted-table")), "1")
        XCTAssertNil(pasteboard.string(forType: .init("com.phronesis.tableconverter.converted-table")))
    }

    @MainActor
    func testLegacyConvertedClipboardRemainsReadyWithoutRewritingIt() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("<table><tr><td>기존 변환 결과</td></tr></table>", forType: .html)
        item.setString("1", forType: .init("com.phronesis.tableconverter.converted-table"))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let revision = pasteboard.changeCount
        let converter = ClipboardTableConverter(pasteboard: pasteboard)

        XCTAssertTrue(converter.isReadyToPaste)
        await assertClipboardState(converter, .readyToPaste)
        XCTAssertEqual(pasteboard.changeCount, revision)
        XCTAssertNil(pasteboard.string(forType: .init("com.phronesis.pyororong.converted-table")))
    }

    @MainActor
    func testLegacyMarkerWithoutATableDoesNotReportACompletedConversion() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("1", forType: .init("com.phronesis.tableconverter.converted-table"))
        let converter = ClipboardTableConverter(pasteboard: pasteboard)

        XCTAssertFalse(converter.isReadyToPaste)
        await assertClipboardState(converter, .idle)
    }

    @MainActor
    func testPublicHTMLIsSupported() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<table style='mso-test:yes'><tr><td>공통 HTML</td></tr></table>", forType: .html)
        XCTAssertEqual(try ClipboardTableConverter(pasteboard: pasteboard).convert().plainText, "공통 HTML")
    }

    @MainActor
    func testNativeHighlighterDataIsReadAlongsideHTMLAndWrittenAsPasteableColors() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TableConverterCoreTests/Fixtures")
        let item = NSPasteboardItem()
        item.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.html")),
                     forType: .init("com.hancom.office.XHTML032Format"))
        item.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.cfb")),
                     forType: .init("com.hancom.office.Hwp032Native"))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let originalCount = pasteboard.changeCount
        await assertClipboardState(converter, .readyToConvert)
        XCTAssertEqual(pasteboard.changeCount, originalCount)
        let result = try converter.convert()
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertTrue(result.html.contains("background-color: rgb(101, 255, 101);"))
        XCTAssertTrue(result.html.contains("background-color: rgb(255, 178, 255);"))
        XCTAssertEqual(pasteboard.string(forType: .html), result.html)
        XCTAssertEqual(pasteboard.string(forType: .string), result.plainText)
        await assertClipboardState(converter, .readyToPaste)
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
    func testClipboardStateTracksConversionAndNewClipboardContents() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        await assertClipboardState(converter, .idle)

        let sourceType = NSPasteboard.PasteboardType("com.hancom.office.XHTML032Format")
        let html = "<table style='mso-test:yes'><tr><td>상태 전환</td></tr></table>"
        pasteboard.setString(html, forType: sourceType)
        let originalChangeCount = pasteboard.changeCount
        await assertClipboardState(converter, .readyToConvert)
        await assertClipboardState(converter, .readyToConvert)
        XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
        XCTAssertEqual(pasteboard.string(forType: sourceType), html)

        let result = try converter.convert()
        await assertClipboardState(converter, .readyToPaste)
        await assertClipboardState(converter, .readyToPaste)
        XCTAssertEqual(pasteboard.string(forType: .html), result.html)

        pasteboard.clearContents()
        pasteboard.setString("다른 내용", forType: .string)
        await assertClipboardState(converter, .idle)

        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        await assertClipboardState(converter, .readyToConvert)

        pasteboard.clearContents()
        pasteboard.setString("<table><tr><td>일반 웹 표</td></tr></table>", forType: .html)
        await assertClipboardState(converter, .idle)
    }

    @MainActor
    func testConvertedClipboardIsRecognizedAfterRecreatingConverter() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<table style='mso-test:yes'><tr><td>다시 실행</td></tr></table>", forType: .html)
        _ = try ClipboardTableConverter(pasteboard: pasteboard).convert()

        let changeCount = pasteboard.changeCount
        await assertClipboardState(ClipboardTableConverter(pasteboard: pasteboard), .readyToPaste)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }

    @MainActor
    func testInvalidHangulTableIsNotReportedAsReadyToConvert() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let html = "<table style='mso-test:yes'><tr><td style='color:#zzzzzz'>잘못된 색상</td></tr></table>"
        pasteboard.setString(html, forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount

        await assertClipboardState(converter, .idle)
        XCTAssertThrowsError(try converter.convert()) {
            XCTAssertEqual($0 as? ConversionError, .invalidColor("#zzzzzz"))
        }
        await assertClipboardState(converter, .conversionFailed)
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
    }

    @MainActor
    func testFailurePersistsUntilClipboardChangesAndRetryCanSucceed() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("원래 텍스트", forType: .string)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let count = pasteboard.changeCount
        await assertClipboardState(converter, .idle)
        XCTAssertThrowsError(try converter.convert())
        await assertClipboardState(converter, .conversionFailed)
        await assertClipboardState(converter, .conversionFailed)
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .string), "원래 텍스트")
        await assertClipboardState(ClipboardTableConverter(pasteboard: pasteboard), .idle)

        // Adding a format can keep the same change count; the type change also clears the error.
        pasteboard.setString("<table style='mso-test:yes'><tr><td>재시도</td></tr></table>", forType: .html)
        await assertClipboardState(converter, .readyToConvert)
        _ = try converter.convert()
        await assertClipboardState(converter, .readyToPaste)
    }

    @MainActor
    func testAsyncFailureShowsErrorAndNewCopyClearsIt() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let html = "<table style='mso-test:yes'><tr><td style='color:#zzzzzz'>실패</td></tr></table>"
        pasteboard.setString(html, forType: .html)
        let count = pasteboard.changeCount
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        do {
            _ = try await converter.convertAsync()
            XCTFail("Invalid color must fail")
        } catch {
            XCTAssertEqual(error as? ConversionError, .invalidColor("#zzzzzz"))
        }
        await assertClipboardState(converter, .conversionFailed)
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        pasteboard.clearContents()
        pasteboard.setString("<table style='mso-test:yes'><tr><td>새 표</td></tr></table>", forType: .html)
        await assertClipboardState(converter, .readyToConvert)
        _ = try await converter.convertAsync()
        await assertClipboardState(converter, .readyToPaste)
    }

    @MainActor
    func testUnmarkedConvertedHTMLIsNotReportedAsOurConversion() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("<table style='mso-test:yes'><tr><td>변환 표</td></tr></table>", forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let result = try converter.convert()
        await assertClipboardState(converter, .readyToPaste)

        pasteboard.clearContents()
        pasteboard.setString(result.html, forType: .html)
        await assertClipboardState(converter, .idle)
    }

    @MainActor
    func testAsyncConversionPreservesNativeHighlightsAndWritesPasteableResult() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TableConverterCoreTests/Fixtures")
        let item = NSPasteboardItem()
        item.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.html")),
                     forType: .init("com.hancom.office.XHTML032Format"))
        item.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.cfb")),
                     forType: .init("com.hancom.office.Hwp032Native"))
        XCTAssertTrue(pasteboard.writeObjects([item]))
        let converter = ClipboardTableConverter(pasteboard: pasteboard)

        let result = try await converter.convertAsync()

        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertTrue(result.html.contains("background-color: rgb(101, 255, 101);"))
        XCTAssertTrue(result.html.contains("background-color: rgb(255, 178, 255);"))
        XCTAssertEqual(pasteboard.string(forType: .html), result.html)
        XCTAssertEqual(pasteboard.string(forType: .string), result.plainText)
        await assertClipboardState(converter, .readyToPaste)
    }

    @MainActor
    func testAsyncConversionLetsMainQueueRunAndDoesNotOverwriteNewClipboard() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let rows = String(repeating: "<tr><td>긴 표 변환 중</td><td>새 복사 내용 유지</td></tr>", count: 500)
        pasteboard.setString("<table style='mso-test:yes'>\(rows)</table>", forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let copiedDuringConversion = expectation(description: "Main queue remains responsive")
        // This runs once convertAsync suspends for its background calculation.
        DispatchQueue.main.async {
            pasteboard.clearContents()
            pasteboard.setString("변환 중 새로 복사한 내용", forType: .string)
            copiedDuringConversion.fulfill()
        }

        do {
            _ = try await converter.convertAsync()
            XCTFail("A changed clipboard must not be overwritten")
        } catch {
            XCTAssertEqual(error as? ConversionError, .clipboardChanged)
        }
        await fulfillment(of: [copiedDuringConversion], timeout: 2)
        XCTAssertEqual(pasteboard.string(forType: .string), "변환 중 새로 복사한 내용")
        XCTAssertNil(pasteboard.string(forType: .html))
        await assertClipboardState(converter, .idle)
    }

    @MainActor
    func testCancelledAsyncConversionDoesNotWriteClipboard() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let html = "<table style='mso-test:yes'><tr><td>취소 시 원본 유지</td></tr></table>"
        pasteboard.setString(html, forType: .html)
        let originalCount = pasteboard.changeCount
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        let task = Task { @MainActor in try await converter.convertAsync() }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled conversion must not write a result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(pasteboard.changeCount, originalCount)
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        await assertClipboardState(converter, .readyToConvert)
    }

    @MainActor
    func testStateValidationLetsMainQueueRunAndConversionReusesPreparedHTML() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let rows = String(repeating: "<tr><td>백그라운드 검사</td><td>계산 재사용</td></tr>", count: 500)
        pasteboard.setString("<table style='mso-test:yes'>\(rows)</table>", forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        var mainQueueRan = false
        DispatchQueue.main.async { mainQueueRan = true }

        await assertClipboardState(converter, .readyToConvert)
        XCTAssertTrue(mainQueueRan)
        let prepared = try await converter.prepareConversion()
        let result = try await converter.convertAsync()
        // Fresh conversions generate different UUIDs, so exact HTML proves reuse.
        XCTAssertEqual(result.html, prepared.html)
        XCTAssertEqual(pasteboard.string(forType: .html), prepared.html)
    }

    @MainActor
    func testNewCopyDuringStateValidationDoesNotLeaveAStalePreparedResult() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let rows = String(repeating: "<tr><td>이전 표</td></tr>", count: 500)
        pasteboard.setString("<table style='mso-test:yes'>\(rows)</table>", forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        DispatchQueue.main.async {
            pasteboard.clearContents()
            pasteboard.setString("새 복사 내용", forType: .string)
        }
        await assertClipboardState(converter, .idle)
        XCTAssertEqual(pasteboard.string(forType: .string), "새 복사 내용")

        pasteboard.clearContents()
        pasteboard.setString("<table style='mso-test:yes'><tr><td>새 표</td></tr></table>", forType: .html)
        await assertClipboardState(converter, .readyToConvert)
        let result = try await converter.convertAsync()
        XCTAssertEqual(result.plainText, "새 표")
    }

    @MainActor
    func testAddingNativeFormatInvalidatesPreparedHTML() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TableConverterCoreTests/Fixtures")
        pasteboard.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.html")), forType: .html)
        let converter = ClipboardTableConverter(pasteboard: pasteboard)
        await assertClipboardState(converter, .readyToConvert)
        let revision = pasteboard.changeCount
        pasteboard.setData(try Data(contentsOf: fixtures.appendingPathComponent("native-highlight-anonymized.cfb")),
                           forType: .init("com.hancom.office.Hwp032Native"))
        XCTAssertEqual(pasteboard.changeCount, revision)

        let result = try await converter.convertAsync()
        XCTAssertTrue(result.html.contains("background-color: rgb(101, 255, 101);"))
        XCTAssertFalse(result.hasUnrestoredHighlights)
    }

    @MainActor
    private func assertClipboardState(_ converter: ClipboardTableConverter, _ expected: ClipboardTableState,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        let state = await converter.clipboardState()
        XCTAssertEqual(state, expected, file: file, line: line)
    }

    @MainActor
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("com.phronesis.pyororong.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }
}
