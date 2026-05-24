import XCTest
@testable import DueProof

final class ClaimLogicTests: XCTestCase {
    func testUrgentAndExpiredCalculations() {
        let urgentDeadline = DateHelpers.calendar.date(byAdding: .day, value: 3, to: Date())!
        let overdueDeadline = DateHelpers.calendar.date(byAdding: .day, value: -1, to: Date())!
        let noDeadline = Claim(title: "Gift card", category: .giftCard, valueAtRisk: 25)

        let urgentClaim = Claim(title: "Return", category: .returnItem, valueAtRisk: 100, deadline: urgentDeadline)
        let overdueClaim = Claim(title: "Overdue return", category: .returnItem, valueAtRisk: 60, deadline: overdueDeadline)
        let expiredClaim = Claim(title: "Expired return", category: .returnItem, valueAtRisk: 60, status: .expired)

        XCTAssertTrue(urgentClaim.isUrgent)
        XCTAssertFalse(overdueClaim.isUrgent)
        XCTAssertTrue(overdueClaim.isOverdue)
        XCTAssertFalse(overdueClaim.isExpired)
        XCTAssertEqual(overdueClaim.effectiveStatus, .overdue)
        XCTAssertEqual(overdueClaim.urgencyLabel, "Overdue by 1 day")
        XCTAssertTrue(expiredClaim.isExpired)
        XCTAssertFalse(noDeadline.isUrgent)
        XCTAssertFalse(noDeadline.isExpired)
        XCTAssertTrue(noDeadline.countsTowardMoneyAtRisk)
    }

    func testDaysUntilDeadline() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let futureDate = DateHelpers.calendar.date(byAdding: .day, value: 5, to: referenceDate)!
        let pastDate = DateHelpers.calendar.date(byAdding: .day, value: -2, to: referenceDate)!

        XCTAssertEqual(DateHelpers.daysUntil(futureDate, from: referenceDate), 5)
        XCTAssertEqual(DateHelpers.daysUntil(pastDate, from: referenceDate), -2)
    }

    func testCategoryReminderDefaultsProtectCommonDeadlineWindows() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let returnDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 30, to: referenceDate))
        let warrantyDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .year, value: 1, to: referenceDate))

        XCTAssertEqual(
            DateHelpers.daysUntil(try XCTUnwrap(DateHelpers.defaultReminderDate(for: .returnItem, deadline: returnDeadline, referenceDate: referenceDate)), from: referenceDate),
            23
        )
        XCTAssertEqual(
            DateHelpers.daysUntil(try XCTUnwrap(DateHelpers.defaultReminderDate(for: .warranty, deadline: warrantyDeadline, referenceDate: referenceDate)), from: referenceDate),
            335
        )
    }

    func testStatusTransitions() {
        let claim = Claim(title: "Rebate", category: .rebate, valueAtRisk: 42)

        claim.markRecovered()
        XCTAssertEqual(claim.status, .recovered)
        XCTAssertEqual(claim.recoveredValue, 42)
        XCTAssertNotNil(claim.completedAt)

        claim.status = .active
        claim.completedAt = nil
        claim.recoveredValue = 0
        claim.markUsed()
        XCTAssertEqual(claim.status, .used)
        XCTAssertNotNil(claim.completedAt)

        claim.status = .active
        claim.markExpired()
        XCTAssertEqual(claim.status, .expired)
    }

    @MainActor
    func testNotificationIdentifierIsStableAndClaimScoped() {
        let id = UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!

        XCTAssertEqual(
            NotificationService.reminderIdentifier(for: id),
            "dueproof.claim.8EED90D8-87E6-4F1F-B978-7CE78F8D9071"
        )
    }
}
