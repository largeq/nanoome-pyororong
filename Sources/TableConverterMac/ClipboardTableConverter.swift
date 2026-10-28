import AppKit
import TableConverterCore

public enum ClipboardTableState: Hashable, Sendable {
    case idle
    case readyToConvert
    case readyToPaste
    case conversionFailed
}

@MainActor
public final class ClipboardTableConverter {
    private static let convertedTableType = NSPasteboard.PasteboardType("com.phronesis.pyororong.converted-table")
    private static let legacyConvertedTableType = NSPasteboard.PasteboardType("com.phronesis.tableconverter.converted-table")
    private static let convertedTableVersion = "1"
    private let pasteboard: NSPasteboard
    private let converter = HangulTableConverter()
    private var observedClipboard: ClipboardSnapshot?
    private var cachedState = ClipboardTableState.idle
    private var failedClipboard: ClipboardSnapshot?
    private var prepared: PreparedConversion?

    private struct PreparedConversion {
        let snapshot: ClipboardSnapshot
        let task: Task<ConversionResult, Error>
        var result: ConversionResult?
    }

    private struct ClipboardSnapshot: Equatable {
        let changeCount: Int
        let types: [NSPasteboard.PasteboardType]
    }

    private var clipboardSnapshot: ClipboardSnapshot {
        ClipboardSnapshot(changeCount: pasteboard.changeCount, types: pasteboard.types ?? [])
    }

    public init(pasteboard: NSPasteboard? = nil) {
        self.pasteboard = pasteboard ?? .general
    }

    public var clipboardRevision: Int { pasteboard.changeCount }

    public var isReadyToPaste: Bool {
        (pasteboard.string(forType: Self.convertedTableType) == Self.convertedTableVersion
            || pasteboard.string(forType: Self.legacyConvertedTableType) == Self.convertedTableVersion) && readHTML() != nil
    }

    public func clipboardState() async -> ClipboardTableState {
        let snapshot = clipboardSnapshot
        if let failedClipboard {
            if failedClipboard == snapshot { return .conversionFailed }
            self.failedClipboard = nil
        }
        if observedClipboard == snapshot { return cachedState }

        let state: ClipboardTableState
        if isReadyToPaste {
            prepared = nil
            state = .readyToPaste
        } else {
            do {
                _ = try await prepareConversion()
                state = .readyToConvert
            } catch {
                state = .idle
            }
        }

        guard clipboardSnapshot == snapshot else { return .idle }
        observedClipboard = snapshot
        cachedState = state
        return state
    }

    public func convert() throws -> ConversionResult {
        let snapshot = clipboardSnapshot
        do {
            let result: ConversionResult
            if let prepared, prepared.snapshot == snapshot, let cached = prepared.result {
                result = cached
            } else {
                let input = try conversionInput()
                result = try converter.convert(input.html, nativeHwpData: input.nativeHwpData)
            }
            try write(result, originalChangeCount: snapshot.changeCount)
            prepared = nil
            failedClipboard = nil
            return result
        } catch {
            recordFailure(error, for: snapshot)
            throw error
        }
    }

    /// Only the immutable input leaves the main actor; pasteboard access stays here.
    public func convertAsync() async throws -> ConversionResult {
        let snapshot = clipboardSnapshot
        do {
            try Task.checkCancellation()
            let result = try await prepareConversion()
            try Task.checkCancellation()
            try write(result, originalChangeCount: snapshot.changeCount)
            prepared = nil
            failedClipboard = nil
            return result
        } catch {
            recordFailure(error, for: snapshot)
            throw error
        }
    }

    func prepareConversion() async throws -> ConversionResult {
        let snapshot = clipboardSnapshot
        let task: Task<ConversionResult, Error>
        if let prepared, prepared.snapshot == snapshot {
            task = prepared.task
        } else {
            prepared = nil
            let input = try conversionInput()
            guard clipboardSnapshot == snapshot else { throw ConversionError.clipboardChanged }
            task = Task.detached(priority: .userInitiated) {
                try HangulTableConverter().convert(input.html, nativeHwpData: input.nativeHwpData)
            }
            prepared = PreparedConversion(snapshot: snapshot, task: task)
        }
        let result = try await task.value
        guard clipboardSnapshot == snapshot else { throw ConversionError.clipboardChanged }
        if prepared?.snapshot == snapshot { prepared?.result = result }
        return result
    }

    private func recordFailure(_ error: Error, for snapshot: ClipboardSnapshot) {
        guard !(error is CancellationError),
              error as? ConversionError != .clipboardChanged,
              clipboardSnapshot == snapshot else { return }
        failedClipboard = snapshot
    }

    private struct ConversionInput: Sendable {
        let html: String
        let nativeHwpData: Data?
    }

    private func conversionInput() throws -> ConversionInput {
        let changeCount = pasteboard.changeCount
        guard let html = readHTML() else { throw ConversionError.noHTMLTable }
        let nativeHwpData = pasteboard.data(forType: .init("com.hancom.office.Hwp032Native"))
        guard pasteboard.changeCount == changeCount else { throw ConversionError.clipboardChanged }
        return ConversionInput(html: html, nativeHwpData: nativeHwpData)
    }

    private func write(_ result: ConversionResult, originalChangeCount: Int) throws {
        let item = NSPasteboardItem()
        guard item.setData(Data(result.html.utf8), forType: .html),
              item.setString(result.plainText, forType: .string),
              item.setString(Self.convertedTableVersion, forType: Self.convertedTableType) else {
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
