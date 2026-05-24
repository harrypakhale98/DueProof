import XCTest
@testable import DueProof

final class DashboardMetricsTests: XCTestCase {
    func testDashboardMetricsMatchReleaseRules() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let futureDeadline = DateHelpers.calendar.date(byAdding: .day, value: 20, to: referenceDate)!
        let urgentDeadline = DateHelpers.calendar.date(byAdding: .day, value: 3, to: referenceDate)!
        let overdueDeadline = DateHelpers.calendar.date(byAdding: .day, value: -1, to: referenceDate)!

        let active = Claim(title: "Active", category: .returnItem, valueAtRisk: 100, deadline: futureDeadline)
        let urgent = Claim(title: "Urgent", category: .subscription, valueAtRisk: 50, deadline: urgentDeadline)
        let overdue = Claim(title: "Overdue", category: .returnItem, valueAtRisk: 25, deadline: overdueDeadline)
        let noDeadline = Claim(title: "No deadline", category: .giftCard, valueAtRisk: 10)
        let recovered = Claim(title: "Recovered", category: .rebate, valueAtRisk: 80, status: .recovered, recoveredValue: 75)
        let used = Claim(title: "Used", category: .warranty, valueAtRisk: 0, status: .used)

        let metrics = DashboardMetrics(
            claims: [active, urgent, overdue, noDeadline, recovered, used],
            referenceDate: referenceDate
        )

        XCTAssertEqual(metrics.moneyAtRisk, 185)
        XCTAssertEqual(metrics.recoveredValue, 75)
        XCTAssertEqual(metrics.urgentCount, 1)
        XCTAssertEqual(metrics.activeCount, 4)
        XCTAssertEqual(metrics.overdueCount, 1)
        XCTAssertEqual(metrics.prooflessOpenCount, 4)
        XCTAssertEqual(metrics.nextActionClaim?.title, "Overdue")
        XCTAssertEqual(metrics.expiringSoonClaims.map(\.title), ["Overdue", "Urgent", "Active"])
    }
}
