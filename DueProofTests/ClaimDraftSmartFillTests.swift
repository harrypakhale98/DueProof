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

    func testOCRServiceHandlesMissingLocalFileGracefully() async {
        let missingURL = URL(fileURLWithPath: "/tmp/dueproof-missing-proof-image.jpg")
        let result = await OCRService.shared.recognizeText(at: missingURL)

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
