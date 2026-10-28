import Foundation
import SwiftSoup

/// Converts Hancom clipboard HTML without depending on macOS UI or clipboard access.
public struct HangulTableConverter: Sendable {
    private typealias StyleSheet = [ObjectIdentifier: [String: String]]
    public init() {}

    public func isHangulTable(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        return ["mso-", "hancom", "xmlns:w=\"urn:schemas-microsoft-com:office:word\""]
            .contains { lowercased.contains($0) }
    }

    public func convert(_ html: String, nativeHwpData: Data? = nil) throws -> ConversionResult {
        guard isHangulTable(html) else { throw ConversionError.notHangulTable }
        // Hancom's XHTML pasteboard format contains HTML and Office-specific declarations.
        // Parse as HTML explicitly, even if an XML declaration is present.
        let document = try SwiftSoup.parseHTML(html)
        guard !(try document.getElementsByTag("table").isEmpty()), let body = document.body() else {
            throw ConversionError.tableNotFound
        }
        var hasUnrestoredHighlights = false
        if let nativeHwpData {
            do {
                let paragraphs = try HwpHighlightReader.read(nativeHwpData)
                hasUnrestoredHighlights = try !HwpHighlightOverlay.restore(paragraphs, in: body)
            } catch {
                // Keep the HTML conversion usable if the optional native format cannot be read.
                hasUnrestoredHighlights = true
            }
        }
        let styleSheet = try readStyleSheet(document)
        let convertedHTML = try convertDocument(blocks(in: body), styleSheet: styleSheet)
        let convertedDocument = try SwiftSoup.parseHTML(convertedHTML)
        return ConversionResult(
            html: convertedHTML,
            plainText: textContent(of: convertedDocument),
            hasDiagonal: html.lowercased().contains("mso-diagonal"),
            hasUnrestoredHighlights: hasUnrestoredHighlights,
            unconvertedImageCount: try document.select("img").array().filter {
                !isWebImage(try $0.attr("src"))
            }.count
        )
    }

