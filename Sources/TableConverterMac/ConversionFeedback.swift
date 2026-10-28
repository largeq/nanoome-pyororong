import Foundation
import TableConverterCore

/// Presentation data only; showing or reopening a result never changes the clipboard.
public struct ConversionFeedback: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case success, partialSuccess, failure
    }

    public struct Detail: Equatable, Sendable {
        public let title: String
        public let message: String
    }

    public enum RecoveryAction: Equatable, Sendable {
        case retry, usageGuide
    }

    public static let pasteInstruction = "네이버 카페·블로그에서 붙여넣기(⌘V)하세요."

    public let outcome: Outcome
    public let title: String
    public let message: String
    public let details: [Detail]
    public let clipboardRevision: Int?
    public let recoveryAction: RecoveryAction?

    public var autoDismissInterval: TimeInterval? {
        switch outcome {
        case .success: 3.5
        case .partialSuccess: 8
        case .failure: nil
        }
    }

    public init(outcome: Outcome, title: String, message: String,
                details: [Detail] = [], clipboardRevision: Int? = nil,
                recoveryAction: RecoveryAction? = nil) {
        self.outcome = outcome
        self.title = title
        self.message = message
        self.details = details
        self.clipboardRevision = clipboardRevision
        self.recoveryAction = recoveryAction
    }

    public static func completed(_ result: ConversionResult? = nil, clipboardRevision: Int) -> Self {
        var details: [Detail] = []
        if let result {
            if result.unconvertedImageCount > 0 {
                details.append(Detail(title: "그림 \(result.unconvertedImageCount)개",
                    message: "카페·블로그에서 별도로 추가하세요."))
            }
            if result.hasUnrestoredHighlights {
                details.append(Detail(title: "형광펜 일부",
                    message: "붙여넣은 결과를 원본과 비교하세요."))
            }
            if result.hasDiagonal {
                details.append(Detail(title: "대각선", message: "변환된 표에서는 제외됩니다."))
            }
        }
        return Self(outcome: details.isEmpty ? .success : .partialSuccess,
            title: details.isEmpty ? "변환 완료" : "변환 완료(확인 필요)",
            message: Self.pasteInstruction + (details.isEmpty ? "" : "\n일부 내용은 원본과 다를 수 있습니다."),
            details: details, clipboardRevision: clipboardRevision)
    }

    public static func failed(_ error: any Error, clipboardRevision: Int) -> Self {
        let message: String
        let action: RecoveryAction
        var details: [Detail] = []
        switch error as? ConversionError {
        case .some(.noHTMLTable), .some(.notHangulTable), .some(.tableNotFound):
            message = "복사한 내용에서 한글 표를 찾지 못했습니다.\n한글에서 표를 포함해 다시 복사하세요."
            action = .usageGuide
        case .some(.invalidColor):
            message = "표의 글자색 또는 배경색을 읽지 못했습니다.\n한글에서 해당 색상을 다시 지정한 뒤 표를 복사해 주세요."
            action = .usageGuide
            details = [Detail(title: "오류 정보", message: error.localizedDescription)]
        case .some(.layoutTooComplex):
            message = "중첩되거나 병합된 셀 구조를 처리하지 못했습니다.\n표를 나누어 복사해 주세요. 복사한 원본은 유지됩니다."
            action = .usageGuide
        case .some(.clipboardChanged):
            message = "변환 중 다른 내용이 복사되어 작업을 멈췄습니다.\n변환할 표를 다시 복사해 주세요."
            action = .usageGuide
        case .some(.clipboardWriteFailed):
            message = "변환된 표를 저장하지 못했습니다.\n잠시 후 다시 변환해 주세요."
            action = .retry
        case .none:
            message = "예상하지 못한 오류가 발생했습니다.\n한글에서 표를 다시 복사한 뒤 변환해 주세요."
            action = .retry
            details = [Detail(title: "오류 정보", message: error.localizedDescription)]
        }
        return Self(outcome: .failure, title: "변환하지 못했습니다", message: message,
                    details: details, clipboardRevision: clipboardRevision, recoveryAction: action)
    }
}
