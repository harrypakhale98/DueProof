import UIKit
import XCTest
@testable import DueProof

final class ClaimDraftSmartFillTests: XCTestCase {
    func testFallbackParserExtractsObviousTotalAmount() {
        let draft = ClaimDraftGenerator.generateFallbackDraft(from: """
        NIKE
        Receipt
        Subtotal $130.00
        Tax $10.00
        Total $140.00
        """)

        XCTAssertEqual(draft.valueAtRisk, 140)
        XCTAssertEqual(draft.merchant, "NIKE")
        XCTAssertNil(draft.notes)
    }

    func testFallbackParserRejectsNonFiniteTotalAmount() {
        let hugeAmount = String(repeating: "9", count: 400) + ".00"
        let draft = ClaimDraftGenerator.generateFallbackDraft(from: "NIKE\nReceipt\nTotal $\(hugeAmount)")

        XCTAssertNil(draft.valueAtRisk)
    }

    func testFallbackParserRejectsAbsurdFiniteTotalAmount() {
        let draft = ClaimDraftGenerator.generateFallbackDraft(
            from: "NIKE\nReceipt\nTotal $1,000,000,000.00"
        )

        XCTAssertNil(draft.valueAtRisk)
    }

    func testFallbackParserExtractsObviousDate() {
        let draft = ClaimDraftGenerator.generateFallbackDraft(from: """
        TARGET
        Purchased 05/20/2026
        Total $38.50
        """)

        XCTAssertNotNil(draft.purchaseDate)
        XCTAssertEqual(draft.valueAtRisk, 38.5)
    }

    func testGiftCardWithoutExplicitExpirationDoesNotKeepDeadline() {
        let proposedDeadline = DateHelpers.calendar.date(byAdding: .day, value: 30, to: Date())!
        let draft = ClaimDraft(
            title: "Target gift card",
            category: .giftCard,
            merchant: "Target",
            valueAtRisk: 38.5,
            suggestedDeadline: proposedDeadline,
            confidence: 0.8
        )

        let validated = ClaimDraftValidator().validate(draft, sourceText: "Target Gift Card Balance $38.50")

        XCTAssertNil(validated.suggestedDeadline)
        XCTAssertTrue(validated.warnings.contains("Gift cards only get an expiration date when the proof clearly shows one."))
        XCTAssertTrue(validated.warnings.contains(ClaimDraftValidator.reviewWarning))
    }

    func testReturnDeadlineInferredFromPurchaseDateGetsWarning() {
        let purchaseDate = Date(timeIntervalSince1970: 1_767_225_600)
        let deadline = DateHelpers.calendar.date(byAdding: .day, value: 30, to: purchaseDate)!
        let draft = ClaimDraft(
            title: "Nike return",
            category: .returnItem,
            merchant: "Nike",
            valueAtRisk: 140,
            purchaseDate: purchaseDate,
            suggestedDeadline: deadline,
            confidence: 0.8
        )

        let validated = ClaimDraftValidator().validate(draft, sourceText: "Nike Receipt Total $140.00")

        XCTAssertEqual(validated.suggestedDeadline, deadline)
        XCTAssertTrue(validated.warnings.contains("Return deadline is suggested from the purchase date. Confirm the merchant policy before saving."))
        XCTAssertTrue(validated.warnings.contains(ClaimDraftValidator.reviewWarning))
    }

    func testFallbackStillWorksWhenOnDeviceIntelligenceIsNotPreferred() async {
        let generator = ClaimDraftGenerator(preferOnDeviceIntelligence: false)
        let result = OCRResult(text: """
        APPLE
        Receipt
        Total $99.00
        05/20/2026
        """)

        let draft = await generator.generate(from: result)

        XCTAssertEqual(draft.valueAtRisk, 99)
        XCTAssertEqual(draft.category, .returnItem)
        XCTAssertTrue(draft.warnings.contains(ClaimDraftValidator.reviewWarning))
    }

    func testSubscriptionReceiptDateDoesNotBecomeDeadline() async {
        let generator = ClaimDraftGenerator(preferOnDeviceIntelligence: false)
        let result = OCRResult(text: """
        STREAMCO
        Subscription receipt
        05/20/2026
        Total $12.99
        """)

        let draft = await generator.generate(from: result)

        XCTAssertEqual(draft.category, .subscription)
        XCTAssertNil(draft.suggestedDeadline)
    }

    func testReimbursementSuggestsSubmissionDeadlineFromPurchaseDate() async {
        let generator = ClaimDraftGenerator(preferOnDeviceIntelligence: false)
        let result = OCRResult(text: """
        FSA CLAIM FORM
        Purchased 05/20/2026
        Total $88.00
        """)

        let draft = await generator.generate(from: result)

        XCTAssertEqual(draft.category, .reimbursement)
        XCTAssertNotNil(draft.suggestedDeadline)
        XCTAssertTrue(draft.warnings.contains("Claim deadline is suggested from the purchase date. Confirm the submission window before saving."))
    }