    private let paragraphTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "pre"]
    private let containerTags: Set<String> = ["div", "section", "article", "main", "header", "footer", "blockquote", "ul", "ol"]

    private func blocks(in element: Element) -> [DocumentBlock] {
        var result: [DocumentBlock] = []
        var inline: [Node] = []
        func flush() {
            if inline.contains(where: isContent) { result.append(.paragraph(source: element, nodes: inline)) }
            inline.removeAll()
        }
        for node in element.getChildNodes() {
            if let child = node as? Element {
                let tag = child.tagName()
                if ["script", "style", "head", "meta", "link", "title"].contains(tag) { continue }
                if tag == "table" {
                    flush()
                    result.append(.table(child))
                } else if paragraphTags.contains(tag) || containerTags.contains(tag) || hasBlockChildren(child) {
                    flush()
                    let nested = blocks(in: child)
                    if nested.isEmpty && paragraphTags.contains(tag) {
                        result.append(.paragraph(source: child, nodes: []))
                    } else {
                        result.append(contentsOf: nested)
                    }
                } else {
                    inline.append(child)
                }
            } else if node is TextNode {
                inline.append(node)
            }
        }
        flush()
        return result
    }

    private func hasBlockChildren(_ element: Element) -> Bool {
        element.getChildNodes().contains { node in
            guard let child = node as? Element else { return false }
            return child.tagName() == "table" || paragraphTags.contains(child.tagName())
                || containerTags.contains(child.tagName()) || hasBlockChildren(child)
        }
    }

    private func isContent(_ node: Node) -> Bool {
        if let text = node as? TextNode {
            let value = textContent(of: text)
            return !value.isEmpty && value != "\n"
        }
        if let element = node as? Element, ["br", "img"].contains(element.tagName()) { return true }
        return node.getChildNodes().contains(where: isContent)
    }

    private func convertDocument(_ blocks: [DocumentBlock], styleSheet: StyleSheet) throws -> String {
        var output = ""
        var paragraphs = ""
        func flush() {
            guard !paragraphs.isEmpty else { return }
            let id = makeID()
            output += "<div class=\"se-component se-text se-l-default\" id=\"\(id)\" data-compid=\"\(id)\"><div class=\"se-component-content\"><div class=\"se-section se-section-text se-l-default\"><div class=\"se-module se-module-text\">\(paragraphs)</div></div></div></div>"
            paragraphs = ""
        }
        for block in blocks {
            switch block {
            case .paragraph:
                paragraphs += try renderParagraph(block, styleSheet: styleSheet)
            case .table(let table):
                flush()
                output += try createTable(from: table, styleSheet: styleSheet)
            }
        }
        flush()
        return output
    }

    private func createTable(from table: Element, styleSheet: StyleSheet) throws -> String {
        let builder = TableLayoutBuilder(
            styles: { try localStyles(of: $0, styleSheet: styleSheet) },
            blocks: { blocks(in: $0) }
        )
        let grid = try builder.build(table)
        let tableStyle = "border-collapse: collapse; table-layout: fixed; width: 100%; max-width: 100%;"
        let id = makeID()
        var output = "<div class=\"se-component se-table se-l-default\" id=\"\(id)\" data-compid=\"\(id)\">"
        output += "<div class=\"se-component-content\"><div class=\"se-section se-section-table se-l-default\">"
        output += "<div class=\"se-table-container\"><table class=\"se-table-content\" style=\"\(escape(tableStyle))\"><tbody>"
        let rows = Dictionary(grouping: grid.cells, by: \.row)
        for index in 0..<grid.rows {
            output += "<tr class=\"se-tr\" id=\"\(makeID())\">"
            for cell in rows[index] ?? [] { output += try convertCell(cell, styleSheet: styleSheet) }
            output += "</tr>"
        }
        return output + "</tbody></table></div></div></div></div>"
    }

    private func convertCell(_ cell: LayoutCell, styleSheet: StyleSheet) throws -> String {
        let styles = try localStyles(of: cell.source, styleSheet: styleSheet)
        var style = "width: \(cssNumber(cell.widthFraction * 100))%;"
        if !cell.isFragment, let height = styles["height"], !height.isEmpty { style += " height: \(height);" }
        if let background = styles["background-color"], !background.isEmpty { style += " background-color: \(background);" }
        let borderKeys = ["border", "border-top", "border-left", "border-bottom", "border-right"]
        if cell.isFragment {
            style += " border: none;"
        } else if borderKeys.contains(where: { styles[$0] != nil }) {
            for key in borderKeys { if let value = styles[key] { style += " \(key): \(value);" } }
        } else {
            style += " border: 1px solid #000000;"
        }
        for key in ["padding", "padding-top", "padding-right", "padding-bottom", "padding-left", "vertical-align"] {
            if let value = styles[key] { style += " \(key): \(value);" }
        }
        if styles["vertical-align"] == nil, let value = try? cell.source.attr("valign"), ["top", "middle", "bottom"].contains(value) {
            style += " vertical-align: \(value);"
        }
        var output = "<td id=\"\(makeID())\" colspan=\"\(cell.columnSpan)\" rowspan=\"\(cell.rowSpan)\" class=\"se-cell\" style=\"\(escape(style))\"><div class=\"se-module se-module-text\">"
        if cell.paragraphs.isEmpty {
            output += try renderParagraph(.paragraph(source: cell.source, nodes: []), styleSheet: styleSheet)
        } else {
            for block in cell.paragraphs { output += try renderParagraph(block, styleSheet: styleSheet) }
        }
        return output + "</div></td>"
    }

    private func renderParagraph(_ block: DocumentBlock, styleSheet: StyleSheet) throws -> String {
        guard case .paragraph(let source, let nodes) = block else { return "" }
        return try paragraph(
            alignment: alignment(of: source, styleSheet: styleSheet),
            content: nodes.map { try convertInlineContent($0, styleSheet: styleSheet) }.joined(),
            lineHeight: inheritedTextStyles(of: source, styleSheet: styleSheet)["line-height"] ?? "1.6"
        )
    }

    private func convertInlineContent(_ node: Node, styleSheet: StyleSheet) throws -> String {
        if let text = node as? TextNode {
            let value = textContent(of: text)
            // Formatting newlines between HTML elements are not document line breaks.
            if value == "\n" { return "" }
            guard let parent = text.parent() as? Element else { return escape(value) }
            let styles = try inheritedTextStyles(of: parent, styleSheet: styleSheet)
            return span(
                text: value,
                color: styles["color"] ?? "rgb(0, 0, 0)",
                bold: styles["font-weight"] == "bold" || (Double(styles["font-weight"] ?? "") ?? 0) >= 600,
                underline: styles["text-decoration"]?.contains("underline") == true,
                strike: styles["text-decoration"]?.contains("line-through") == true,
                italic: styles["font-style"] == "italic",
                backgroundColor: try inlineBackground(of: parent, styleSheet: styleSheet),
                fontFamily: styles["font-family"],
                fontSize: styles["font-size"]
            )
        }
        if let element = node as? Element {
            if ["script", "style"].contains(element.tagName()) { return "" }
            if element.tagName() == "br" { return "<br>" }
            if element.tagName() == "img" {
                let src = try element.attr("src")
                // The Cafe editor accepts web images, but rejects file: and
                // data: images. Report those instead of claiming they pasted.
                guard isWebImage(src) else { return "" }
                return "<img src=\"\(escape(src))\" alt=\"\(escape(try element.attr("alt")))\" style=\"max-width:100%;\">"
            }
            if element.tagName() == "a", let href = try? element.attr("href"),
               ["https://", "http://", "mailto:", "tel:", "#"].contains(where: { href.lowercased().hasPrefix($0) }) {
                let content = try element.getChildNodes().map { try convertInlineContent($0, styleSheet: styleSheet) }.joined()
                return "<a href=\"\(escape(href))\">\(content)</a>"
            }
        }
        return try node.getChildNodes().map { try convertInlineContent($0, styleSheet: styleSheet) }.joined()
    }

    private func paragraph(alignment: String, content: String, lineHeight: String) -> String {
        "<p id=\"\(makeID())\" class=\"se-text-paragraph se-text-paragraph-align-\(alignment)\" style=\"text-align: \(escape(alignment)); line-height: \(escape(lineHeight));\">\(content)</p>"
    }

    private func span(
        text: String,
        color: String = "rgb(0, 0, 0)",
        bold: Bool = false,
        underline: Bool = false,
        strike: Bool = false,
        italic: Bool = false,
        backgroundColor: String? = nil,
        fontFamily: String? = nil,
        fontSize: String? = nil
    ) -> String {
        var style = "color: \(color);"
        if let backgroundColor { style += " background-color: \(backgroundColor);" }
        let decorations = [underline ? "underline" : nil, strike ? "line-through" : nil].compactMap { $0 }
        if !decorations.isEmpty { style += " text-decoration: \(decorations.joined(separator: " "));" }
        if italic { style += " font-style: italic;" }
        if let fontFamily, !fontFamily.isEmpty { style += " font-family: \(fontFamily);" }
        if let fontSize, !fontSize.isEmpty { style += " font-size: \(fontSize);" }
        var classes: [String] = []
        if let size = pixels(fontSize) {
            let supported = [11, 13, 15, 16, 19, 24, 28, 30, 34, 38]
            let nearest = supported.min { abs(Double($0) - size) < abs(Double($1) - size) }!
            classes.append("se-fs-fs\(nearest)")
        }
        if let fontFamily {
            let name = fontFamily.lowercased().replacingOccurrences(of: " ", with: "")
            if name.contains("나눔바른고딕") || name.contains("nanumbarungothic") {
                classes.append("se-ff-nanumbarungothic")
            } else if name.contains("나눔고딕") || name.contains("nanumgothic") {
                classes.append("se-ff-nanumgothic")
            }
        }
        var output = "<span id=\"\(makeID())\" class=\"\(classes.joined(separator: " "))\" style=\"\(escape(style))\">"
        if bold { output += "<b>" }
        if underline { output += "<u>" }
        // Cafe's paste importer recognizes strike/del, but drops s and CSS-only strikeout.
        if strike { output += "<strike>" }
        if italic { output += "<i>" }
        output += escape(text)
        if italic { output += "</i>" }
        if strike { output += "</strike>" }
        if underline { output += "</u>" }
        if bold { output += "</b>" }
        return output + "</span>"
    }

    private func alignment(of element: Element, styleSheet: StyleSheet) throws -> String {
        let value = try inheritedTextStyles(of: element, styleSheet: styleSheet)["text-align"] ?? "left"
        return ["left", "center", "right", "justify"].contains(value) ? value : "left"
    }

    private func isWebImage(_ source: String) -> Bool {
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return false }
        return true
    }

    private func localStyles(of element: Element, styleSheet: StyleSheet) throws -> [String: String] {
        var styles = styleSheet[ObjectIdentifier(element)] ?? [:]
        styles.merge(try convertedStyles(element.attr("style"))) { _, inline in inline }
        return styles
    }

    private func inlineBackground(of element: Element, styleSheet: StyleSheet) throws -> String? {
        // Highlight belongs to the inline text. A cell/paragraph background must
        // not become a highlighter mark when the editor imports the text.
        for ancestor in [element] + element.parents().array() {
            let tag = ancestor.tagName()
            if paragraphTags.contains(tag) || containerTags.contains(tag)
                || ["td", "th", "tr", "table", "body", "html"].contains(tag) { break }
            let styles = try localStyles(of: ancestor, styleSheet: styleSheet)
            if let background = styles["background-color"] ?? styles["background"] {
                let value = background.lowercased().replacingOccurrences(of: " ", with: "")
                if !["", "transparent", "none", "inherit", "initial", "unset", "rgba(0,0,0,0)"].contains(value) {
                    return background
                }
            }
        }
        return nil
    }

    private func inheritedTextStyles(of element: Element, styleSheet: StyleSheet) throws -> [String: String] {
        let inheritedKeys: Set<String> = ["font-family", "font-size", "font-weight", "font-style", "text-decoration", "text-decoration-line", "color", "text-align", "line-height"]
        var styles: [String: String] = [:]
        var decorations = Set<String>()
        for ancestor in Array(element.parents().array().reversed()) + [element] {
            if ["b", "strong"].contains(ancestor.tagName()) { styles["font-weight"] = "bold" }
            if ancestor.tagName() == "u" { decorations.insert("underline") }
            if ["s", "strike", "del"].contains(ancestor.tagName()) { decorations.insert("line-through") }
            if ["i", "em"].contains(ancestor.tagName()) { styles["font-style"] = "italic" }
            for (key, value) in try localStyles(of: ancestor, styleSheet: styleSheet)
            where inheritedKeys.contains(key) && !["inherit", "unset"].contains(value) {
                styles[key] = value
                if ["text-decoration", "text-decoration-line"].contains(key) {
                    for decoration in ["underline", "line-through"] where value.contains(decoration) {
                        decorations.insert(decoration)
                    }
                }
            }
        }
        styles["text-decoration"] = decorations.sorted().joined(separator: " ")
        return styles
    }

    private func readStyleSheet(_ document: Document) throws -> StyleSheet {
        var rules: [(selector: String, styles: [String: String], specificity: Int, order: Int)] = []
        let expression = try NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
        for element in try document.getElementsByTag("style") {
            let css = element.data()
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "(?s)/\\*.*?\\*/", with: "", options: .regularExpression)
            let string = css as NSString
            for match in expression.matches(in: css, range: NSRange(location: 0, length: string.length)) {
                let selectors = string.substring(with: match.range(at: 1))
                let styles = try convertedStyles(string.substring(with: match.range(at: 2)))
                for raw in selectors.split(separator: ",") {
                    let selector = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !selector.isEmpty, !selector.contains("@") else { continue }
                    let specificity = selector.filter { $0 == "#" }.count * 100
                        + selector.filter { $0 == "." || $0 == "[" }.count * 10
                        + selector.split(whereSeparator: { " >+~".contains($0) }).filter { $0.first?.isLetter == true }.count
                    rules.append((selector, styles, specificity, rules.count))
                }
            }
        }
        var result: StyleSheet = [:]
        for rule in rules.sorted(by: { ($0.specificity, $0.order) < ($1.specificity, $1.order) }) {
            guard let elements = try? document.select(rule.selector) else { continue }
            for element in elements {
                result[ObjectIdentifier(element), default: [:]].merge(rule.styles) { _, new in new }
            }
        }
        return result
    }

    private func pixels(_ value: String?) -> Double? {
        guard let value, value.hasSuffix("px"), let number = Double(value.dropLast(2)), number.isFinite else { return nil }
        return number
    }

    private func cssNumber(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    func convertedStyles(_ style: String) throws -> [String: String] {
        // Hancom sometimes omits the semicolon before a background declaration
        // embedded in an Office diagonal declaration. Recover it before skipping mso-.
        let cleaned = style.replacingOccurrences(
            of: "(?i)(mso-diagonal-[^;]*?)\\s+(background(?:-color)?\\s*:)",
            with: "$1;$2", options: .regularExpression
        )
        var result: [String: String] = [:]
        for declaration in cleaned.split(separator: ";") {
            guard let separator = declaration.firstIndex(of: ":") else { continue }
            var key = declaration[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = declaration[declaration.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("mso-") { continue }
            if ["background", "background-color", "color"].contains(key), value.hasPrefix("#") {
                value = try rgb(from: value)
                if key == "background" { key = "background-color" }
            }
            if ["width", "height", "font-size"].contains(key), value.lowercased().hasSuffix("pt"),
               let points = Double(value.dropLast(2)), points.isFinite, (points * 4 / 3).isFinite {
                value = "\(cssNumber(points * 4 / 3))px"
            }
            result[key] = value
        }
        return result
    }

    private func rgb(from hex: String) throws -> String {
        let digits = hex.drop(while: { $0 == "#" })
        guard digits.count == 6 else { return "rgb(0, 0, 0)" }
        guard let value = UInt32(digits, radix: 16) else { throw ConversionError.invalidColor(hex) }
        return "rgb(\((value >> 16) & 255), \((value >> 8) & 255), \(value & 255))"
    }

    private func makeID() -> String { "SE-\(UUID().uuidString.lowercased())" }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

/// Like BeautifulSoup.get_text(): concatenate text nodes without adding layout whitespace.
/// A normal HTML parser's `text()` can insert spaces and change table contents.
func textContent(of node: Node) -> String {
    if let text = node as? TextNode {
        var value = text.getWholeText()
        // BeautifulSoup's HTML builder collapses whitespace-only source nodes.
        // Keep NBSP and whitespace within actual text unchanged.
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ " \t\r\n\u{000c}".unicodeScalars.contains($0) }) {
            value = value.contains("\n") ? "\n" : " "
        }
        return value
    }
    if let element = node as? Element {
        if ["script", "style"].contains(element.tagName()) { return "" }
        if element.tagName() == "br" { return "\n" }
    }
    return node.getChildNodes().map { textContent(of: $0) }.joined()
}
