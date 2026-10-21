import Foundation
import SwiftSoup

/// The conversion rules of the Python version, independent of macOS UI and clipboard access.
public struct HangulTableConverter: Sendable {
    public init() {}

    public func isHangulTable(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        return ["mso-", "hancom", "xmlns:w=\"urn:schemas-microsoft-com:office:word\""]
            .contains { lowercased.contains($0) }
    }

    public func convert(_ html: String) throws -> ConversionResult {
        guard isHangulTable(html) else { throw ConversionError.notHangulTable }
        // Hancom's XHTML pasteboard format contains HTML and Office-specific declarations.
        // Parse as HTML explicitly, even if an XML declaration is present.
        let document = try SwiftSoup.parseHTML(html)
        guard let table = try document.getElementsByTag("table").first() else {
            throw ConversionError.tableNotFound
        }
        let convertedHTML = try createTable(from: table)
        let convertedDocument = try SwiftSoup.parseHTML(convertedHTML)
        return ConversionResult(
            html: convertedHTML,
            plainText: textContent(of: convertedDocument),
            hasDiagonal: html.contains("mso-diagonal")
        )
    }

    private func createTable(from table: Element) throws -> String {
        let id = makeID()
        var output = "<div class=\"se-component se-table se-l-default\" id=\"\(id)\" data-compid=\"\(id)\">"
        output += "<div class=\"se-component-content\"><div class=\"se-section se-section-table se-l-default\">"
        output += "<div class=\"se-table-container\"><table class=\"se-table-content\" style=\"border-collapse: collapse;\"><tbody>"
        for row in try table.getElementsByTag("tr") {
            output += "<tr class=\"se-tr\" id=\"\(makeID())\">"
            for cell in try row.select("td, th") {
                output += try convertCell(cell)
            }
            output += "</tr>"
        }
        output += "</tbody></table></div></div></div></div>"
        return output
    }

    private func convertCell(_ cell: Element) throws -> String {
        let colspan = try cell.hasAttr("colspan") ? cell.attr("colspan") : "1"
        let rowspan = try cell.hasAttr("rowspan") ? cell.attr("rowspan") : "1"
        let styles = try convertedStyles(cell.attr("style"))
        var style = ""
        if let width = styles["width"], let height = styles["height"], !width.isEmpty, !height.isEmpty {
            style = "width: \(width); height: \(height);"
        }
        if let background = styles["background-color"], !background.isEmpty {
            style += " background-color: \(background);"
        }
        style += " border: 1px solid #000000;"

        var output = "<td id=\"\(makeID())\" colspan=\"\(escape(colspan))\" rowspan=\"\(escape(rowspan))\" class=\"se-cell\" style=\"\(escape(style))\">"
        output += "<div class=\"se-module se-module-text\">"
        let paragraphs = try cell.getElementsByTag("p")
        if paragraphs.isEmpty() {
            output += paragraph(
                alignment: try alignment(of: cell),
                content: span(text: textContent(of: cell, strip: true))
            )
        } else {
            for source in paragraphs {
                output += try paragraph(alignment: alignment(of: source), content: convertParagraph(source))
            }
        }
        output += "</div></td>"
        return output
    }

    private func convertParagraph(_ paragraph: Element) throws -> String {
        let spans = try paragraph.getElementsByTag("span")
        if spans.isEmpty() {
            return span(text: textContent(of: paragraph))
        }
        var output = ""
        for source in spans {
            let styles = try convertedStyles(source.attr("style"))
            let bold = try styles["font-weight"] == "bold" || !source.getElementsByTag("b").isEmpty()
            let underline = try styles["text-decoration"] == "underline" || !source.getElementsByTag("u").isEmpty()
            output += span(
                text: textContent(of: source),
                color: styles["color"] ?? "rgb(0, 0, 0)",
                bold: bold,
                underline: underline
            )
        }
        return output
    }

    private func paragraph(alignment: String, content: String) -> String {
        "<p id=\"\(makeID())\" class=\"se-text-paragraph se-text-paragraph-align-\(alignment)\" style=\"line-height: 1.6;\">\(content)</p>"
    }

    private func span(text: String, color: String = "rgb(0, 0, 0)", bold: Bool = false, underline: Bool = false) -> String {
        var output = "<span id=\"\(makeID())\" class=\"se-ff-nanumgothic se-fs15\" style=\"color: \(escape(color));\">"
        if bold { output += "<b>" }
        if underline { output += "<u>" }
        output += escape(text)
        if underline { output += "</u>" }
        if bold { output += "</b>" }
        return output + "</span>"
    }

    private func alignment(of element: Element) throws -> String {
        let style = try element.attr("style")
        if style.contains("text-align:center") || style.contains("text-align: center") { return "center" }
        if style.contains("text-align:right") || style.contains("text-align: right") { return "right" }
        return "left"
    }

    func convertedStyles(_ style: String) throws -> [String: String] {
        let cleaned = style.replacingOccurrences(of: "mso-diagonal-[^;]+;?", with: "", options: .regularExpression)
        var result: [String: String] = [:]
        for declaration in cleaned.split(separator: ";") {
            guard let separator = declaration.firstIndex(of: ":") else { continue }
            var key = declaration[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = declaration[declaration.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("mso-") { continue }
            if ["background", "background-color", "color"].contains(key), value.hasPrefix("#") {
                value = try rgb(from: value)
                if key == "background" { key = "background-color" }
            }
            // Preserve the legacy layout rules during migration; proportional widths are a later improvement.
            if key == "width", value.contains("pt") {
                value = "50%"
            } else if key == "height", value.contains("pt"),
                      let points = Double(value.replacingOccurrences(of: "pt", with: "")),
                      (points * 1.33).isFinite, abs(points * 1.33) < Double(Int.max) {
                value = "\(Int(points * 1.33))px"
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
func textContent(of node: Node, strip: Bool = false) -> String {
    if let text = node as? TextNode {
        var value = text.getWholeText()
        // BeautifulSoup's HTML builder collapses whitespace-only source nodes.
        // Keep NBSP and whitespace within actual text unchanged.
        if !value.isEmpty, value.allSatisfy({ " \t\r\n\u{000c}".contains($0) }) {
            value = value.contains("\n") ? "\n" : " "
        }
        return strip ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }
    if let element = node as? Element, ["script", "style"].contains(element.tagName()) { return "" }
    return node.getChildNodes().map { textContent(of: $0, strip: strip) }.joined()
}
