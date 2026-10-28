import XCTest
@testable import TableConverterCore
@testable import TableConverterMac

final class ConversionFeedbackTests: XCTestCase {
    private func result(images: Int = 0, highlights: Bool = false, diagonal: Bool = false) -> ConversionResult {
        ConversionResult(html: "<table></table>", plainText: "", hasDiagonal: diagonal,
            hasUnrestoredHighlights: highlights, unconvertedImageCount: images)
    }

    func testCleanConversionIsSuccessWithShortDismissTime() {
        let feedback = ConversionFeedback.completed(result(), clipboardRevision: 12)
        XCTAssertEqual(feedback.outcome, .success)
        XCTAssertEqual(feedback.title, "변환 완료")
        XCTAssertEqual(feedback.message, "네이버 카페·블로그에서 붙여넣기(⌘V)하세요.")
        XCTAssertEqual(feedback.autoDismissInterval, 3.5)
        XCTAssertTrue(feedback.details.isEmpty)
        XCTAssertEqual(feedback.clipboardRevision, 12)
        XCTAssertNil(feedback.recoveryAction)
        XCTAssertEqual(feedback, .completed(clipboardRevision: 12))
    }

    func testAllSevenLimitationCombinationsShareCopyAndKeepOnlyTheirDetails() {
        for mask in 1...7 {
            let images = mask & 1 != 0
            let highlights = mask & 2 != 0
            let diagonal = mask & 4 != 0
            let input = result(images: images ? 2 : 0, highlights: highlights, diagonal: diagonal)
            let feedback = ConversionFeedback.completed(input, clipboardRevision: 4)
            XCTAssertEqual(feedback.outcome, .partialSuccess)
            XCTAssertEqual(feedback.title, "변환 완료(확인 필요)")
            XCTAssertEqual(feedback.details.map(\.title),
                [(images, "그림 2개"), (highlights, "형광펜 일부"), (diagonal, "대각선")]
                    .filter { $0.0 }.map { $0.1 })
            XCTAssertEqual(feedback.autoDismissInterval, 8)
            XCTAssertEqual(feedback.message,
                "네이버 카페·블로그에서 붙여넣기(⌘V)하세요.\n일부 내용은 원본과 다를 수 있습니다.")
            XCTAssertNil(feedback.recoveryAction)
        }
    }

    func testCombinedLimitationsKeepActualImageCountAndAllDetails() {
        let feedback = ConversionFeedback.completed(result(images: 7, highlights: true, diagonal: true),
                                                    clipboardRevision: 9)
        XCTAssertEqual(feedback.details.map(\.title), ["그림 7개", "형광펜 일부", "대각선"])
        XCTAssertEqual(feedback.details.map(\.message), ["카페·블로그에서 별도로 추가하세요.",
            "붙여넣은 결과를 원본과 비교하세요.", "변환된 표에서는 제외됩니다."])
    }

    func testFailuresShareTitleAndOfferRecoveryForTheirCause() {
        let missingTable = [ConversionError.noHTMLTable, .notHangulTable, .tableNotFound]
        for error in missingTable + [.invalidColor("#zzzzzz"), .clipboardChanged, .clipboardWriteFailed, .layoutTooComplex] {
            let feedback = ConversionFeedback.failed(error, clipboardRevision: 25)
            XCTAssertEqual(feedback.outcome, .failure)
            XCTAssertEqual(feedback.title, "변환하지 못했습니다")
            XCTAssertNil(feedback.autoDismissInterval)
            XCTAssertEqual(feedback.recoveryAction, error == .clipboardWriteFailed ? .retry : .usageGuide)
            XCTAssertEqual(feedback.clipboardRevision, 25)
            if missingTable.contains(error) {
                XCTAssertEqual(feedback.message,
                    "복사한 내용에서 한글 표를 찾지 못했습니다.\n한글에서 표를 포함해 다시 복사하세요.")
            } else {
                switch error {
                case .invalidColor:
                    XCTAssertTrue(feedback.message.contains("색상"))
                    XCTAssertEqual(feedback.details.first?.message, error.localizedDescription)
                case .clipboardChanged:
                    XCTAssertTrue(feedback.message.contains("다른 내용이 복사"))
                case .clipboardWriteFailed:
                    XCTAssertTrue(feedback.message.contains("저장하지 못했습니다"))
                case .layoutTooComplex:
                    XCTAssertTrue(feedback.message.contains("복사한 원본은 유지됩니다"))
                default:
                    XCTFail("Unhandled error in this check")
                }
            }
        }
    }

    func testUnexpectedFailureKeepsDiagnosticDetailsAlongsideRetry() {
        let error = NSError(domain: "ConversionFeedbackTests", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "원인 확인용 오류"])
        let feedback = ConversionFeedback.failed(error, clipboardRevision: 25)
        XCTAssertEqual(feedback.title, "변환하지 못했습니다")
        XCTAssertEqual(feedback.message,
            "예상하지 못한 오류가 발생했습니다.\n한글에서 표를 다시 복사한 뒤 변환해 주세요.")
        XCTAssertEqual(feedback.details.first?.message, "원인 확인용 오류")
        XCTAssertEqual(feedback.recoveryAction, .retry)
    }

    func testSettingsErrorDoesNotOfferConversionRetry() {
        let feedback = ConversionFeedback(outcome: .failure,
            title: "단축키를 사용할 수 없습니다", message: "다른 조합을 선택해주세요.")
        XCTAssertNil(feedback.recoveryAction)
        XCTAssertNil(feedback.clipboardRevision)
    }
}
