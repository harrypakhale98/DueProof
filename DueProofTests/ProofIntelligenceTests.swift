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

    func testFallbackProofAnalysisCapturesSerialAndBarcodeIdentifiers() {
        let intelligence = ProofIntelligenceService.generateFallbackAnalysis(
            from: """
            Apple
            Warranty receipt
            Serial No: C02Z1234LVDL
            Total $999.00
            Purchased 05/20/2026
            Barcode ean13: 0123456789012
            """,
            barcodeValues: ["0123456789012"]
        )

        XCTAssertEqual(intelligence.serialNumber, "C02Z1234LVDL")
        XCTAssertEqual(intelligence.barcodeValues, ["0123456789012"])
        XCTAssertEqual(intelligence.primaryIdentifier, "C02Z1234LVDL")
        XCTAssertTrue(intelligence.summary.contains("C02Z1234LVDL"))
    }

    func testOCRSearchableTextIncludesMachineReadableIdentifiers() {
        let result = OCRResult(
            text: "Receipt",
            barcodes: [
                OCRResult.RecognizedBarcode(value: "0123456789012", symbology: "ean13")
            ]
        )

        XCTAssertTrue(result.searchableText.contains("Receipt"))
        XCTAssertTrue(result.searchableText.contains("Barcode ean13: 0123456789012"))
        XCTAssertFalse(result.isEmpty)
    }

    func testOCRResultBoundsUntrustedTextBarcodesAndWarnings() {
        let result = OCRResult(
            text: String(repeating: "A", count: OCRResultLimits.text + 500),
            lines: (0..<(OCRResultLimits.maximumLines + 25)).map { index in
                OCRResult.RecognizedLine(
                    text: "\(index)-\(String(repeating: "L", count: OCRResultLimits.lineText + 50))",
                    confidence: 4
                )
            },
            barcodes: (0..<(OCRResultLimits.maximumBarcodes + 10)).map { index in
                OCRResult.RecognizedBarcode(
                    value: "CODE-\(index)-\(String(repeating: "B", count: OCRResultLimits.barcodeValue + 50))",
                    symbology: String(repeating: "S", count: OCRResultLimits.barcodeSymbology + 50),
                    confidence: .infinity
                )
            },
            averageConfidence: .infinity,
            warnings: (0..<(OCRResultLimits.maximumWarnings + 10)).map { index in
                "\(index)-\(String(repeating: "W", count: OCRResultLimits.warning + 50))"
            }
        )

        XCTAssertEqual(result.text.count, OCRResultLimits.text)
        XCTAssertEqual(result.lines.count, OCRResultLimits.maximumLines)
        XCTAssertEqual(result.lines.first?.text.count, OCRResultLimits.lineText)
        XCTAssertEqual(result.lines.first?.confidence, 1)
        XCTAssertEqual(result.barcodes.count, OCRResultLimits.maximumBarcodes)
        XCTAssertEqual(result.barcodes.first?.value.count, OCRResultLimits.barcodeValue)
        XCTAssertEqual(result.barcodes.first?.symbology.count, OCRResultLimits.barcodeSymbology)
        XCTAssertNil(result.barcodes.first?.confidence)
        XCTAssertEqual(result.averageConfidence, 1)
        XCTAssertEqual(result.warnings.count, OCRResultLimits.maximumWarnings)
        XCTAssertEqual(result.warnings.first?.count, OCRResultLimits.warning)
        XCTAssertLessThanOrEqual(result.searchableText.count, OCRResultLimits.text)
    }

    func testCompletenessDisplayPercentClampsInvalidScores() {
        XCTAssertEqual(
            ProofCompleteness(
                score: .infinity,
                hasMerchant: false,
                hasValue: false,
                hasPurchaseDate: false,
                hasDeadline: false,
                hasReadableText: false,
                missingFields: []
            ).displayPercent,
            "0%"
        )
        XCTAssertEqual(
            ProofCompleteness(
                score: 1.4,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: true,
                hasDeadline: true,
                hasReadableText: true,
                missingFields: []
            ).displayPercent,
            "100%"
        )
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

    func testProofItemInitializerNormalizesUserControlledFields() {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let proof = ProofItem(
            type: .note,
            localFileName: "../private.txt",
            syncedFileData: Data(repeating: 1, count: FileStorageService.maximumProofFileBytes + 1),
            displayName: "   ",
            extractedText: String(repeating: "E", count: ProofItemTextLimits.extractedText + 50),
            intelligence: ProofIntelligence(
                merchant: String(repeating: "M", count: ClaimTextLimits.merchant + 50),
                category: .rebate,
                valueAtRisk: -10,
                purchaseDate: invalidDate,
                deadline: invalidDate,
                deadlineIsExplicit: true,
                orderNumber: String(repeating: "O", count: ClaimTextLimits.reference + 50),
                serialNumber: nil,
                barcodeValues: [String(repeating: "B", count: ClaimTextLimits.reference + 50)],
                confidence: 9,
                warnings: [String(repeating: "W", count: 300)],
                summary: "   ",
                completeness: ProofCompleteness(
                    score: -4,
                    hasMerchant: true,
                    hasValue: true,
                    hasPurchaseDate: false,
                    hasDeadline: false,
                    hasReadableText: true,
                    missingFields: [String(repeating: "F", count: 200)]
                )
            ),
            createdAt: invalidDate
        )

        XCTAssertNil(proof.localFileName)
        XCTAssertNil(proof.syncedFileData)
        XCTAssertEqual(proof.displayName, "Note")
        XCTAssertEqual(proof.extractedText?.count, ProofItemTextLimits.extractedText)
        XCTAssertEqual(proof.intelligence?.merchant?.count, ClaimTextLimits.merchant)
        XCTAssertNil(proof.intelligence?.valueAtRisk)
        XCTAssertNil(proof.intelligence?.purchaseDate)
        XCTAssertNil(proof.intelligence?.deadline)
        XCTAssertFalse(proof.intelligence?.deadlineIsExplicit ?? true)
        XCTAssertEqual(proof.intelligence?.orderNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(proof.intelligence?.barcodeValues.first?.count, ClaimTextLimits.reference)
        XCTAssertEqual(proof.intelligence?.confidence, 1)
        XCTAssertEqual(proof.intelligence?.summary, "Proof needs review.")
        XCTAssertEqual(proof.intelligence?.completeness.score, 0.4)
        XCTAssertEqual(proof.intelligence?.completeness.hasMerchant, true)
        XCTAssertEqual(proof.intelligence?.completeness.hasValue, false)
        XCTAssertEqual(proof.intelligence?.completeness.hasPurchaseDate, false)
        XCTAssertEqual(proof.intelligence?.completeness.hasDeadline, false)
        XCTAssertTrue(proof.intelligence?.completeness.missingFields.contains("value") == true)
        XCTAssertTrue(proof.createdAt.timeIntervalSinceReferenceDate.isFinite)
    }

    func testProofItemNormalizeStoredFieldsRepairsLoadedCorruptProof() throws {
        let proof = ProofItem(type: .document, localFileName: "receipt.pdf", displayName: "Receipt")
        proof.localFileName = "nested/receipt.pdf"
        proof.syncedFileData = Data(repeating: 1, count: FileStorageService.maximumProofFileBytes + 1)
        proof.displayName = String(repeating: "D", count: ProofItemTextLimits.displayName + 50)
        proof.extractedText = String(repeating: "T", count: ProofItemTextLimits.extractedText + 50)
        proof.createdAt = Date(timeIntervalSinceReferenceDate: .infinity)

        let corruptIntelligence = ProofIntelligence(
            merchant: String(repeating: "Merchant", count: 40),
            category: .warranty,
            valueAtRisk: -50,
            purchaseDate: nil,
            deadline: nil,
            deadlineIsExplicit: true,
            orderNumber: String(repeating: "O", count: ClaimTextLimits.reference + 50),
            serialNumber: String(repeating: "S", count: ClaimTextLimits.reference + 50),
            barcodeValues: [
                "  \(String(repeating: "B", count: ClaimTextLimits.reference + 50))  ",
                "  \(String(repeating: "B", count: ClaimTextLimits.reference + 50))  "
            ],
            confidence: 2,
            warnings: [
                "  \(String(repeating: "W", count: 300))  ",
                "  \(String(repeating: "W", count: 300))  "
            ],
            summary: String(repeating: "Summary", count: 120),
            completeness: ProofCompleteness(
                score: 3,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: false,
                hasDeadline: false,
                hasReadableText: true,
                missingFields: [
                    "  \(String(repeating: "field", count: 30))  "
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        proof.intelligenceData = try encoder.encode(corruptIntelligence)

        XCTAssertTrue(proof.normalizeStoredFields())

        XCTAssertNil(proof.localFileName)
        XCTAssertNil(proof.syncedFileData)
        XCTAssertEqual(proof.displayName.count, ProofItemTextLimits.displayName)
        XCTAssertEqual(proof.extractedText?.count, ProofItemTextLimits.extractedText)
        XCTAssertEqual(proof.intelligence?.merchant?.count, ClaimTextLimits.merchant)
        XCTAssertNil(proof.intelligence?.valueAtRisk)
        XCTAssertEqual(proof.intelligence?.deadlineIsExplicit, false)
        XCTAssertEqual(proof.intelligence?.orderNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(proof.intelligence?.serialNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(proof.intelligence?.barcodeValues.count, 1)
        XCTAssertEqual(proof.intelligence?.barcodeValues.first?.count, ClaimTextLimits.reference)
        XCTAssertEqual(proof.intelligence?.confidence, 1)
        XCTAssertEqual(proof.intelligence?.warnings.count, 1)
        XCTAssertEqual(proof.intelligence?.warnings.first?.count, 160)
        XCTAssertEqual(proof.intelligence?.summary.count, 500)
        XCTAssertEqual(proof.intelligence?.completeness.score, 0.4)
        XCTAssertEqual(proof.intelligence?.completeness.hasValue, false)
        XCTAssertTrue(proof.intelligence?.completeness.missingFields.contains("value") == true)
        XCTAssertFalse(proof.intelligence?.completeness.missingFields.contains { $0.hasPrefix("field") } ?? true)
        XCTAssertTrue(proof.createdAt.timeIntervalSinceReferenceDate.isFinite)
    }

    func testProofIntelligenceNormalizationDropsInvalidDates() {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let intelligence = ProofIntelligence(
            merchant: "Store",
            category: .rebate,
            valueAtRisk: 10,
            purchaseDate: invalidDate,
            deadline: invalidDate,
            deadlineIsExplicit: true,
            orderNumber: nil,
            confidence: 0.8,
            warnings: [],
            summary: "Proof.",
            completeness: ProofCompleteness(
                score: 1,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: true,
                hasDeadline: true,
                hasReadableText: true,
                missingFields: []
            )
        ).normalizedForStorage()

        XCTAssertNil(intelligence.purchaseDate)
        XCTAssertNil(intelligence.deadline)
        XCTAssertFalse(intelligence.deadlineIsExplicit)
        XCTAssertFalse(intelligence.completeness.hasPurchaseDate)
        XCTAssertFalse(intelligence.completeness.hasDeadline)
    }

    func testProofIntelligenceRecomputesCompletenessFromNormalizedFields() {
        let intelligence = ProofIntelligence(
            merchant: "   ",
            category: .rebate,
            valueAtRisk: -10,
            purchaseDate: nil,
            deadline: nil,
            deadlineIsExplicit: false,
            orderNumber: nil,
            confidence: 0.8,
            warnings: [],
            summary: "Proof.",
            completeness: ProofCompleteness(
                score: 1,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: true,
                hasDeadline: true,
                hasReadableText: true,
                missingFields: []
            )
        ).normalizedForStorage()

        XCTAssertEqual(intelligence.completeness.score, 0.2)
        XCTAssertFalse(intelligence.completeness.hasMerchant)
        XCTAssertFalse(intelligence.completeness.hasValue)
        XCTAssertFalse(intelligence.completeness.hasPurchaseDate)
        XCTAssertFalse(intelligence.completeness.hasDeadline)
        XCTAssertTrue(intelligence.completeness.hasReadableText)
        XCTAssertTrue(intelligence.completeness.missingFields.contains("merchant"))
        XCTAssertTrue(intelligence.completeness.missingFields.contains("value"))
        XCTAssertTrue(intelligence.completeness.missingFields.contains("deadline"))
    }

    func testProofIntelligenceDecodingToleratesMalformedStoredMetadata() throws {
        let json = """
        {
          "merchant": "  Example Store  ",
          "category": "notARealCategory",
          "valueAtRisk": "not-a-number",
          "purchaseDate": "not-a-date",
          "deadline": "also-not-a-date",
          "deadlineIsExplicit": "yes",
          "orderNumber": "ORDER-123",
          "serialNumber": "SERIAL-456",
          "barcodeValues": "not-an-array",
          "confidence": "high",
          "warnings": "not-an-array",
          "summary": "   ",
          "completeness": {
            "score": "not-a-score",
            "hasMerchant": "yes",
            "hasValue": "no",
            "hasPurchaseDate": "no",
            "hasDeadline": "no",
            "hasReadableText": "yes",
            "missingFields": "not-an-array"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let intelligence = try decoder
            .decode(ProofIntelligence.self, from: Data(json.utf8))
            .normalizedForStorage()

        XCTAssertEqual(intelligence.merchant, "Example Store")
        XCTAssertNil(intelligence.category)
        XCTAssertNil(intelligence.valueAtRisk)
        XCTAssertNil(intelligence.purchaseDate)
        XCTAssertNil(intelligence.deadline)
        XCTAssertFalse(intelligence.deadlineIsExplicit)
        XCTAssertEqual(intelligence.orderNumber, "ORDER-123")
        XCTAssertEqual(intelligence.serialNumber, "SERIAL-456")
        XCTAssertTrue(intelligence.barcodeValues.isEmpty)
        XCTAssertEqual(intelligence.confidence, 0)
        XCTAssertTrue(intelligence.warnings.isEmpty)
        XCTAssertEqual(intelligence.summary, "Proof needs review.")
        XCTAssertEqual(intelligence.completeness.score, 0.2)
        XCTAssertTrue(intelligence.completeness.hasMerchant)
        XCTAssertFalse(intelligence.completeness.hasValue)
        XCTAssertFalse(intelligence.completeness.hasPurchaseDate)
        XCTAssertFalse(intelligence.completeness.hasDeadline)
        XCTAssertFalse(intelligence.completeness.hasReadableText)
        XCTAssertTrue(intelligence.completeness.missingFields.contains("value"))
        XCTAssertTrue(intelligence.completeness.missingFields.contains("readable text"))
    }

    func testProofIntelligenceEncodingSanitizesCorruptMetadata() throws {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let intelligence = ProofIntelligence(
            merchant: "   ",
            category: .warranty,
            valueAtRisk: .infinity,
            purchaseDate: invalidDate,
            deadline: invalidDate,
            deadlineIsExplicit: true,
            orderNumber: String(repeating: "O", count: ClaimTextLimits.reference + 50),
            serialNumber: String(repeating: "S", count: ClaimTextLimits.reference + 50),
            barcodeValues: [
                String(repeating: "B", count: ClaimTextLimits.reference + 50),
                String(repeating: "B", count: ClaimTextLimits.reference + 50)
            ],
            confidence: .infinity,
            warnings: [String(repeating: "W", count: 300)],
            summary: "   ",
            completeness: ProofCompleteness(
                score: .infinity,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: true,
                hasDeadline: true,
                hasReadableText: true,
                missingFields: [String(repeating: "F", count: 200)]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            ProofIntelligence.self,
            from: try encoder.encode(intelligence)
        )

        XCTAssertNil(decoded.merchant)
        XCTAssertEqual(decoded.category, .warranty)
        XCTAssertNil(decoded.valueAtRisk)
        XCTAssertNil(decoded.purchaseDate)
        XCTAssertNil(decoded.deadline)
        XCTAssertFalse(decoded.deadlineIsExplicit)
        XCTAssertEqual(decoded.orderNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(decoded.serialNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(decoded.barcodeValues.count, 1)
        XCTAssertEqual(decoded.barcodeValues.first?.count, ClaimTextLimits.reference)
        XCTAssertEqual(decoded.confidence, 0)
        XCTAssertEqual(decoded.warnings.count, 1)
        XCTAssertEqual(decoded.warnings.first?.count, 160)
        XCTAssertEqual(decoded.summary, "Proof needs review.")
        XCTAssertEqual(decoded.completeness.score, 0.2)
        XCTAssertFalse(decoded.completeness.hasMerchant)
        XCTAssertFalse(decoded.completeness.hasValue)
        XCTAssertFalse(decoded.completeness.hasPurchaseDate)
        XCTAssertFalse(decoded.completeness.hasDeadline)
        XCTAssertEqual(decoded.completeness.missingFields, ["merchant", "value", "purchase date", "deadline"])
    }

    func testProofIntelligenceRejectsAbsurdFiniteMoneyValues() throws {
        let intelligence = ProofIntelligence(
            merchant: "Store",
            category: .rebate,
            valueAtRisk: CurrencyFormatter.maximumSupportedAmount + 1,
            purchaseDate: nil,
            deadline: nil,
            deadlineIsExplicit: false,
            orderNumber: nil,
            confidence: 0.9,
            warnings: [],
            summary: "Store proof",
            completeness: ProofCompleteness(
                score: 1,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: false,
                hasDeadline: false,
                hasReadableText: true,
                missingFields: []
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ProofIntelligence.self, from: try encoder.encode(intelligence))

        XCTAssertNil(decoded.valueAtRisk)
        XCTAssertFalse(decoded.completeness.hasValue)
        XCTAssertTrue(decoded.completeness.missingFields.contains("value"))
    }

    func testFallbackProofAnalysisRejectsAbsurdFiniteMoneyValues() {
        let intelligence = ProofIntelligenceService.generateFallbackAnalysis(
            from: "STORE\nReceipt\nTotal $1,000,000,000.00"
        )

        XCTAssertNil(intelligence.valueAtRisk)
        XCTAssertFalse(intelligence.completeness.hasValue)
        XCTAssertTrue(intelligence.completeness.missingFields.contains("value"))
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
                serialNumber: "SN-123456",
                barcodeValues: ["0123456789012"],
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
        XCTAssertTrue(ClaimSearchIntent.parse("SN-123456").matches(claim, referenceDate: referenceDate))
        XCTAssertTrue(ClaimSearchIntent.parse("0123456789012").matches(claim, referenceDate: referenceDate))
        XCTAssertFalse(ClaimSearchIntent.parse("missing proof").matches(claim, referenceDate: referenceDate))
        XCTAssertFalse(ClaimSearchIntent.parse("gift cards").matches(claim, referenceDate: referenceDate))
    }
}
