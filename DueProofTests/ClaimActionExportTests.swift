import XCTest
@testable import DueProof

@MainActor
final class ClaimActionExportTests: XCTestCase {
    func testActionPlanPrioritizesProofAndWarrantySteps() {
        let claim = Claim(
            title: "Laptop repair",
            category: .warranty,
            merchant: "Apple",
            valueAtRisk: 499,
            deadline: DateHelpers.calendar.date(byAdding: .day, value: 45, to: Date()),
            referenceNumber: "APL-SN-1234",
            policySummary: "AppleCare coverage through the deadline.",
            actionURLString: "https://support.apple.com"
        )

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertEqual(plan.headline, "Warranty claim ready")
        XCTAssertTrue(plan.nextStep.contains("Attach proof"))
        XCTAssertTrue(plan.checklist.contains("Attach proof before sending the claim."))
        XCTAssertTrue(plan.checklist.contains("Gather purchase proof, serial number, and product photos."))
        XCTAssertTrue(plan.checklist.contains("Keep this reference ready: APL-SN-1234."))
        XCTAssertTrue(plan.checklist.contains("Review the saved policy note before acting."))
        XCTAssertTrue(plan.checklist.contains("Use the saved action link for support, cancellation, or submission."))
        XCTAssertTrue(plan.messageSubject.contains("Apple Warranty"))
        XCTAssertTrue(plan.messageBody.contains("Reference: APL-SN-1234"))
        XCTAssertTrue(plan.messageBody.contains("Action link: https://support.apple.com"))
        XCTAssertTrue(plan.messageBody.contains("Value at risk:"))
        XCTAssertTrue(plan.messageBody.contains("499"))
    }

    func testActionPlanDoesNotInventDeadlineWhenProofIsAttached() {
        let claim = Claim(
            title: "Gift card balance",
            category: .giftCard,
            valueAtRisk: 25
        )
        let proof = ProofItem(type: .note, displayName: "Balance note", claim: claim)
        claim.proofItemsList = [proof]

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertTrue(plan.nextStep.contains("Confirm the deadline"))
        XCTAssertTrue(plan.nextStep.contains("1 proof item attached"))
        XCTAssertFalse(plan.nextStep.contains("No deadline"))
        XCTAssertFalse(plan.nextStep.contains("act before"))
    }

    func testActionPlanDoesNotSayBeforeDeadlineWhenDeadlineIsMissing() {
        let claim = Claim(
            title: "Paper rebate",
            category: .rebate,
            valueAtRisk: 40
        )

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertTrue(plan.nextStep.contains("Set a deadline"))
        XCTAssertTrue(plan.nextStep.contains("attach proof"))
        XCTAssertFalse(plan.nextStep.contains("before the deadline"))
        XCTAssertFalse(plan.nextStep.contains("No deadline"))
    }

