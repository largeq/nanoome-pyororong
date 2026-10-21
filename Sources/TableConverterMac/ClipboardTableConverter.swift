import AppKit
import TableConverterCore

@MainActor
public final class ClipboardTableConverter {
    private let pasteboard: NSPasteboard
    private let converter = HangulTableConverter()

    public init(pasteboard: NSPasteboard? = nil) {
        self.pasteboard = pasteboard ?? .general
    }

    public func convert() throws -> ConversionResult {
        let originalChangeCount = pasteboard.changeCount
        guard let html = readHTML() else { throw ConversionError.noHTMLTable }
        let result = try converter.convert(html)
        let item = NSPasteboardItem()
        guard item.setData(Data(result.html.utf8), forType: .html),
              item.setString(result.plainText, forType: .string) else {
            throw ConversionError.clipboardWriteFailed
        }

        let originals = copyItems()
        guard pasteboard.changeCount == originalChangeCount else { throw ConversionError.clipboardChanged }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(originals)
            throw ConversionError.clipboardWriteFailed
        }
        return result
    }

    private func readHTML() -> String? {
        for type in pasteboard.types ?? [] {
            guard type.rawValue.lowercased().contains("html"), let data = pasteboard.data(forType: type) else { continue }
            let html = String(decoding: data, as: UTF8.self)
            if html.lowercased().contains("<table") { return html }
        }
        return nil
    }

    private func copyItems() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
