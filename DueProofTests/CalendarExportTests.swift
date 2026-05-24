import XCTest
@testable import DueProof

final class CalendarExportTests: XCTestCase {
    func testICSExportForClaimWithDeadline() throws {
        let claim = Claim(
            title: "Warranty deadline",
            category: .warranty,
            valueAtRisk: 0,
            deadline: Date(timeIntervalSince1970: 1_767_225_600)
        )

        let url = try CalendarExportService.shared.exportDeadline(for: claim)
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(contents.contains("SUMMARY:DueProof: Warranty deadline"))
        XCTAssertTrue(contents.contains("UID:\(claim.id.uuidString)@dueproof.local"))
    }

    func testICSExportWithoutDeadlineThrows() {
        let claim = Claim(title: "No deadline", category: .giftCard, valueAtRisk: 25)
        XCTAssertThrowsError(try CalendarExportService.shared.exportDeadline(for: claim))
    }
}