    func testCSVReportEscapesCommaQuotesAndNewlines() throws {
        let claim = Claim(
            title: "Return, quoted \"bag\"",
            category: .returnItem,
            merchant: "Store",
            valueAtRisk: 35.5,
            referenceNumber: "RET-35",
            policySummary: "Bring receipt, tags, and original packaging.",
            actionURLString: "https://store.example/returns",
            notes: "Line 1\nLine 2"
        )

        let url = try ClaimReportExportService.shared.exportCSV(claims: [claim])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("Title,Category,Merchant,Status"))
        XCTAssertTrue(csv.contains("Reference,Policy Summary,Action URL"))
        XCTAssertTrue(csv.contains("RET-35"))
        XCTAssertTrue(csv.contains("https://store.example/returns"))
        XCTAssertTrue(csv.contains("\"Return, quoted \"\"bag\"\"\""))
        XCTAssertTrue(csv.contains("\"Line 1\nLine 2\""))
    }

    func testCSVReportNeutralizesFormulaStyleCells() throws {
        let claim = Claim(
            title: "=HYPERLINK(\"https://example.com\")",
            category: .returnItem,
            merchant: "@merchant",
            valueAtRisk: 35.5,
            referenceNumber: "+1-555-0000",
            notes: "-private note"
        )

        let url = try ClaimReportExportService.shared.exportCSV(claims: [claim])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"https://example.com\"\")\""))
        XCTAssertTrue(csv.contains("'@merchant"))
        XCTAssertTrue(csv.contains("'+1-555-0000"))
        XCTAssertTrue(csv.contains("'-private note"))
    }

    func testCSVReportKeepsOpenDeadlineWorkBeforeCompletedHistory() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let oldDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: -30, to: referenceDate))
        let urgentDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 2, to: Date()))
        let completed = Claim(
            title: "Completed old claim",
            category: .rebate,
            valueAtRisk: 50,
            deadline: oldDeadline,
            status: .recovered
        )
        let urgent = Claim(
            title: "Open urgent claim",
            category: .returnItem,
            valueAtRisk: 25,
            deadline: urgentDeadline
        )

        let url = try ClaimReportExportService.shared.exportCSV(claims: [completed, urgent])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertLessThan(
            try XCTUnwrap(csv.range(of: "Open urgent claim")?.lowerBound),
            try XCTUnwrap(csv.range(of: "Completed old claim")?.lowerBound)
        )
    }

    func testCSVReportBoundsCorruptStoredTextAndInvalidDates() throws {
        let longTitle = String(repeating: "T", count: 5_000)
        let longMerchant = String(repeating: "M", count: 5_000)
        let longPolicy = String(repeating: "P", count: 20_000)
        let longNotes = String(repeating: "N", count: 20_000)
        let claim = Claim(
            title: "Baseline claim",
            category: .rebate,
            valueAtRisk: 20
        )
        claim.title = longTitle
        claim.merchant = longMerchant
        claim.policySummary = longPolicy
        claim.notes = longNotes
        claim.deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.reminderDate = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.createdAt = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)

        let url = try ClaimReportExportService.shared.exportCSV(claims: [claim])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("Unknown date"))
        XCTAssertFalse(csv.contains(longTitle))
        XCTAssertFalse(csv.contains(longMerchant))
        XCTAssertFalse(csv.contains(longPolicy))
        XCTAssertFalse(csv.contains(longNotes))
        XCTAssertLessThan(csv.count, 7_000)
    }

    func testActionExportsUseOnlyValidatedActionLinks() throws {
        let claim = Claim(
            title: "Suspicious link",
            category: .returnItem,
            valueAtRisk: 20,
            actionURLString: "javascript:alert(1)"
        )

        let plan = ClaimActionPlanService.shared.plan(for: claim)
        XCTAssertFalse(plan.checklist.contains("Use the saved action link for support, cancellation, or submission."))
        XCTAssertFalse(plan.messageBody.contains("javascript:alert"))

        let url = try ClaimReportExportService.shared.exportCSV(claims: [claim])
        let csv = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(csv.contains("javascript:alert"))
    }

    func testActionPlanDoesNotLeakCorruptMoneyOrOversizedProofReference() {
        let longIdentifier = String(repeating: "X", count: ClaimTextLimits.reference + 50)
        let claim = Claim(
            title: "Corrupt claim",
            category: .warranty,
            valueAtRisk: 10
        )
        claim.valueAtRisk = .infinity
        let proof = ProofItem(
            type: .note,
            displayName: "Warranty note",
            intelligence: ProofIntelligence(
                merchant: nil,
                category: nil,
                valueAtRisk: nil,
                purchaseDate: nil,
                deadline: nil,
                deadlineIsExplicit: false,
                orderNumber: longIdentifier,
                confidence: 1,
                warnings: [],
                summary: "Proof note.",
                completeness: ProofCompleteness(
                    score: 1,
                    hasMerchant: false,
                    hasValue: false,
                    hasPurchaseDate: false,
                    hasDeadline: false,
                    hasReadableText: true,
                    missingFields: []
                )
            ),
            claim: claim
        )
        claim.proofItemsList = [proof]

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertFalse(plan.checklist.contains { $0.hasPrefix("Confirm the value at risk:") })
        XCTAssertTrue(plan.checklist.contains { item in
            item == "Keep this reference ready: \(String(longIdentifier.prefix(ClaimTextLimits.reference)))."
        })
    }

    func testActionPlanBoundsCorruptStoredTextAndInvalidDates() throws {
        let longTitle = String(repeating: "T", count: 5_000)
        let longMerchant = String(repeating: "M", count: 5_000)
        let longPolicy = String(repeating: "P", count: 20_000)
        let claim = Claim(
            title: "Baseline claim",
            category: .rebate,
            valueAtRisk: 40
        )
        claim.title = longTitle
        claim.merchant = longMerchant
        claim.policySummary = longPolicy
        claim.deadline = Date(timeIntervalSinceReferenceDate: .infinity)

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertTrue(plan.nextStep.contains("Confirm the saved deadline"))
        XCTAssertTrue(plan.messageBody.contains("Deadline: Invalid deadline"))
        XCTAssertTrue(plan.checklist.contains("Confirm the deadline before relying on this claim."))
        XCTAssertFalse(plan.exportText.contains(longTitle))
        XCTAssertFalse(plan.exportText.contains(longMerchant))
        XCTAssertFalse(plan.exportText.contains(longPolicy))
        XCTAssertLessThan(plan.exportText.count, 7_000)

        let url = try ClaimActionPlanService.shared.exportMessage(for: claim)
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("Deadline: Invalid deadline"))
        XCTAssertLessThanOrEqual(url.lastPathComponent.count, 140)
    }

    func testActionPlanCollapsesStoredLineBreaksInInlineFields() {
        let claim = Claim(
            title: "Return\nInjected title",
            category: .returnItem,
            merchant: "Store\nInjected merchant",
            valueAtRisk: 20,
            referenceNumber: "REF\n123",
            policySummary: "Policy\nline"
        )

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertTrue(plan.messageSubject.contains("Store Injected merchant Return"))
        XCTAssertFalse(plan.messageSubject.contains("\n"))
        XCTAssertTrue(plan.messageBody.contains("Provider: Store Injected merchant"))
        XCTAssertTrue(plan.messageBody.contains("Reference: REF 123"))
        XCTAssertTrue(plan.messageBody.contains("Policy note: Policy line"))
        XCTAssertTrue(plan.checklist.contains("Keep this reference ready: REF 123."))
    }

    func testProofPacketExportCreatesPDF() throws {
        let claim = Claim(
            title: "Rebate packet",
            category: .rebate,
            merchant: "Appliance Store",
            valueAtRisk: 75,
            deadline: Date(timeIntervalSince1970: 1_767_225_600),
            notes: "Needs submission proof."
        )

        let url = try ProofPacketExportService.shared.exportPacket(for: claim)
        let data = try Data(contentsOf: url)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1_000)
    }

    func testProofPacketExportBoundsCorruptStoredTextAndDates() throws {
        let claim = Claim(
            title: "Baseline packet",
            category: .document,
            valueAtRisk: 25,
            deadline: Date(timeIntervalSince1970: 1_767_225_600)
        )
        claim.title = String(repeating: "T", count: 5_000)
        claim.merchant = String(repeating: "M", count: 5_000)
        claim.deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.reminderDate = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.policySummary = String(repeating: "P", count: 20_000)
        claim.notes = String(repeating: "N", count: 20_000)
        claim.createdAt = Date(timeIntervalSinceReferenceDate: .infinity)
        claim.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)

        let proof = ProofItem(type: .note, displayName: "Proof note", claim: claim)
        proof.displayName = String(repeating: "D", count: 5_000)
        proof.extractedText = String(repeating: "E", count: 20_000)
        proof.createdAt = Date(timeIntervalSinceReferenceDate: .infinity)
        proof.intelligence = ProofIntelligence(
            merchant: String(repeating: "M", count: 500),
            category: .document,
            valueAtRisk: .infinity,
            purchaseDate: nil,
            deadline: nil,
            deadlineIsExplicit: true,
            orderNumber: String(repeating: "O", count: 500),
            serialNumber: String(repeating: "S", count: 500),
            barcodeValues: [String(repeating: "B", count: 500)],
            confidence: .infinity,
            warnings: [String(repeating: "W", count: 500)],
            summary: String(repeating: "Summary", count: 500),
            completeness: ProofCompleteness(
                score: .infinity,
                hasMerchant: true,
                hasValue: true,
                hasPurchaseDate: false,
                hasDeadline: false,
                hasReadableText: true,
                missingFields: [String(repeating: "F", count: 500)]
            )
        )
        claim.proofItemsList = [proof]

        let url = try ProofPacketExportService.shared.exportPacket(for: claim)
        let data = try Data(contentsOf: url)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertLessThan(data.count, 250_000)
        XCTAssertLessThanOrEqual(url.lastPathComponent.count, 140)
    }

    func testClaimMessageExportCreatesTextFile() throws {
        let claim = Claim(
            title: "FSA reimbursement",
            category: .reimbursement,
            merchant: "Benefits Provider",
            valueAtRisk: 120
        )

        let url = try ClaimActionPlanService.shared.exportMessage(for: claim)
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("Message subject:"))
        XCTAssertTrue(text.contains("Benefits Provider Reimbursement"))
        XCTAssertTrue(text.contains("Checklist:"))
    }
}
