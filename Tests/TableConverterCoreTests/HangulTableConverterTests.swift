import Foundation
import SwiftSoup
import XCTest
@testable import TableConverterCore

final class HangulTableConverterTests: XCTestCase {
    private let converter = HangulTableConverter()

    func testRealClipboardFixturesPreservePythonContentAndMerges() throws {
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
                    let location = "\(expected.name), row \(rowIndex), cell \(cellIndex)"
                    XCTAssertEqual(cells.0.colspan, cells.1.colspan, location)
                    XCTAssertEqual(cells.0.rowspan, cells.1.rowspan, location)
                    XCTAssertEqual(cells.0.paragraphs.count, cells.1.paragraphs.count, location)
                    for (actual, legacy) in zip(cells.0.paragraphs, cells.1.paragraphs) {
                        // Python ignored the first comment-wrapped CSS rule.
                        // Naver displays source justification as left alignment;
                        // stylesheet inheritance itself is covered separately.
                        let displayedAlignment = actual.alignment == "justify" ? "left" : actual.alignment
                        XCTAssertEqual(displayedAlignment, legacy.alignment, location)
                        XCTAssertEqual(actual.spans.map(\.text).joined(), legacy.spans.map(\.text).joined(), location)
                        // Text-node boundaries and inherited formatting on blank spans may differ.
                        // Keep comparing the formatting of every visible character.
                        XCTAssertEqual(visibleCharacterFormatting(actual), visibleCharacterFormatting(legacy), location)
                    }
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

    func testNonbreakingSpacesSurviveSourceNewlinesWithoutKeepingIndentation() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><p><span>A</span><span>&nbsp;\n</span><span>B</span></p><p><span>&nbsp;\n</span></p><p>\n  <span>C</span>\n</p></td></tr></table>")
        XCTAssertEqual(result.plainText, "A\u{00a0}\nB\u{00a0}\nC")
        let rows = try snapshot(result.html)
        XCTAssertEqual(rows[0][0].paragraphs.count, 3)
        XCTAssertEqual(rows[0][0].paragraphs[1].spans[0].text, "\u{00a0}\n")
    }

