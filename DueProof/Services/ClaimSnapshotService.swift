import Foundation
import WidgetKit

final class ClaimSnapshotService {
    static let shared = ClaimSnapshotService()

    private init() {}

    func publish(claims: [Claim]) {
        let snapshot = makeSnapshot(claims: claims)

        do {
            try SharedClaimSnapshotStore.shared.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            #if DEBUG
            print("Unable to publish DueProof widget snapshot: \(error.localizedDescription)")
            #endif
        }
    }

    func clear() {
        SharedClaimSnapshotStore.shared.delete()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func makeSnapshot(claims: [Claim]) -> SharedClaimSnapshot {
        let metrics = DashboardMetrics(claims: claims)
        return SharedClaimSnapshot(
            generatedAt: Date(),
            moneyAtRisk: metrics.moneyAtRisk,
            recoveredValue: metrics.recoveredValue,
            urgentCount: metrics.urgentCount,
            overdueCount: metrics.overdueCount,
            activeCount: metrics.activeCount,
            prooflessOpenCount: metrics.prooflessOpenCount,
            nextAction: metrics.nextActionClaim.map(makeSummary),
            expiringSoon: metrics.expiringSoonClaims.map(makeSummary)
        )
    }

    private func makeSummary(claim: Claim) -> SharedClaimSnapshot.ClaimSummary {
        SharedClaimSnapshot.ClaimSummary(
            id: claim.id,
            title: claim.title,
            merchant: claim.merchant,
            categoryDisplayName: claim.categoryDisplayName,
            categoryIconName: claim.categoryIcon,
            statusDisplayName: claim.statusDisplayName,
            urgencyLabel: claim.urgencyLabel,
            valueAtRisk: claim.valueAtRisk,
            deadline: claim.deadline,
            hasProof: !claim.proofItemsList.isEmpty
        )
    }
}
