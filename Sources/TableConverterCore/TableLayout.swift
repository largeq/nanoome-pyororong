import SwiftSoup

enum DocumentBlock {
    case paragraph(source: Element, nodes: [Node])
    case table(Element)
}

struct LayoutCell {
    let source: Element
    let paragraphs: [DocumentBlock]
    var row: Int
    var column: Int
    var rowSpan: Int
    var columnSpan: Int
    var widthFraction: Double
    let isFragment: Bool
}

struct TableLayout {
    var rows: Int
    var columns: Int
    var cells: [LayoutCell]
}

/// Expands nested tables into the surrounding grid, retaining each piece of
/// content once. Original DOM nodes remain attached so CSS inheritance survives.
struct TableLayoutBuilder {
    let styles: (Element) throws -> [String: String]
    let blocks: (Element) throws -> [DocumentBlock]
    private let trackLimit = 4096
    private let cellLimit = 100_000

    private struct SourceCell {
        let source: Element
        let row: Int
        let column: Int
        let rowSpan: Int
        let columnSpan: Int
        let content: TableLayout
    }

    func build(_ table: Element, depth: Int = 0) throws -> TableLayout {
        guard depth < 16 else { throw ConversionError.layoutTooComplex }
        let rows = try table.getElementsByTag("tr").array().filter { nearestTable($0) === table }
        guard rows.count <= trackLimit else { throw ConversionError.layoutTooComplex }
        var occupied = Array(repeating: Set<Int>(), count: rows.count)
        var sourceCells: [SourceCell] = []
        var columns = 1
        var rowWidths = Array(repeating: 0.0, count: rows.count)
        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            for cell in try row.select("td, th").array().filter({ nearestTable($0) === table }) {
                let columnSpan = max(1, Int(try cell.attr("colspan")) ?? 1)
                let requestedRows = Int(try cell.attr("rowspan")) ?? 1
                let rowSpan = requestedRows == 0 ? rows.count - rowIndex : min(max(1, requestedRows), rows.count - rowIndex)
                guard columnSpan <= trackLimit else { throw ConversionError.layoutTooComplex }
                while (column..<column + columnSpan).contains(where: { occupied[rowIndex].contains($0) }) {
                    column += 1
                    guard column + columnSpan <= trackLimit else { throw ConversionError.layoutTooComplex }
                }
                guard column + columnSpan <= trackLimit, sourceCells.count < cellLimit else {
                    throw ConversionError.layoutTooComplex
                }
                for r in rowIndex..<rowIndex + rowSpan {
                    occupied[r].formUnion(column..<column + columnSpan)
                }
                let content = try cellContent(cell, depth: depth)
                sourceCells.append(SourceCell(source: cell, row: rowIndex, column: column,
                    rowSpan: rowSpan, columnSpan: columnSpan, content: content))
                rowWidths[rowIndex] += try pixels(styles(cell)["width"]) ?? 0
                column += columnSpan
                columns = max(columns, column)
            }
        }
        let explicitWidth = try pixels(styles(table)["width"])
        let width = explicitWidth ?? rowWidths.max() ?? 0
        var rowTracks = Array(repeating: 1, count: rows.count)
        var columnTracks = Array(repeating: 1, count: columns)
        // A shared subdivision lets a three-column inner table coexist with
        // five surrounding columns, without changing their physical widths.
        var changed = true
        while changed {
            changed = false
            for cell in sourceCells {
                changed = try subdivide(&rowTracks, start: cell.row, span: cell.rowSpan,
                                        multiple: cell.content.rows) || changed
                changed = try subdivide(&columnTracks, start: cell.column, span: cell.columnSpan,
                                        multiple: cell.content.columns) || changed
            }
        }
        let rowOffsets = offsets(rowTracks)
        let columnOffsets = offsets(columnTracks)
        var output: [LayoutCell] = []
        for cell in sourceCells {
            let rowScale = (rowOffsets[cell.row + cell.rowSpan] - rowOffsets[cell.row]) / cell.content.rows
            let columnScale = (columnOffsets[cell.column + cell.columnSpan] - columnOffsets[cell.column]) / cell.content.columns
            let cellWidth = try pixels(styles(cell.source)["width"])
            let fraction = cellWidth.flatMap { width > 0 ? $0 / width : nil }
                ?? Double(cell.columnSpan) / Double(columns)
            for var child in cell.content.cells {
                child.row = rowOffsets[cell.row] + child.row * rowScale
                child.column = columnOffsets[cell.column] + child.column * columnScale
                child.rowSpan *= rowScale
                child.columnSpan *= columnScale
                child.widthFraction *= fraction
                output.append(child)
                guard output.count <= cellLimit else { throw ConversionError.layoutTooComplex }
            }
        }
        return TableLayout(rows: rowOffsets.last ?? 0, columns: columnOffsets.last ?? 1,
                           cells: output.sorted { ($0.row, $0.column) < ($1.row, $1.column) })
    }

    private func cellContent(_ cell: Element, depth: Int) throws -> TableLayout {
        let content = try blocks(cell)
        guard content.contains(where: { if case .table = $0 { true } else { false } }) else {
            return TableLayout(rows: 1, columns: 1, cells: [LayoutCell(source: cell,
                paragraphs: content, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                widthFraction: 1, isFragment: false)])
        }
        var pieces: [TableLayout] = []
        var paragraphs: [DocumentBlock] = []
        func flush() {
            guard !paragraphs.isEmpty else { return }
            pieces.append(TableLayout(rows: 1, columns: 1, cells: [LayoutCell(source: cell,
                paragraphs: paragraphs, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                widthFraction: 1, isFragment: true)]))
            paragraphs.removeAll()
        }
        for block in content {
            switch block {
            case .paragraph: paragraphs.append(block)
            case .table(let child):
                flush()
                let grid = try build(child, depth: depth + 1)
                if grid.rows > 0 { pieces.append(grid) }
            }
        }
        flush()
        var columns = 1
        for piece in pieces {
            let factor = piece.columns / gcd(columns, piece.columns)
            guard columns <= trackLimit / factor else { throw ConversionError.layoutTooComplex }
            columns *= factor
        }
        var cells: [LayoutCell] = []
        var rowOffset = 0
        for piece in pieces {
            for var child in piece.cells {
                child.row += rowOffset
                child.column *= columns / piece.columns
                child.columnSpan *= columns / piece.columns
                cells.append(child)
            }
            rowOffset += piece.rows
            guard rowOffset <= trackLimit, cells.count <= cellLimit else { throw ConversionError.layoutTooComplex }
        }
        return TableLayout(rows: max(1, rowOffset), columns: columns, cells: cells)
    }

    private func subdivide(_ tracks: inout [Int], start: Int, span: Int, multiple: Int) throws -> Bool {
        let total = tracks[start..<start + span].reduce(0, +)
        let factor = multiple / gcd(total, multiple)
        guard factor > 1 else { return false }
        guard total <= trackLimit / factor else { throw ConversionError.layoutTooComplex }
        for index in start..<start + span { tracks[index] *= factor }
        guard tracks.reduce(0, +) <= trackLimit else { throw ConversionError.layoutTooComplex }
        return true
    }

    private func offsets(_ tracks: [Int]) -> [Int] {
        var output = [0]
        for value in tracks { output.append(output.last! + value) }
        return output
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(1, a)
    }

    private func nearestTable(_ element: Element) -> Element? {
        element.parents().array().first { $0.tagName() == "table" }
    }

    private func pixels(_ value: String?) -> Double? {
        guard let value, value.hasSuffix("px"), let number = Double(value.dropLast(2)),
              number.isFinite, number > 0 else { return nil }
        return number
    }
}
