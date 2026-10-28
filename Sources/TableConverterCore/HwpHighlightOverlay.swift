import Foundation
import SwiftSoup

enum HwpHighlightOverlay {
    private struct TextSlice {
        let node: TextNode
        let units: [UInt16]
        let offsets: [Int]
        let start: Int
    }

    /// Match the complete visible text in order before applying any color. Searching for
    /// individual phrases could color the wrong occurrence in repeated table cells.
    static func restore(_ paragraphs: [HwpNativeParagraph], in body: Element) throws -> Bool {
        if let complete = try restoreExact(paragraphs, in: body) { return complete }
        let visible = paragraphs.filter { !$0.isAuxiliary }
        if visible.count != paragraphs.count, let complete = try restoreExact(visible, in: body) {
            return complete && !paragraphs.contains { $0.isAuxiliary && !$0.highlights.isEmpty }
        }
        return false
    }

    private static func restoreExact(_ paragraphs: [HwpNativeParagraph], in body: Element) throws -> Bool? {
        guard paragraphs.contains(where: { !$0.highlights.isEmpty }) else { return true }
        var native: [UInt16] = []
        var ranges: [HwpTextHighlight] = []
        var spaces: [(token: Int, length: Int, start: Int, end: Int, run: Int)] = []
        var complete = true
        for paragraph in paragraphs {
            let offsets = paragraph.text.indices.filter { !isSpacing(paragraph.text[$0]) }
            let start = native.count
            native.append(contentsOf: offsets.map { paragraph.text[$0] })
            for range in paragraph.highlights {
                let lower = lowerBound(offsets, range.start)
                let upper = lowerBound(offsets, range.end)
                if lower == upper {
                    // A highlighter can cover only a space between two letters.
                    if lower > 0, lower < offsets.count {
                        let gapStart = offsets[lower - 1] + 1
                        spaces.append((start + lower, offsets[lower] - gapStart,
                                       range.start - gapStart, range.end - gapStart, ranges.count))
                    } else { complete = false }
                }
                ranges.append(HwpTextHighlight(start: start + lower, end: start + upper, color: range.color))
            }
        }
        var html: [UInt16] = []
        var slices: [TextSlice] = []
        for node in textNodes(in: body) {
            let units = Array(node.getWholeText().utf16)
            let offsets = units.indices.filter { !isSpacing(units[$0]) }
            slices.append(TextSlice(node: node, units: units, offsets: offsets, start: html.count))
            html.append(contentsOf: offsets.map { units[$0] })
        }
        guard native == html else { return nil }
        // Range identities keep a plain space between separate same-color highlights plain.
        var runs = [Int](repeating: -1, count: native.count)
        var work = 0
        for (index, range) in ranges.enumerated() {
            work += range.end - range.start
            guard work <= HwpCompoundFile.byteLimit else { return false }
            for position in range.start..<range.end { runs[position] = index }
        }
        // Never split a UTF-16 surrogate pair into two differently styled strings.
        for index in native.indices where (0xd800...0xdbff).contains(native[index]) {
            guard index + 1 < native.count, (0xdc00...0xdfff).contains(native[index + 1]),
                  runs[index] == runs[index + 1] else { return false }
        }
        let nonempty = slices.indices.filter { !slices[$0].offsets.isEmpty }
        let starts = nonempty.map { slices[$0].start }
        var spaceColors: [Int: [(offset: Int, run: Int)]] = [:]
        for space in spaces {
            let previous = nonempty[lowerBound(starts, space.token) - 1]
            let next = nonempty[lowerBound(starts, space.token + 1) - 1]
            guard textBlock(of: slices[previous].node) === textBlock(of: slices[next].node) else {
                complete = false
                continue
            }
            var positions: [(Int, Int)] = []
            for index in previous...next {
                let slice = slices[index]
                let lower = index == previous ? slice.offsets[space.token - 1 - slice.start] + 1 : 0
                let upper = index == next ? slice.offsets[space.token - slice.start] : slice.units.count
                positions.append(contentsOf: (lower..<upper).map { (index, $0) })
            }
            guard positions.count == space.length, space.start >= 0, space.end <= positions.count else {
                complete = false
                continue
            }
            for (index, offset) in positions[space.start..<space.end] {
                spaceColors[index, default: []].append((offset, space.run))
            }
        }
        for (sliceIndex, slice) in slices.enumerated() {
            var colors = [Int](repeating: -1, count: slice.units.count)
            for (index, offset) in slice.offsets.enumerated() { colors[offset] = runs[slice.start + index] }
            // Carry a highlight across whitespace only while inside the same original range.
            let boundaries = [-1] + slice.offsets + [slice.units.count]
            for index in 0..<boundaries.count - 1 {
                let previous = slice.start + index - 1
                let next = slice.start + index
                if previous >= 0, next < runs.count, runs[previous] >= 0, runs[previous] == runs[next] {
                    for offset in (boundaries[index] + 1)..<boundaries[index + 1] { colors[offset] = runs[next] }
                }
            }
            for color in spaceColors[sliceIndex] ?? [] { colors[color.offset] = max(colors[color.offset], color.run) }
            guard colors.contains(where: { $0 >= 0 }) else { continue }
            var start = 0
            while start < slice.units.count {
                let run = colors[start]
                var end = start + 1
                while end < colors.count && colors[end] == run { end += 1 }
                let text = TextNode(String(decoding: slice.units[start..<end], as: UTF16.self), "")
                if run >= 0 {
                    let value = ranges[run].color
                    let span = Element(try Tag.valueOf("span"), "")
                    try span.attr("style", "background-color: rgb(\(value & 255), \((value >> 8) & 255), \((value >> 16) & 255));")
                    try span.appendChild(text)
                    try slice.node.before(span)
                } else {
                    try slice.node.before(text)
                }
                start = end
            }
            try slice.node.remove()
        }
        return complete
    }

    private static func textBlock(of node: Node) -> Node {
        var ancestor = node.parent()
        while let element = ancestor as? Element {
            if ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "pre", "td", "th", "body"].contains(element.tagName()) { return element }
            ancestor = element.parent()
        }
        return node
    }

    private static func textNodes(in node: Node) -> [TextNode] {
        if let text = node as? TextNode { return [text] }
        if let element = node as? Element, ["script", "style"].contains(element.tagName()) { return [] }
        return node.getChildNodes().flatMap { textNodes(in: $0) }
    }

    private static func lowerBound(_ offsets: [Int], _ value: Int) -> Int {
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if offsets[middle] < value { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }

    private static func isSpacing(_ unit: UInt16) -> Bool {
        (9...13).contains(unit) || [0, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x2060, 0x3000, 0xfeff].contains(unit)
            || (0x2000...0x200b).contains(unit)
    }
}
