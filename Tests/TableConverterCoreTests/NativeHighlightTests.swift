import Foundation
import SwiftSoup
import XCTest
@testable import TableConverterCore

final class NativeHighlightTests: XCTestCase {
    private let green: UInt32 = 0x65ff65
    private let pink: UInt32 = 0xffb2ff

    func testAnonymizedRealClipboardRestoresGreenPinkAndYellowWithoutChangingTextOrCells() throws {
        let html = try fixtureHTML()
        let native = try fixtureData()
        let paragraphs = try HwpHighlightReader.read(native)
        let highlights = paragraphs.flatMap(\.highlights)
        XCTAssertEqual(paragraphs.count, 146)
        XCTAssertEqual(highlights.filter { $0.color == green }.count, 6)
        XCTAssertEqual(highlights.filter { $0.color == pink }.count, 1)
        XCTAssertEqual(highlights.filter { $0.color == 0x00ffff }.count, 14)
        let converter = HangulTableConverter()
        let before = try converter.convert(html)
        let after = try converter.convert(html, nativeHwpData: native)
        XCTAssertFalse(after.hasUnrestoredHighlights)
        XCTAssertEqual(after.plainText, before.plainText)
        let doc = try SwiftSoup.parseHTML(after.html)
        XCTAssertEqual(try doc.select("table").size(), 1)
        XCTAssertEqual(try doc.select("td").size(), 118)
        XCTAssertEqual(try coloredText(doc, "rgb(101, 255, 101)").utf16.count, 28)
        XCTAssertEqual(try coloredText(doc, "rgb(255, 178, 255)").utf16.count, 2)
        XCTAssertEqual(try coloredText(doc, "rgb(255, 255, 0)").utf16.count, 101)
    }

    func testCompressedMiniStreamsAndUncompressedRegularStreamsProduceSameFormatting() throws {
        let converter = HangulTableConverter()
        let html = try fixtureHTML()
        let compressed = try converter.convert(html, nativeHwpData: fixtureData())
        let regular = try converter.convert(html, nativeHwpData: fixtureData("native-highlight-anonymized-uncompressed"))
        XCTAssertFalse(regular.hasUnrestoredHighlights)
        XCTAssertEqual(compressed.plainText, regular.plainText)
        let spans: (String) throws -> [String] = { html in
            try SwiftSoup.parseHTML(html).select("span").array().map { try $0.attr("style") + "|" + $0.html() }
        }
        XCTAssertEqual(try spans(compressed.html), try spans(regular.html))
    }

    func testNativeOffsetsCountEightUnitControlsAndUTF16SurrogatePairs() throws {
        let units: [UInt16] = [2, 0, 0, 0, 0, 0, 0, 2] + Array("가😀나".utf16) + [13]
        let data = nativeDocument(units: units, ranges: [(9, 11, green)])
        let paragraphs = try HwpHighlightReader.read(data)
        XCTAssertEqual(String(decoding: paragraphs[0].text, as: UTF16.self), "가😀나")
        XCTAssertEqual(paragraphs[0].highlights.first?.start, 1)
        XCTAssertEqual(paragraphs[0].highlights.first?.end, 3)
        let result = try HangulTableConverter().convert(table("가😀나"), nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(101, 255, 101)"), "😀")
    }

    func testExtendedRecordLengthsAreReadWithoutTruncatingText() throws {
        let text = String(repeating: "가", count: 2200)
        let data = nativeDocument(units: Array(text.utf16) + [13], ranges: [(2198, 2200, pink)])
        let result = try HangulTableConverter().convert(table(text), nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertEqual(result.plainText, text)
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 178, 255)"), "가가")
    }

    func testWholeDocumentMatchesRepeatedTextByPositionAcrossMultipleTables() throws {
        let html = "<p>앞</p>" + table("반복") + "<p>사이</p>" + table("<b>반</b><u>복</u>") + "<p>뒤</p>"
        let doc = try SwiftSoup.parseHTML(html)
        let paragraphs = [paragraph("앞"), paragraph("반복"), paragraph("사이"),
                          paragraph("반복", [(0, 2, pink)]), paragraph("뒤")]
        XCTAssertTrue(try HwpHighlightOverlay.restore(paragraphs, in: XCTUnwrap(doc.body())))
        let result = try HangulTableConverter().convert(doc.outerHtml())
        let output = try SwiftSoup.parseHTML(result.html)
        let tables = try output.select("table").array()
        XCTAssertEqual(tables.count, 2)
        XCTAssertEqual(try coloredText(tables[0], "rgb(255, 178, 255)"), "")
        XCTAssertEqual(try coloredText(tables[1], "rgb(255, 178, 255)"), "반복")
        XCTAssertEqual(try output.select("b").text(), "반")
        XCTAssertEqual(try output.select("u").text(), "복")
        XCTAssertEqual(result.plainText, "앞반복사이반복뒤")
    }

    func testPartialHighlightAcrossNestedFormattingAndNestedTables() throws {
        let html = "<table style='mso-test:yes'><tr><td><p>앞</p><table><tr><td><p><b>가나</b><strike>다라</strike>마</p></td></tr></table><p>뒤</p></td></tr></table>"
        let doc = try SwiftSoup.parseHTML(html)
        XCTAssertTrue(try HwpHighlightOverlay.restore([paragraph("앞"), paragraph("가나다라마", [(1, 4, green)]), paragraph("뒤")], in: XCTUnwrap(doc.body())))
        let result = try HangulTableConverter().convert(doc.outerHtml())
        let output = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try coloredText(output, "rgb(101, 255, 101)"), "나다라")
        XCTAssertEqual(result.plainText, "앞가나다라마뒤")
        XCTAssertEqual(try output.select("table").size(), 1)
        XCTAssertEqual(try output.select("strike").text(), "다라")
    }

