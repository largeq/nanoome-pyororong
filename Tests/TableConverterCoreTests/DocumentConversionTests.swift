import Foundation
import SwiftSoup
import XCTest
@testable import TableConverterCore

final class DocumentConversionTests: XCTestCase {
    private let converter = HangulTableConverter()

    func testWholeAnonymizedClipboardRetainsAllTextAndMatchesWindowsNestedGrid() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "full-document-anonymized", withExtension: "html", subdirectory: "Fixtures"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let before = try SwiftSoup.parseHTML(source)
        let result = try converter.convert(source)
        let after = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try before.select("table").size(), 11)
        XCTAssertEqual(try after.select("table").size(), 10)
        XCTAssertEqual(try after.select("table table").size(), 0)
        XCTAssertEqual(visible(result.plainText), visible(textContent(of: try XCTUnwrap(before.body()))))
        let tables = try after.select("table").array()
        XCTAssertEqual(try tables.map { try $0.select("tr").size() }, [23, 6, 14, 17, 23, 7, 1, 5, 21, 8])
        XCTAssertEqual(try tables.map { try $0.select("td,th").size() }, [59, 48, 50, 41, 118, 67, 1, 15, 63, 68])
        let rows = try tables[0].select("tr").array()
        XCTAssertEqual(try rows[10].select("td").first()?.attr("rowspan"), "10")
        XCTAssertEqual(try rows[11].select("td").array().map { try $0.attr("colspan") }, ["5", "5", "5"])
        for table in tables { try assertRectangularGrid(table) }
        let ids = try after.select("[id]").array().map { try $0.attr("id") }
        XCTAssertEqual(ids.count, Set(ids).count)
        // These counts come from the anonymized input, not the shorter original text.
        let highlightCounts = ["rgb(255, 255, 0)": 154, "rgb(250, 243, 219)": 217,
                               "rgb(255, 231, 216)": 623, "rgb(255, 255, 10)": 77]
        for (color, count) in highlightCounts {
            let spans = try after.select("span").array().filter {
                try $0.attr("style").contains("background-color: \(color);")
            }
            XCTAssertEqual(spans.map { visible(textContent(of: $0)).count }.reduce(0, +), count, color)
        }
    }

    func testBodyBeforeBetweenAndAfterTablesRetainsOrderAndLinks() throws {
        let html = """
        <body><p style='font-size:10pt'>앞 <b>강조</b></p><div>
        <table style='mso-test:yes'><tr><td>첫 표</td></tr></table>
        중간 <a href='https://example.com'>연결</a>
        <table><tr><td>둘째 표</td></tr></table><p>뒤<br>끝</p></div></body>
        """
        let result = try converter.convert(html)
        XCTAssertEqual(visible(result.plainText), "앞강조첫표중간연결둘째표뒤끝")
        let doc = try SwiftSoup.parseHTML(result.html)
        let components = try doc.select(".se-component").array()
        XCTAssertEqual(components.count, 5)
        XCTAssertEqual(try doc.select("a[href]").first()?.attr("href"), "https://example.com")
        XCTAssertEqual(try doc.select("br").size(), 1)
    }

    func testNestedTableSplitsParentContentAndExpandsSurroundingMerges() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td>제목</td><td colspan='5'>요약</td></tr>
        <tr><td>항목</td><td colspan='5' style='height:200pt;border:2px solid black'>
        <p>앞</p><table><tr><td>가</td><td>나</td><td>다</td></tr>
        <tr><td>라</td><td>마</td><td>바</td></tr></table><p>뒤</p></td></tr>
        <tr><td>마침</td><td colspan='5'>끝</td></tr></table>
        """)
        XCTAssertEqual(result.plainText, "제목요약항목앞가나다라마바뒤마침끝")
        let doc = try SwiftSoup.parseHTML(result.html)
        let rows = try doc.select("tr").array()
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(try rows[0].select("td").array()[1].attr("colspan"), "15")
        XCTAssertEqual(try rows[1].select("td").array()[0].attr("rowspan"), "4")
        let fragment = try rows[1].select("td").array()[1]
        XCTAssertFalse(try fragment.attr("style").contains("height:"))
        XCTAssertTrue(try fragment.attr("style").contains("border: none"))
        try assertRectangularGrid(try XCTUnwrap(doc.select("table").first()))
    }

    func testParallelNestedTablesUseCompatibleRowsWithoutDuplicates() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td><table><tr><td>A</td></tr><tr><td>B</td></tr></table></td>
        <td><table><tr><td>C</td><td>D</td></tr><tr><td>E</td><td>F</td></tr><tr><td>G</td><td>H</td></tr></table></td></tr></table>
        """)
        XCTAssertEqual(result.plainText.sorted(), "ABCDEFGH".sorted())
        let doc = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try doc.select("table").size(), 1)
        XCTAssertEqual(try doc.select("tr").size(), 6)
        try assertRectangularGrid(try XCTUnwrap(doc.select("table").first()))
    }

    func testRowspanningParentWithInnerTablePreservesSiblingCells() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td rowspan='2'><table><tr><td>A</td></tr><tr><td>B</td></tr><tr><td>C</td></tr></table></td><td>D</td></tr><tr><td>E</td></tr></table>
        """)
        XCTAssertEqual(result.plainText.sorted(), "ABCDE".sorted())
        try assertRectangularGrid(try XCTUnwrap(SwiftSoup.parseHTML(result.html).select("table").first()))
    }

    func testMultipleAndDeepInnerTablesKeepTextExactlyOnce() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td><p>앞</p><table><tr><td>중<table><tr><td>심</td></tr></table>간</td></tr></table>
        <p>사이</p><table><tr><td>다음</td></tr></table><p>끝</p></td></tr></table>
        """)
        XCTAssertEqual(result.plainText, "앞중심간사이다음끝")
        let doc = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try doc.select("table").size(), 1)
        try assertRectangularGrid(try XCTUnwrap(doc.select("table").first()))
    }

    func testTextOutsideParagraphsInsideCellsIsNotDiscarded() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td>앞<p>중간</p>뒤</td></tr></table>")
        XCTAssertEqual(result.plainText, "앞중간뒤")
        XCTAssertEqual(try SwiftSoup.parseHTML(result.html).select("p").size(), 3)
    }

    func testAlignmentIsExplicitAndInheritsCellAlignment() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes;text-align:right'><tr><td><p>오른쪽</p><p style='text-align:center'>가운데</p></td><td style='text-align:left'>왼쪽</td></tr></table>
        """)
        let paragraphs = try SwiftSoup.parseHTML(result.html).select("p").array()
        for (p, alignment) in zip(paragraphs, ["right", "center", "left"]) {
            XCTAssertTrue(try p.attr("style").contains("text-align: \(alignment)"))
        }
    }

    func testBackgroundSurvivesMalformedHancomDiagonalDeclaration() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td style='mso-diagonal-down:0.00pt solid #000000 background:#e3f4e3;'><p>배경</p></td></tr></table>
        """)
        XCTAssertTrue(result.hasDiagonal)
        let cell = try XCTUnwrap(SwiftSoup.parseHTML(result.html).select("td").first())
        XCTAssertTrue(try cell.attr("style").contains("background-color: rgb(227, 244, 227)"))
        XCTAssertFalse(try cell.attr("style").contains("mso-diagonal"))
    }

    func testStrikeUnderlineAndItalicArePreservedTogether() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td><u><s><i>겹친 서식</i></s></u><span style='text-decoration:line-through'>취소선</span></td></tr></table>
        """)
        let doc = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try doc.select("u strike i").text(), "겹친 서식")
        XCTAssertEqual(try doc.select("strike").size(), 2)
        XCTAssertEqual(result.plainText, "겹친 서식취소선")
    }

    func testTextHighlightKeepsNestedFormattingAndDoesNotLeakFromCellOrToAdjacentText() throws {
        let result = try converter.convert("""
        <style>.highlight {background:#ffff00}</style>
        <table style='mso-test:yes'><tr><td style='background:#e3f4e3'><p>일반<span class='highlight'>
        <b>강조</b><span style='background:transparent'>이어서</span>
        <span style='background-color:#ffe7d8'><u>다른색</u></span></span>끝</p></td></tr></table>
        """)
        let doc = try SwiftSoup.parseHTML(result.html)
        let spans = try doc.select("span").array()
        XCTAssertEqual(spans.map { textContent(of: $0) }, ["일반", "강조", "이어서", "다른색", "끝"])
        let colors = try spans.map { try converter.convertedStyles($0.attr("style"))["background-color"] }
        XCTAssertEqual(colors, [nil, "rgb(255, 255, 0)", "rgb(255, 255, 0)", "rgb(255, 231, 216)", nil])
        XCTAssertEqual(try doc.select("b").text(), "강조")
        XCTAssertEqual(try doc.select("u").text(), "다른색")
        XCTAssertTrue(try doc.select("td").attr("style").contains("background-color: rgb(227, 244, 227)"))
    }

    func testRGBAndNamedHighlightColorsAreRetained() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td><span style='background:rgb(250, 243, 219)'>베이지</span>
        <span style='background-color:yellow'>노랑</span></td></tr></table>
        """)
        let spans = try SwiftSoup.parseHTML(result.html).select("span").array()
        XCTAssertTrue(try spans[0].attr("style").contains("background-color: rgb(250, 243, 219)"))
        XCTAssertTrue(try spans[1].attr("style").contains("background-color: yellow"))
    }

    func testFontClassesUseWindowsReferenceSizesWithoutDiscardingOriginalSize() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes;font-family:나눔바른고딕'><tr><td><p style='font-size:10pt'>보통</p><p style='font-size:8pt'>작게</p></td></tr></table>
        """)
        let spans = try SwiftSoup.parseHTML(result.html).select("span").array()
        XCTAssertTrue(spans[0].hasClass("se-fs-fs13"))
        XCTAssertTrue(spans[1].hasClass("se-fs-fs11"))
        XCTAssertTrue(spans[0].hasClass("se-ff-nanumbarungothic"))
        XCTAssertTrue(try spans[0].attr("style").contains("13.3333px"))
    }

    func testHancomCommentWrappedStyleSheetWithNumericClassProvidesDefaultFontSize() throws {
        let result = try converter.convert("""
        <style><!--
        p.0,li.0,div.0 {font-size:10pt;text-align:justify}
        --></style><table style='mso-test:yes'><tr><td><p class='0'><span style='font-family:나눔바른고딕'>기본 크기</span></p></td></tr></table>
        """)
        let span = try XCTUnwrap(SwiftSoup.parseHTML(result.html).select("span").first())
        XCTAssertTrue(try span.attr("style").contains("font-size: 13.3333px"))
    }

    func testUnsafeLinkBecomesTextAndExcessiveGridDoesNotReturnPartialOutput() throws {
        let result = try converter.convert("<table style='mso-test:yes'><tr><td><a href='javascript:alert(1)'>내용</a></td></tr></table>")
        XCTAssertEqual(result.plainText, "내용")
        XCTAssertEqual(try SwiftSoup.parseHTML(result.html).select("a").size(), 0)
        XCTAssertThrowsError(try converter.convert("<table style='mso-test:yes'><tr><td colspan='100000'>원본</td></tr></table>")) {
            XCTAssertEqual($0 as? ConversionError, .layoutTooComplex)
        }
    }

    func testWebImagesRemainAndUnavailableLocalImagesAreReported() throws {
        let result = try converter.convert("""
        <table style='mso-test:yes'><tr><td><p>앞<img src='https://example.com/picture.png' alt='그림'></p>
        <p><img src='file:///tmp/local.png'>뒤</p><img src='data:image/png;base64,AAAA'></td></tr></table>
        """)
        let doc = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try doc.select("img").size(), 1)
        XCTAssertEqual(try doc.select("img").first()?.attr("src"), "https://example.com/picture.png")
        XCTAssertEqual(result.unconvertedImageCount, 2)
        XCTAssertEqual(result.plainText, "앞뒤")
    }

    private func visible(_ text: String) -> String {
        text.filter { !$0.isWhitespace && $0 != "\u{200b}" && $0 != "\u{feff}" }
    }

    private func assertRectangularGrid(_ table: Element, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try table.select("tr").array()
        var occupied: [Set<Int>] = Array(repeating: [], count: rows.count)
        for (r, row) in rows.enumerated() {
            var column = 0
            for cell in try row.select("td,th") {
                while occupied[r].contains(column) { column += 1 }
                let width = Int(try cell.attr("colspan")) ?? 1
                let height = Int(try cell.attr("rowspan")) ?? 1
                XCTAssertLessThanOrEqual(r + height, rows.count, file: file, line: line)
                for y in r..<min(r + height, rows.count) {
                    for x in column..<column + width {
                        XCTAssertTrue(occupied[y].insert(x).inserted, "Overlapping cells", file: file, line: line)
                    }
                }
                column += width
            }
        }
        let width = occupied.map(\.count).max() ?? 0
        for row in occupied { XCTAssertEqual(row, Set(0..<width), "Grid contains holes", file: file, line: line) }
    }
}
