import Foundation
import zlib

struct HwpTextHighlight {
    let start: Int
    let end: Int
    /// HWP COLORREF: red is in the lowest byte.
    let color: UInt32
}

struct HwpNativeParagraph {
    let text: [UInt16]
    let highlights: [HwpTextHighlight]
    var isAuxiliary = false
}

/// Reads HWP 5 paragraph text and range tags, without importing document layouts or executing content.
/// Hancom file specification, sections 4.3.2 and 4.3.5.
enum HwpHighlightReader {
    private struct Paragraph {
        var text: [UInt16] = []
        var highlights: [HwpTextHighlight] = []
        var anchors: [UInt32: [Int]] = [:]
        var usedAnchors: [UInt32: Int] = [:]
        var children: [Int: [Int]] = [:]
        var isAuxiliary = false
    }

    static func read(_ data: Data) throws -> [HwpNativeParagraph] {
        let file = try HwpCompoundFile(data)
        let header = try file.stream(["FileHeader"])
        guard header.count >= 40, header.starts(with: Array("HWP Document File".utf8)), header[35] == 5 else {
            throw HwpNativeReadError.invalidData
        }
        let flags = try header.hwpUInt32(36)
        guard flags & 6 == 0 else { throw HwpNativeReadError.invalidData } // Password/distribution documents.
        var result: [HwpNativeParagraph] = []
        var totalBytes = 0
        for name in try file.sectionNames() {
            let stored = try file.stream(["BodyText", name])
            let bytes = flags & 1 == 1 ? try inflateSection(stored) : stored
            totalBytes += bytes.count
            guard totalBytes <= HwpCompoundFile.byteLimit else { throw HwpNativeReadError.invalidData }
            result.append(contentsOf: try paragraphs(in: bytes))
        }
        return result
    }

    private static func paragraphs(in bytes: [UInt8]) throws -> [HwpNativeParagraph] {
        var offset = 0
        var paragraphs: [Paragraph] = []
        var ancestors: [(level: Int, index: Int)] = []
        var controls: [(level: Int, owner: Int, offset: Int?, auxiliary: Bool)] = []
        var roots: [Int] = []
        while offset < bytes.count {
            let header = try bytes.hwpUInt32(offset)
            offset += 4
            let tag = Int(header & 0x3ff)
            let level = Int((header >> 10) & 0x3ff)
            var size = Int(header >> 20)
            if size == 0xfff {
                size = Int(try bytes.hwpUInt32(offset))
                offset += 4
            }
            guard size <= bytes.count - offset else { throw HwpNativeReadError.invalidData }
            let end = offset + size
            controls.removeAll { $0.level >= level }
            if tag == 66 { // HWPTAG_PARA_HEADER
                let auxiliary = controls.last?.auxiliary ?? false
                if let control = controls.last {
                    guard let anchor = control.offset else { throw HwpNativeReadError.invalidData }
                    paragraphs[control.owner].children[anchor, default: []].append(paragraphs.count)
                } else { roots.append(paragraphs.count) }
                ancestors.removeAll { $0.level >= level }
                ancestors.append((level, paragraphs.count))
                var paragraph = Paragraph()
                paragraph.isAuxiliary = auxiliary
                paragraphs.append(paragraph)
            } else if tag == 67 || tag == 70 { // PARA_TEXT / PARA_RANGE_TAG
                guard let index = ancestors.last(where: { $0.level == level - 1 })?.index else {
                    throw HwpNativeReadError.invalidData
                }
                if tag == 67 {
                    guard size % 2 == 0 else { throw HwpNativeReadError.invalidData }
                    for position in stride(from: offset, to: end, by: 2) {
                        paragraphs[index].text.append(try bytes.hwpUInt16(position))
                    }
                    paragraphs[index].anchors = try controlAnchors(in: paragraphs[index].text)
                } else {
                    guard size % 12 == 0 else { throw HwpNativeReadError.invalidData }
                    for position in stride(from: offset, to: end, by: 12) {
                        let value = try bytes.hwpUInt32(position + 8)
                        if value >> 24 == 2 {
                            paragraphs[index].highlights.append(HwpTextHighlight(
                                start: Int(try bytes.hwpUInt32(position)), end: Int(try bytes.hwpUInt32(position + 4)),
                                color: value & 0xffffff))
                        }
                    }
                }
            } else if tag == 71 { // CTRL_HEADER: descendants belong at the matching inline object marker.
                guard size >= 4, let owner = ancestors.last(where: { $0.level == level - 1 })?.index else {
                    throw HwpNativeReadError.invalidData
                }
                let identifier = try bytes.hwpUInt32(offset)
                let anchors = paragraphs[owner].anchors[identifier] ?? []
                let used = paragraphs[owner].usedAnchors[identifier, default: 0]
                let anchor = used < anchors.count ? anchors[used] : nil
                paragraphs[owner].usedAnchors[identifier] = used + 1
                // Graphic captions/text boxes may be absent from Hancom's HTML export.
                let auxiliary = paragraphs[owner].isAuxiliary || identifier == 0x67736f20 // "gso "
                controls.append((level, owner, anchor, auxiliary))
            }
            offset = end
        }
        // A parent paragraph's complete text precedes its table records in the file.
        // Interleave child paragraphs at their object markers to recover screen order.
        func flatten(_ index: Int) throws -> [HwpNativeParagraph] {
            let paragraph = paragraphs[index]
            let (decoded, offsets) = try decodeText(paragraph)
            if paragraph.children.isEmpty { return [decoded] }
            var result: [HwpNativeParagraph] = []
            var cursor = 0
            func appendText(until end: Int) {
                guard cursor < end else { return }
                let highlights = decoded.highlights.compactMap { range -> HwpTextHighlight? in
                    let start = max(cursor, range.start)
                    let upper = min(end, range.end)
                    return start < upper ? HwpTextHighlight(start: start - cursor, end: upper - cursor, color: range.color) : nil
                }
                result.append(HwpNativeParagraph(text: Array(decoded.text[cursor..<end]), highlights: highlights,
                                                 isAuxiliary: decoded.isAuxiliary))
            }
            for anchor in paragraph.children.keys.sorted() {
                let boundary = offsets[anchor]
                appendText(until: boundary)
                for child in paragraph.children[anchor] ?? [] { result.append(contentsOf: try flatten(child)) }
                cursor = boundary
            }
            appendText(until: decoded.text.count)
            return result
        }
        return try roots.flatMap(flatten)
    }