    func testDraftValidatorNormalizesAIControlledFields() {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let validDeadline = Date(timeIntervalSince1970: 1_767_225_600)
        let lateReminder = validDeadline.addingTimeInterval(60 * 60)
        let draft = ClaimDraft(
            title: String(repeating: "T", count: ClaimTextLimits.title + 50),
            category: .other,
            merchant: String(repeating: "M", count: ClaimTextLimits.merchant + 50),
            valueAtRisk: .infinity,
            purchaseDate: invalidDate,
            suggestedDeadline: validDeadline,
            reminderDate: lateReminder,
            notes: String(repeating: "N", count: ClaimTextLimits.notes + 50),
            confidence: .nan,
            warnings: (0..<(OCRResultLimits.maximumWarnings + 10)).map { index in
                "\(index)-\(String(repeating: "W", count: 300))"
            },
            sourceSummary: String(repeating: "S", count: 1_000)
        )

        let validated = ClaimDraftValidator().validate(draft, sourceText: String(repeating: "x", count: OCRResultLimits.text + 500))

        XCTAssertEqual(validated.title?.count, ClaimTextLimits.title)
        XCTAssertEqual(validated.merchant?.count, ClaimTextLimits.merchant)
        XCTAssertNil(validated.valueAtRisk)
        XCTAssertNil(validated.purchaseDate)
        XCTAssertEqual(validated.suggestedDeadline, validDeadline)
        XCTAssertNil(validated.reminderDate)
        XCTAssertEqual(validated.notes?.count, ClaimTextLimits.notes)
        XCTAssertEqual(validated.confidence, 0)
        XCTAssertNil(validated.category)
        XCTAssertLessThanOrEqual(validated.warnings.count, OCRResultLimits.maximumWarnings)
        XCTAssertTrue(validated.warnings.contains(ClaimDraftValidator.reviewWarning))
        XCTAssertTrue(validated.warnings.contains("Only a few details looked reliable, so some fields were left blank."))
        XCTAssertEqual(validated.sourceSummary?.count, 500)
    }

    func testDraftValidatorRejectsAbsurdFiniteMoneyValues() {
        let draft = ClaimDraft(
            title: "Inflated claim",
            category: .rebate,
            merchant: "Store",
            valueAtRisk: CurrencyFormatter.maximumSupportedAmount + 1,
            confidence: 0.9
        )

        let validated = ClaimDraftValidator().validate(draft, sourceText: "Store rebate")

        XCTAssertNil(validated.valueAtRisk)
        XCTAssertTrue(validated.warnings.contains(ClaimDraftValidator.reviewWarning))
    }

    func testOCRServiceHandlesMissingLocalFileGracefully() async {
        let missingURL = URL(fileURLWithPath: "/tmp/dueproof-missing-proof-image.jpg")
        let result = await OCRService.shared.recognizeText(at: missingURL)

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testOCRServiceRejectsOversizedLocalFilesBeforeDecode() async throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1)
            .write(to: imageURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let result = await OCRService.shared.recognizeText(at: imageURL)

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)

        let documentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data(repeating: 0x41, count: FileStorageService.maximumProofFileBytes + 1)
            .write(to: documentURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: documentURL) }

        let searchableText = await OCRService.shared.searchableText(at: documentURL, type: .document)
        XCTAssertNil(searchableText)
    }

    func testOCRServiceCapsPDFSearchableTextExtraction() async throws {
        let documentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: documentURL) }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: documentURL) { context in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10)
            ]

            for page in 0..<20 {
                context.beginPage()
                let text = String(repeating: "Evidence page \(page) with proof details. ", count: 120)
                text.draw(
                    in: CGRect(x: 24, y: 24, width: 564, height: 744),
                    withAttributes: attributes
                )
            }
        }

        let extractedText = await OCRService.shared.searchableText(at: documentURL, type: .document)
        let searchableText = try XCTUnwrap(extractedText)

        XCTAssertLessThanOrEqual(searchableText.count, OCRResultLimits.text)
        XCTAssertTrue(searchableText.contains("Evidence page"))
    }

    func testOCRImagePreparationDownsamplesLargeImageData() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3_200, height: 1_600)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_200, height: 1_600))
        }
        let data = try XCTUnwrap(image.pngData())
        let preparedImage = try XCTUnwrap(OCRService.shared.preparedImage(from: data))

        XCTAssertLessThanOrEqual(max(preparedImage.size.width, preparedImage.size.height), 2_400)
        XCTAssertNil(OCRService.shared.preparedImage(from: data, maxPixelSize: 0))
        let cappedImage = try XCTUnwrap(OCRService.shared.preparedImage(from: data, maxPixelSize: 10_000))
        XCTAssertLessThanOrEqual(
            max(cappedImage.size.width, cappedImage.size.height),
            CGFloat(OCRService.maximumPreparedImagePixelSize)
        )
    }
}
