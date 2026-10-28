import Foundation

public struct ConversionResult: Sendable {
    public let html: String
    public let plainText: String
    public let hasDiagonal: Bool
    public let hasUnrestoredHighlights: Bool
    public let unconvertedImageCount: Int
}

public enum ConversionError: LocalizedError, Equatable {
    case noHTMLTable
    case notHangulTable
    case tableNotFound
    case invalidColor(String)
    case clipboardChanged
    case clipboardWriteFailed
    case layoutTooComplex

    public var errorDescription: String? {
        switch self {
        case .noHTMLTable:
            "한글 프로그램에서 표를 복사한 후 다시 시도해주세요."
        case .notHangulTable:
            "한글 프로그램에서 복사한 표만 변환할 수 있습니다."
        case .tableNotFound:
            "표를 찾을 수 없습니다."
        case .invalidColor(let value):
            "표의 색상 값을 읽을 수 없습니다: \(value)"
        case .layoutTooComplex:
            "표의 중첩·병합 구조가 너무 복잡해 변환하지 못했습니다. 복사한 원본은 유지됩니다."
        case .clipboardChanged:
            "변환 중 클립보드가 변경되었습니다. 표를 다시 복사한 후 시도해주세요."
        case .clipboardWriteFailed:
            "변환된 표를 클립보드에 저장하지 못했습니다."
        }
    }
}