    func testDirectCellTextAndHeadersPreserveSpacesAndBold() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><th style='text-align:right'> 제목 </th><td> 앞 <b> 뒤 </b></td></tr></table>")
        let rows = try snapshot(result.html)
        XCTAssertEqual(rows[0][0].paragraphs[0].alignment, "right")
        XCTAssertEqual(rows[0][0].paragraphs[0].spans[0].text, " 제목 ")
        XCTAssertEqual(rows[0][1].paragraphs[0].spans[0].text, " 앞 ")
        XCTAssertFalse(rows[0][1].paragraphs[0].spans[0].bold)
        XCTAssertEqual(rows[0][1].paragraphs[0].spans[1].text, " 뒤 ")
        XCTAssertTrue(rows[0][1].paragraphs[0].spans[1].bold)
    }

    func testOriginalCellWidthsAndInheritedFontSizesArePreserved() throws {
        let html = """
        <table style='mso-test:yes;font-family:나눔바른고딕;font-size:7pt'>
        <tr><td style='width:30pt'>좁음</td><td style='width:60pt;height:12pt'>중간</td>
        <td style='width:90pt'><span style='font-size:4pt'>넓음</span></td></tr></table>
        """
        let doc = try SwiftSoup.parseHTML(converter.convert(html).html)
        let table = try XCTUnwrap(doc.getElementsByTag("table").first())
        let cells = try table.getElementsByTag("td").array()
        XCTAssertEqual(try rawStyles(cells[0].attr("style"))["width"], "16.6667%")
        XCTAssertEqual(try rawStyles(cells[1].attr("style"))["width"], "33.3333%")
        XCTAssertEqual(try rawStyles(cells[2].attr("style"))["width"], "50%")
        XCTAssertEqual(try rawStyles(cells[1].attr("style"))["height"], "16px")
        XCTAssertEqual(try rawStyles(table.attr("style"))["width"], "100%")
        XCTAssertEqual(try rawStyles(table.attr("style"))["table-layout"], "fixed")
        let spans = try doc.getElementsByTag("span").array()
        XCTAssertEqual(try rawStyles(spans[0].attr("style"))["font-family"], "나눔바른고딕")
        XCTAssertEqual(try rawStyles(spans[0].attr("style"))["font-size"], "9.3333px")
        XCTAssertEqual(try rawStyles(spans[2].attr("style"))["font-size"], "5.3333px")
        XCTAssertFalse(try spans[0].attr("class").contains("se-fs15"))
    }

    func testStyleSheetFontInheritanceAndInlineOverrides() throws {
        let html = """
        <style>p {font-family:함초롬바탕;font-size:10pt} p.small {font-size:7pt} .small {font-size:8pt}</style>
        <table style='mso-test:yes'><tr><td><p class='small'>첫째<span style='font-size:6pt'>둘째</span></p></td></tr></table>
        """
        let doc = try SwiftSoup.parseHTML(converter.convert(html).html)
        let spans = try doc.getElementsByTag("span").array()
        XCTAssertEqual(try rawStyles(spans[0].attr("style"))["font-family"], "함초롬바탕")
        XCTAssertEqual(try rawStyles(spans[0].attr("style"))["font-size"], "9.3333px")
        XCTAssertEqual(try rawStyles(spans[1].attr("style"))["font-size"], "8px")
    }

    func testMixedAndNestedInlineTextIsNeitherLostNorDuplicated() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><p>앞 <span style='font-weight:bold'>강조<span style='font-weight:normal'>보통</span></span> 뒤</p></td></tr></table>")
        XCTAssertEqual(result.plainText, "앞 강조보통 뒤")
        let spans = try snapshot(result.html)[0][0].paragraphs[0].spans
        XCTAssertEqual(spans.map(\.text), ["앞 ", "강조", "보통", " 뒤"])
        XCTAssertEqual(spans.map(\.bold), [false, true, false, false])
    }

    func testExplicitLineBreaksRemainLineBreaks() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><p><span>첫줄<br>둘째줄</span></p></td></tr></table>")
        XCTAssertEqual(result.plainText, "첫줄\n둘째줄")
        XCTAssertEqual(try SwiftSoup.parseHTML(result.html).getElementsByTag("br").size(), 1)
    }

    func testMergedCellsDoNotInflateTableWidth() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td rowspan='2' style='width:30pt'>가</td>
        <td style='width:60pt'>나</td><td style='width:90pt'>다</td></tr>
        <tr><td colspan='2' style='width:150pt'>병합</td></tr></table>
        """)
        let doc = try SwiftSoup.parseHTML(result.html)
        let table = try XCTUnwrap(doc.getElementsByTag("table").first())
        XCTAssertEqual(try rawStyles(table.attr("style"))["width"], "100%")
        let merged = try XCTUnwrap(doc.select("td[colspan=2]").first())
        XCTAssertEqual(try rawStyles(merged.attr("style"))["width"], "83.3333%")
        XCTAssertEqual(result.plainText, "가나다병합")
    }

    func testOriginalLineSpacingPaddingAndBordersAreRetained() throws {
        let result = try converter.convert("""
        <style>p {line-height:120%}</style><table style='mso-test:yes'><tr>
        <td style='width:30pt;padding:1.41pt;border-left:solid #000000 0.28pt'>
        <p style='line-height:100%'>첫째</p><p>둘째</p></td></tr></table>
        """)
        let doc = try SwiftSoup.parseHTML(result.html)
        let paragraphs = try doc.getElementsByTag("p").array()
        XCTAssertEqual(try rawStyles(paragraphs[0].attr("style"))["line-height"], "100%")
        XCTAssertEqual(try rawStyles(paragraphs[1].attr("style"))["line-height"], "120%")
        let cell = try XCTUnwrap(doc.getElementsByTag("td").first())
        XCTAssertEqual(try rawStyles(cell.attr("style"))["padding"], "1.41pt")
        XCTAssertEqual(try rawStyles(cell.attr("style"))["border-left"], "solid #000000 0.28pt")
    }

    func testAllTablesAndBodyAreConverted() throws {
        let result = try converter.convert("<div>본문</div><table style='mso-test:yes'><tr><td>첫째</td></tr></table><table><tr><td>둘째</td></tr></table>")
        XCTAssertEqual(result.plainText, "본문첫째둘째")
        XCTAssertEqual(try SwiftSoup.parseHTML(result.html).getElementsByTag("table").size(), 2)
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

    private func visibleCharacterFormatting(_ paragraph: ParagraphSnapshot) -> [SpanSnapshot] {
        paragraph.spans.flatMap { span in
            span.text.filter { !$0.isWhitespace }.map {
                SpanSnapshot(text: String($0), color: span.color, bold: span.bold, underline: span.underline)
            }
        }
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
