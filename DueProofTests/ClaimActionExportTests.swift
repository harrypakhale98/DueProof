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
            deadline: DateHelpers.calendar.date(byAdding: .day, value: 45, to: Date())
        )

        let plan = ClaimActionPlanService.shared.plan(for: claim)

        XCTAssertEqual(plan.headline, "Warranty claim ready")
        XCTAssertTrue(plan.nextStep.contains("Attach proof"))
        XCTAssertTrue(plan.checklist.contains("Attach proof before sending the claim."))
        XCTAssertTrue(plan.checklist.contains("Gather purchase proof, serial number, and product photos."))
        XCTAssertTrue(plan.messageSubject.contains("Apple Warranty"))
        XCTAssertTrue(plan.messageBody.contains("Value at risk:"))
        XCTAssertTrue(plan.messageBody.contains("499"))
    }

    func testCSVReportEscapesCommaQuotesAndNewlines() throws {
        let claim = Claim(
            title: "Return, quoted \"bag\"",
            category: .returnItem,
            merchant: "Store",
            valueAtRisk: 35.5,
            notes: "Line 1\nLine 2"
        )

        let url = try ClaimReportExportService.shared.exportCSV(claims: [claim])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("Title,Category,Merchant,Status"))
        XCTAssertTrue(csv.contains("\"Return, quoted \"\"bag\"\"\""))
        XCTAssertTrue(csv.contains("\"Line 1\nLine 2\""))
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