    private static func controlAnchors(in units: [UInt16]) throws -> [UInt32: [Int]] {
        var result: [UInt32: [Int]] = [:]
        var offset = 0
        while offset < units.count {
            if isWideControl(units[offset]) {
                guard offset + 8 <= units.count else { throw HwpNativeReadError.invalidData }
                let identifier = UInt32(units[offset + 1]) | UInt32(units[offset + 2]) << 16
                result[identifier, default: []].append(offset)
                offset += 8
            } else { offset += 1 }
        }
        return result
    }

    private static func isWideControl(_ value: UInt16) -> Bool {
        (1...9).contains(value) || [11, 12].contains(value) || (14...23).contains(value)
    }

    private static func decodeText(_ paragraph: Paragraph) throws -> (HwpNativeParagraph, [Int]) {
        let units = paragraph.text
        var text: [UInt16] = []
        var visibleOffsets = [Int](repeating: 0, count: units.count + 1)
        var offset = 0
        while offset < units.count {
            let value = units[offset]
            let next = offset + (isWideControl(value) ? 8 : 1)
            guard next <= units.count else { throw HwpNativeReadError.invalidData }
            for index in offset..<next { visibleOffsets[index] = text.count }
            if value >= 32 { text.append(value) }
            else if value == 9 { text.append(9) }
            else if value == 10 { text.append(10) }
            else if value == 24 { text.append(45) }
            else if value == 30 || value == 31 { text.append(32) }
            offset = next
            visibleOffsets[offset] = text.count
        }
        let ranges = try paragraph.highlights.map { range in
            guard range.start >= 0, range.start < range.end, range.end <= units.count else {
                throw HwpNativeReadError.invalidData
            }
            return HwpTextHighlight(start: visibleOffsets[range.start], end: visibleOffsets[range.end], color: range.color)
        }.filter { $0.start < $0.end }
        return (HwpNativeParagraph(text: text, highlights: ranges, isAuxiliary: paragraph.isAuxiliary), visibleOffsets)
    }

    private static func inflateSection(_ bytes: [UInt8]) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw HwpNativeReadError.invalidData
        }
        defer { inflateEnd(&stream) }
        return try bytes.withUnsafeBufferPointer { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress)
            stream.avail_in = uInt(bytes.count)
            var output: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { buffer in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let written = buffer.count - Int(stream.avail_out)
                guard output.count + written <= HwpCompoundFile.byteLimit,
                      status == Z_OK || status == Z_STREAM_END else { throw HwpNativeReadError.invalidData }
                output.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END { return output }
                guard written > 0 else { throw HwpNativeReadError.invalidData }
            }
        }
    }
}
