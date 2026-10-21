import Foundation
import SwiftSoup
import XCTest
@testable import TableConverterCore

final class HangulTableConverterTests: XCTestCase {
    private let converter = HangulTableConverter()

    func testRealClipboardFixturesMatchPythonReference() throws {
        let referenceURL = try XCTUnwrap(Bundle.module.url(forResource: "python-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: referenceURL))
        XCTAssertEqual(reference.fixtures.count, 5)
        XCTAssertEqual(reference.sourceSHA256, "9ce2b03dfa14138d30d0cca4a79844e2676ac355cb44a6cb67f7fb5da0115e26")
        for expected in reference.fixtures {
            let url = try XCTUnwrap(Bundle.module.url(forResource: expected.name, withExtension: nil, subdirectory: "Fixtures"))
            let result = try converter.convert(String(contentsOf: url, encoding: .utf8))
            XCTAssertEqual(result.hasDiagonal, expected.hasDiagonal, expected.name)
            XCTAssertEqual(result.plainText, expected.plainText, expected.name)
            let actualRows = try snapshot(result.html)
            XCTAssertEqual(actualRows.count, expected.rows.count, expected.name)
            for (rowIndex, pair) in zip(actualRows, expected.rows).enumerated() {
                XCTAssertEqual(pair.0.count, pair.1.count, "\(expected.name), row \(rowIndex)")
                for (cellIndex, cells) in zip(pair.0, pair.1).enumerated() {
                    XCTAssertEqual(cells.0, cells.1, "\(expected.name), row \(rowIndex), cell \(cellIndex)")
                }
            }
            XCTAssertFalse(result.html.contains("mso-diagonal"), expected.name)
        }
    }

    func testSpecialCharactersRemainText() throws {
        let html = "<table style='mso-test:yes'><tr><td><p><span>A &lt; B &amp; C &gt; D &quot;한글&quot; 😀 &lt;img src=x&gt;</span></p></td></tr></table>"
        let result = try converter.convert(html)
        XCTAssertEqual(result.plainText, "A < B & C > D \"한글\" 😀 <img src=x>")
        XCTAssertTrue(try SwiftSoup.parseHTML(result.html).getElementsByTag("img").isEmpty())
        XCTAssertTrue(result.html.contains("&lt;img"))
    }

    func testParagraphWhitespaceIsPreserved() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><p><span>A  B&nbsp;C</span></p><p><span>다음 줄</span></p></td></tr></table>")
        XCTAssertEqual(result.plainText, "A  B\u{00a0}C다음 줄")
        let rows = try snapshot(result.html)
        XCTAssertEqual(rows[0][0].paragraphs.count, 2)
        XCTAssertEqual(rows[0][0].paragraphs[0].spans[0].text, "A  B\u{00a0}C")
    }

    func testDirectCellTextAndHeadersUseLegacyFallback() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><th style='text-align:right'> 제목 </th><td> 앞 <b> 뒤 </b></td></tr></table>")
        let rows = try snapshot(result.html)
        XCTAssertEqual(rows[0][0].paragraphs[0].alignment, "right")
        XCTAssertEqual(rows[0][0].paragraphs[0].spans[0].text, "제목")
        XCTAssertEqual(rows[0][1].paragraphs[0].spans[0].text, "앞뒤")
        XCTAssertFalse(rows[0][1].paragraphs[0].spans[0].bold)
    }

    func testOnlyFirstTableIsConverted() throws {
        let result = try converter.convert("<div>본문</div><table style='mso-test:yes'><tr><td>첫째</td></tr></table><table><tr><td>둘째</td></tr></table>")
        XCTAssertEqual(result.plainText, "첫째")
        XCTAssertEqual(try SwiftSoup.parseHTML(result.html).getElementsByTag("table").size(), 1)
    }

    func testMissingTableAndForeignHTMLAreRejected() {
        XCTAssertThrowsError(try converter.convert("<table><tr><td>다른 앱</td></tr></table>")) {
            XCTAssertEqual($0 as? ConversionError, .notHangulTable)
        }
        XCTAssertThrowsError(try converter.convert("<p style='mso-test:yes'>표 없음</p>")) {
            XCTAssertEqual($0 as? ConversionError, .tableNotFound)
        }
    }

    func testOfficeHTMLWithXMLDeclarationCanBeRead() throws {
        let result = try converter.convert("<?xml version='1.0'?><html xmlns:w='urn:schemas-microsoft-com:office:word'><body><table style='mso-test:yes'><tr><td><p><span>한글</span></p></td></tr></table></body></html>")
        XCTAssertEqual(result.plainText, "한글")
    }

    func testGeneratedIdentifiersAreUnique() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><p><span>가</span><span>나</span></p></td><td>다</td></tr></table>")
        let ids = try SwiftSoup.parseHTML(result.html).select("[id]").array().map { try $0.attr("id") }
        XCTAssertGreaterThan(ids.count, 5)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertTrue(id.hasPrefix("SE-"))
            XCTAssertNotNil(UUID(uuidString: String(id.dropFirst(3))))
        }
    }

    private func snapshot(_ html: String) throws -> [[CellSnapshot]] {
        let table = try XCTUnwrap(SwiftSoup.parseHTML(html).getElementsByTag("table").first())
        return try table.getElementsByTag("tr").array().map { row in
            try row.getElementsByTag("td").array().map { cell in
                let paragraphs = try cell.getElementsByTag("p").array().map { paragraph in
                    let classNames = try paragraph.attr("class").split(separator: " ")
                    let alignment = String(try XCTUnwrap(classNames.first { $0.hasPrefix("se-text-paragraph-align-") }).dropFirst("se-text-paragraph-align-".count))
                    let spans = try paragraph.getElementsByTag("span").array().map { span in
                        SpanSnapshot(
                            text: textContent(of: span),
                            color: try rawStyles(span.attr("style"))["color"] ?? "",
                            bold: try !span.getElementsByTag("b").isEmpty(),
                            underline: try !span.getElementsByTag("u").isEmpty()
                        )
                    }
                    return ParagraphSnapshot(alignment: alignment, spans: spans)
                }
                return CellSnapshot(
                    colspan: try cell.attr("colspan"),
                    rowspan: try cell.attr("rowspan"),
                    styles: try rawStyles(cell.attr("style")),
                    paragraphs: paragraphs
                )
            }
        }
    }

    private func rawStyles(_ style: String) -> [String: String] {
        var result: [String: String] = [:]
        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }
}

private struct Reference: Decodable {
    let sourceSHA256: String
    let fixtures: [FixtureSnapshot]
}

private struct FixtureSnapshot: Decodable {
    let name: String
    let hasDiagonal: Bool
    let plainText: String
    let rows: [[CellSnapshot]]
}

private struct CellSnapshot: Decodable, Equatable {
    let colspan: String
    let rowspan: String
    let styles: [String: String]
    let paragraphs: [ParagraphSnapshot]
}

private struct ParagraphSnapshot: Decodable, Equatable {
    let alignment: String
    let spans: [SpanSnapshot]
}

private struct SpanSnapshot: Decodable, Equatable {
    let text: String
    let color: String
    let bold: Bool
    let underline: Bool
}
