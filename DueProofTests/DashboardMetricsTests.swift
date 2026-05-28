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

    func testDashboardMetricsIgnoreCorruptNonFiniteMoneyValues() {
        let corruptActive = Claim(title: "Corrupt active", category: .returnItem, valueAtRisk: .infinity)
        let validActive = Claim(title: "Valid active", category: .rebate, valueAtRisk: 25)
        let corruptRecovered = Claim(
            title: "Corrupt recovered",
            category: .warranty,
            valueAtRisk: 100,
            status: .recovered,
            recoveredValue: .nan
        )

        let metrics = DashboardMetrics(claims: [corruptActive, validActive, corruptRecovered])

        XCTAssertEqual(metrics.moneyAtRisk, 25)
        XCTAssertEqual(metrics.recoveredValue, 0)
        XCTAssertTrue(metrics.moneyAtRisk.isFinite)
        XCTAssertTrue(metrics.recoveredValue.isFinite)
    }

    func testDashboardMetricsClampAbsurdFiniteMoneyValues() {
        let inflatedActive = Claim(
            title: "Inflated active",
            category: .returnItem,
            valueAtRisk: CurrencyFormatter.maximumSupportedAmount + 500
        )
        let inflatedRecovered = Claim(
            title: "Inflated recovered",
            category: .rebate,
            valueAtRisk: CurrencyFormatter.maximumSupportedAmount + 500,
            status: .recovered,
            recoveredValue: CurrencyFormatter.maximumSupportedAmount + 500
        )

        let metrics = DashboardMetrics(claims: [inflatedActive, inflatedRecovered])

        XCTAssertEqual(metrics.moneyAtRisk, CurrencyFormatter.maximumSupportedAmount)
        XCTAssertEqual(metrics.recoveredValue, CurrencyFormatter.maximumSupportedAmount)
        XCTAssertTrue(metrics.moneyAtRisk.isFinite)
        XCTAssertTrue(metrics.recoveredValue.isFinite)
    }

    func testSharedClaimSnapshotNormalizesWidgetPayload() {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let summary = SharedClaimSnapshot.ClaimSummary(
            id: UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!,
            title: "  \(String(repeating: "T", count: 300))  ",
            merchant: "   ",
            categoryDisplayName: "",
            categoryIconName: "bad symbol !",
            statusDisplayName: "",
            urgencyLabel: "",
            valueAtRisk: .infinity,
            deadline: invalidDate,
            hasProof: true
        )
        let snapshot = SharedClaimSnapshot(
            generatedAt: invalidDate,
            moneyAtRisk: .nan,
            recoveredValue: -50,
            urgentCount: -1,
            overdueCount: 200_000,
            activeCount: -10,
            prooflessOpenCount: 4,
            nextAction: summary,
            expiringSoon: Array(repeating: summary, count: 9)
        )

        let normalized = snapshot.normalizedForDisplay()

        XCTAssertTrue(normalized.generatedAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertEqual(normalized.moneyAtRisk, 0)
        XCTAssertEqual(normalized.recoveredValue, 0)
        XCTAssertEqual(normalized.urgentCount, 0)
        XCTAssertEqual(normalized.overdueCount, 99_999)
        XCTAssertEqual(normalized.activeCount, 0)
        XCTAssertEqual(normalized.prooflessOpenCount, 4)
        XCTAssertEqual(normalized.expiringSoon.count, 6)
        XCTAssertEqual(normalized.nextAction?.title.count, 160)
        XCTAssertNil(normalized.nextAction?.merchant)
        XCTAssertEqual(normalized.nextAction?.categoryDisplayName, "Claim")
        XCTAssertEqual(normalized.nextAction?.categoryIconName, "checkmark.shield.fill")
        XCTAssertEqual(normalized.nextAction?.statusDisplayName, "Active")
        XCTAssertEqual(normalized.nextAction?.urgencyLabel, "No deadline")
        XCTAssertEqual(normalized.nextAction?.valueAtRisk, 0)
        XCTAssertNil(normalized.nextAction?.deadline)
    }

    func testSharedClaimSnapshotNormalizationKeepsEncodedPayloadBounded() throws {
        let summary = SharedClaimSnapshot.ClaimSummary(
            id: UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!,
            title: String(repeating: "Title", count: 20_000),
            merchant: String(repeating: "Merchant", count: 20_000),
            categoryDisplayName: String(repeating: "Category", count: 20_000),
            categoryIconName: String(repeating: "symbol.", count: 20_000),
            statusDisplayName: String(repeating: "Status", count: 20_000),
            urgencyLabel: String(repeating: "Urgency", count: 20_000),
            valueAtRisk: .infinity,
            deadline: nil,
            hasProof: true
        )
        let snapshot = SharedClaimSnapshot(
            generatedAt: Date(),
            moneyAtRisk: .infinity,
            recoveredValue: .infinity,
            urgentCount: Int.max,
            overdueCount: Int.max,
            activeCount: Int.max,
            prooflessOpenCount: Int.max,
            nextAction: summary,
            expiringSoon: Array(repeating: summary, count: 2_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot.normalizedForDisplay())

        XCTAssertLessThanOrEqual(data.count, SharedClaimSnapshotStore.maximumSnapshotBytes)
    }
}
