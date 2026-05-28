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

    func testICSExportEscapesAndFoldsUserText() throws {
        let claim = Claim(
            title: "Return\nInjected:BAD, semicolon; " + String(repeating: "LongTitle", count: 12),
            category: .returnItem,
            valueAtRisk: 25,
            deadline: Date(timeIntervalSince1970: 1_767_225_600)
        )

        let url = try CalendarExportService.shared.exportDeadline(for: claim)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let unfolded = contents.replacingOccurrences(of: "\r\n ", with: "")

        XCTAssertTrue(contents.contains("\r\n"))
        XCTAssertFalse(contents.contains("\nInjected:BAD"))
        XCTAssertTrue(unfolded.contains("SUMMARY:DueProof: Return\\nInjected:BAD\\, semicolon\\;"))
        XCTAssertTrue(contents.components(separatedBy: "\r\n").contains { $0.hasPrefix(" ") })
    }

    func testICSExportFoldsLongUnicodeLinesByByteLength() throws {
        let claim = Claim(
            title: String(repeating: "é", count: 80),
            category: .document,
            valueAtRisk: 0,
            deadline: Date(timeIntervalSince1970: 1_767_225_600)
        )

        let url = try CalendarExportService.shared.exportDeadline(for: claim)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let summaryLines = contents
            .components(separatedBy: "\r\n")
            .filter { $0.hasPrefix("SUMMARY:") || $0.hasPrefix(" ") }

        XCTAssertFalse(summaryLines.isEmpty)
        XCTAssertTrue(summaryLines.allSatisfy { $0.utf8.count <= 75 })
    }

    func testICSExportBoundsCorruptStoredTitle() throws {
        let claim = Claim(
            title: "Baseline",
            category: .document,
            valueAtRisk: 0,
            deadline: Date(timeIntervalSince1970: 1_767_225_600)
        )
        claim.title = String(repeating: "A", count: 5_000) + "\nInjected:BAD"

        let url = try CalendarExportService.shared.exportDeadline(for: claim)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let unfolded = contents.replacingOccurrences(of: "\r\n ", with: "")

        XCTAssertLessThan(contents.utf8.count, 1_500)
        XCTAssertTrue(unfolded.contains("SUMMARY:DueProof: \(String(repeating: "A", count: ClaimTextLimits.title))"))
        XCTAssertFalse(unfolded.contains("Injected:BAD"))
        XCTAssertTrue(contents.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
    }

    func testICSExportWithoutDeadlineThrows() {
        let claim = Claim(title: "No deadline", category: .giftCard, valueAtRisk: 25)
        XCTAssertThrowsError(try CalendarExportService.shared.exportDeadline(for: claim))
    }

    func testICSExportRejectsInvalidDeadline() {
        let claim = Claim(
            title: "Invalid deadline",
            category: .document,
            valueAtRisk: 0
        )
        claim.deadline = Date(timeIntervalSinceReferenceDate: .infinity)

        XCTAssertThrowsError(try CalendarExportService.shared.exportDeadline(for: claim)) { error in
            XCTAssertEqual(error as? CalendarExportError, .invalidDeadline)
        }
    }
}