    func testHighlightToleratesHTMLSpacingWithoutLeakingAcrossSeparateRanges() throws {
        let doc = try SwiftSoup.parseHTML(table("<b>가</b>&nbsp;<i>나</i> 다"))
        XCTAssertTrue(try HwpHighlightOverlay.restore([paragraph("가 나 다", [(0, 3, green), (4, 5, green)])], in: XCTUnwrap(doc.body())))
        let result = try HangulTableConverter().convert(doc.outerHtml())
        let output = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try coloredText(output, "rgb(101, 255, 101)"), "가\u{a0}나다")
        XCTAssertEqual(result.plainText, "가\u{a0}나 다")
    }

    func testOverlappingNativeRangesUseTheLastColorAndOverrideCharacterShading() throws {
        let html = table("<span style='background:#ffff00'>가나다라</span>마")
        let data = nativeDocument(units: Array("가나다라마\r".utf16), ranges: [(0, 4, green), (1, 3, pink)])
        let result = try HangulTableConverter().convert(html, nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        let doc = try SwiftSoup.parseHTML(result.html)
        XCTAssertEqual(try coloredText(doc, "rgb(101, 255, 101)"), "가라")
        XCTAssertEqual(try coloredText(doc, "rgb(255, 178, 255)"), "나다")
        XCTAssertEqual(result.plainText, "가나다라마")
    }

    func testDifferentSourceTextDoesNotColorAConvenientRepeatedPhrase() throws {
        let html = table("다른 글반복반복")
        let data = nativeDocument(units: Array("반복반복\r".utf16), ranges: [(2, 4, pink)])
        let result = try HangulTableConverter().convert(html, nativeHwpData: data)
        XCTAssertTrue(result.hasUnrestoredHighlights)
        XCTAssertEqual(result.plainText, "다른 글반복반복")
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 178, 255)"), "")
    }

    func testTruncatedCyclicAndOutOfBoundsNativeDataFallsBackToOriginalHTML() throws {
        let valid = try fixtureData()
        var cycle = Array(valid)
        let fatOffset = (Int(try cycle.hwpUInt32(76)) + 1) * 512
        let directory = try cycle.hwpUInt32(48)
        put(directory, into: &cycle, at: fatOffset + Int(directory) * 4)
        let outOfRange = nativeDocument(units: Array("가\r".utf16), ranges: [(0, 99, green)])
        for data in [Data(), Data(valid.prefix(512)), Data(cycle), outOfRange] {
            let result = try HangulTableConverter().convert(table("보존"), nativeHwpData: data)
            XCTAssertTrue(result.hasUnrestoredHighlights)
            XCTAssertEqual(result.plainText, "보존")
        }
    }

    func testInvalidCompressedStreamAndMiniFatCycleAreRejected() throws {
        var invalid = Array(try fixtureData())
        let miniFatSector = Int(try invalid.hwpUInt32(60))
        // The FileHeader occupies mini sectors 0...3. Section0 starts at mini sector 4.
        put(UInt32(4), into: &invalid, at: (miniFatSector + 1) * 512 + 4 * 4)
        XCTAssertThrowsError(try HwpHighlightReader.read(Data(invalid)))
        var compressed = nativeDocument(units: Array("가\r".utf16), ranges: [(0, 1, green)])
        compressed[(2 + 1) * 512 + 36] = 1 // Mark the uncompressed section as compressed.
        XCTAssertThrowsError(try HwpHighlightReader.read(compressed))
    }

    func testNoNativeFormattingKeepsExistingHTMLConversionUsable() throws {
        let data = nativeDocument(units: Array("다른 표현\r".utf16), ranges: [])
        let result = try HangulTableConverter().convert(table("<span style='background:#ffff00'>노랑</span>"), nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 255, 0)"), "노랑")
    }

    func testSplitSurrogateRangeDoesNotMutateHTML() throws {
        let doc = try SwiftSoup.parseHTML(table("😀"))
        let before = try doc.outerHtml()
        XCTAssertFalse(try HwpHighlightOverlay.restore([paragraph("😀", [(0, 1, green)])], in: XCTUnwrap(doc.body())))
        XCTAssertEqual(try doc.outerHtml(), before)
    }

    func testHighlightOnOnlyAnInternalSpaceIsPreserved() throws {
        let data = nativeDocument(units: Array("가 나\r".utf16), ranges: [(1, 2, pink)])
        let result = try HangulTableConverter().convert(table("<b>가</b> <i>나</i>"), nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertEqual(result.plainText, "가 나")
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 178, 255)"), " ")
    }

    func testMultipleInlineTablesAreInterleavedWithParentTextInScreenOrder() throws {
        let object: [UInt16] = [11, 0x6c20, 0x7462, 0, 0, 0, 0, 11] // "tbl " control marker.
        let units = Array("앞".utf16) + object + Array("중".utf16) + object + Array("뒤\r".utf16)
        let data = nativeDocument(units: units, ranges: [(18, 19, pink)], tableChildren: [["첫 표"], ["둘째 표"]])
        let html = "<p>앞</p>" + table("첫 표") + "<p>중</p>" + table("둘째 표") + "<p>뒤</p>"
        let result = try HangulTableConverter().convert(html, nativeHwpData: data)
        XCTAssertFalse(result.hasUnrestoredHighlights)
        XCTAssertEqual(result.plainText, "앞첫 표중둘째 표뒤")
        XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 178, 255)"), "뒤")
    }

    func testGraphicCaptionIsOptionalOnlyWhenTheRemainingWholeTextMatches() throws {
        let object: [UInt16] = [11, 0x6f20, 0x6773, 0, 0, 0, 0, 11] // "gso "
        let units = Array("앞".utf16) + object + Array("뒤\r".utf16)
        let data = nativeDocument(units: units, ranges: [(9, 10, pink)], graphicChildren: ["설명"])
        for text in ["앞뒤", "앞설명뒤"] {
            let result = try HangulTableConverter().convert(table(text), nativeHwpData: data)
            XCTAssertFalse(result.hasUnrestoredHighlights)
            XCTAssertEqual(result.plainText, text)
            XCTAssertEqual(try coloredText(SwiftSoup.parseHTML(result.html), "rgb(255, 178, 255)"), "뒤")
        }
        let mismatch = try HangulTableConverter().convert(table("앞다른뒤"), nativeHwpData: data)
        XCTAssertTrue(mismatch.hasUnrestoredHighlights)
    }

    private func fixtureData(_ name: String = "native-highlight-anonymized") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "cfb", subdirectory: "Fixtures")))
    }

    private func fixtureHTML() throws -> String {
        try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "native-highlight-anonymized", withExtension: "html", subdirectory: "Fixtures")), encoding: .utf8)
    }

    private func coloredText(_ element: Element, _ color: String) throws -> String {
        try element.select("span").array().filter { try $0.attr("style").contains("background-color: \(color);") }
            .map { textContent(of: $0) }.joined()
    }

    private func table(_ text: String) -> String { "<table style='mso-test:yes'><tr><td><p>\(text)</p></td></tr></table>" }
    private func paragraph(_ text: String, _ ranges: [(Int, Int, UInt32)] = []) -> HwpNativeParagraph {
        HwpNativeParagraph(text: Array(text.utf16), highlights: ranges.map { HwpTextHighlight(start: $0.0, end: $0.1, color: $0.2) })
    }

    /// Minimal regular-sector CFB fixture. Real anonymous fixtures also exercise MiniFAT and raw DEFLATE.
    private func nativeDocument(units: [UInt16], ranges: [(Int, Int, UInt32)], tableChildren: [[String]] = [], graphicChildren: [String] = []) -> Data {
        func record(_ tag: UInt32, _ level: UInt32, _ payload: [UInt8]) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: payload.count >= 4095 ? 8 : 4)
            put(tag | level << 10 | UInt32(min(payload.count, 4095)) << 20, into: &data, at: 0)
            if payload.count >= 4095 { put(UInt32(payload.count), into: &data, at: 4) }
            return data + payload
        }
        var rangeBytes: [UInt8] = []
        for range in ranges {
            var data = [UInt8](repeating: 0, count: 12)
            put(UInt32(range.0), into: &data, at: 0)
            put(UInt32(range.1), into: &data, at: 4)
            put(0x02000000 | range.2, into: &data, at: 8)
            rangeBytes += data
        }
        var section = record(66, 0, [UInt8](repeating: 0, count: 22))
        section += record(67, 1, units.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
        section += record(70, 1, rangeBytes)
        for children in tableChildren {
            section += record(71, 1, [0x20, 0x6c, 0x62, 0x74])
            for child in children {
                section += record(66, 2, [UInt8](repeating: 0, count: 22))
                section += record(67, 3, Array((child + "\r").utf16).flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
            }
        }
        if !graphicChildren.isEmpty {
            section += record(71, 1, [0x20, 0x6f, 0x73, 0x67])
            for child in graphicChildren {
                section += record(66, 2, [UInt8](repeating: 0, count: 22))
                section += record(67, 3, Array((child + "\r").utf16).flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
            }
        }
        let sectionSize = max(4096, ((section.count + 4 + 511) / 512) * 512)
        section += record(0, 0, [UInt8](repeating: 0, count: sectionSize - section.count - 4))
        let sectorCount = 10 + section.count / 512
        var file = [UInt8](repeating: 0, count: (sectorCount + 1) * 512)
        file.replaceSubrange(0..<8, with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
        for (offset, value) in [(24, UInt32(0x0003003e)), (28, 0x0009fffe), (32, 6), (44, 1), (48, 1), (56, 4096), (60, 0xfffffffe), (68, 0xfffffffe)] {
            put(value, into: &file, at: offset)
        }
        for offset in stride(from: 76, to: 512, by: 4) { put(0xffffffff, into: &file, at: offset) }
        put(0, into: &file, at: 76)
        for id in 0..<128 {
            let next: UInt32 = id >= sectorCount ? 0xffffffff : id == 0 ? 0xfffffffd : [1, 9, sectorCount - 1].contains(id) ? 0xfffffffe : UInt32(id + 1)
            put(next, into: &file, at: 512 + id * 4)
        }
        func entry(_ id: Int, _ name: String, _ type: UInt8, child: UInt32 = 0xffffffff,
                   right: UInt32 = 0xffffffff, start: UInt32 = 0xfffffffe, size: UInt32 = 0) {
            let offset = 1024 + id * 128
            let text = Array((name + "\0").utf16).flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }
            file.replaceSubrange(offset..<offset + text.count, with: text)
            file[offset + 64] = UInt8(text.count); file[offset + 66] = type; file[offset + 67] = 1
            for (index, value) in [(68, UInt32(0xffffffff)), (72, right), (76, child), (116, start), (120, size)] {
                put(value, into: &file, at: offset + index)
            }
        }
        entry(0, "Root Entry", 5, child: 1)
        entry(1, "FileHeader", 2, right: 2, start: 2, size: 4096)
        entry(2, "BodyText", 1, child: 3)
        entry(3, "Section0", 2, start: 10, size: UInt32(section.count))
        let signature = Array("HWP Document File".utf8)
        file.replaceSubrange(1536..<1536 + signature.count, with: signature)
        file[1536 + 35] = 5
        file.replaceSubrange(5632..<5632 + section.count, with: section)
        return Data(file)
    }

    private func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<4 { bytes[offset + index] = UInt8((value >> (index * 8)) & 255) }
    }
}
