import XCTest
@testable import DueProof

final class ProofIntelligenceTests: XCTestCase {
    func testFallbackProofAnalysisProducesCompletenessAndSummary() {
        let intelligence = ProofIntelligenceService.generateFallbackAnalysis(from: """
        NIKE
        Receipt
        Order #ABCD-1234
        Purchased 05/20/2026
        Total $140.00
        Return by 06/19/2026
        """)

        XCTAssertEqual(intelligence.merchant, "NIKE")
        XCTAssertEqual(intelligence.category, .returnItem)
        XCTAssertEqual(intelligence.valueAtRisk, 140)
        XCTAssertNotNil(intelligence.purchaseDate)
        XCTAssertNotNil(intelligence.deadline)
        XCTAssertTrue(intelligence.deadlineIsExplicit)
        XCTAssertEqual(intelligence.orderNumber, "ABCD-1234")
        XCTAssertGreaterThanOrEqual(intelligence.completeness.score, 0.8)
        XCTAssertTrue(intelligence.summary.localizedCaseInsensitiveContains("NIKE"))
    }

    func testProofItemRoundTripsIntelligenceData() {
        let intelligence = ProofIntelligence(
            merchant: "Target",
            category: .returnItem,
            valueAtRisk: 38.5,
            purchaseDate: Date(timeIntervalSince1970: 1_779_232_000),
            deadline: Date(timeIntervalSince1970: 1_781_824_000),
            deadlineIsExplicit: true,
            orderNumber: "TGT-12345",
            confidence: 0.84,
            warnings: [],
            summary: "Target return proof is ready.",
            completeness: ProofCompleteness(
                score: 1,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: true,
                hasDeadline: true,
                hasReadableText: true,
                missingFields: []
            )
        )

        let proof = ProofItem(
            type: .photo,
            displayName: "Receipt",
            extractedText: "Target total $38.50",
            intelligence: intelligence
        )

        XCTAssertNotNil(proof.intelligenceData)
        XCTAssertEqual(proof.intelligence?.summary, "Target return proof is ready.")
        XCTAssertEqual(proof.intelligence?.orderNumber, "TGT-12345")

        proof.intelligence = nil
        XCTAssertNil(proof.intelligenceData)
    }

    func testClaimSearchIntentMatchesNaturalLanguage() {
        let referenceDate = Date(timeIntervalSince1970: 1_779_232_000)
        let deadline = DateHelpers.calendar.date(byAdding: .day, value: 5, to: referenceDate)!
        let claim = Claim(
            title: "Receipt follow-up",
            category: .returnItem,
            valueAtRisk: 140,
            deadline: deadline,
            status: .active
        )
        let proof = ProofItem(
            type: .photo,
            displayName: "Nike receipt",
            extractedText: "NIKE Total $140 Return by 06/19/2026",
            intelligence: ProofIntelligence(
                merchant: "NIKE",
                category: .returnItem,
                valueAtRisk: 140,
                purchaseDate: referenceDate,
                deadline: deadline,
                deadlineIsExplicit: true,
                orderNumber: "ABCD-1234",
                confidence: 0.9,
                warnings: [],
                summary: "NIKE proof includes $140.00 and a deadline found in the proof.",
                completeness: ProofCompleteness(
                    score: 1,
                    hasMerchant: true,
                    hasValue: true,
                    hasPurchaseDate: true,
                    hasDeadline: true,
                    hasReadableText: true,
                    missingFields: []
                )
            ),
            claim: claim
        )
        claim.proofItemsList.append(proof)

        XCTAssertTrue(ClaimSearchIntent.parse("returns due this week nike").matches(claim, referenceDate: referenceDate))
        XCTAssertTrue(ClaimSearchIntent.parse("with proof over $100 ABCD-1234").matches(claim, referenceDate: referenceDate))
        XCTAssertFalse(ClaimSearchIntent.parse("missing proof").matches(claim, referenceDate: referenceDate))
        XCTAssertFalse(ClaimSearchIntent.parse("gift cards").matches(claim, referenceDate: referenceDate))
    }
}
