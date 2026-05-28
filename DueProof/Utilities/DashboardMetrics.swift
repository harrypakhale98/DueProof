import Foundation

struct DashboardMetrics {
    let moneyAtRisk: Double
    let recoveredValue: Double
    let urgentCount: Int
    let activeCount: Int
    let overdueCount: Int
    let prooflessOpenCount: Int
    let nextActionClaim: Claim?
    let expiringSoonClaims: [Claim]

    init(claims: [Claim], referenceDate: Date = Date()) {
        moneyAtRisk = claims
            .filter(\.countsTowardMoneyAtRisk)
            .reduce(0) { $0 + CurrencyFormatter.sanitizedAmount($1.valueAtRisk) }

        recoveredValue = claims
            .filter { $0.status == .recovered }
            .reduce(0) { $0 + CurrencyFormatter.sanitizedAmount($1.recoveredValue) }

        urgentCount = claims
            .filter { claim in
                claim.hasUrgentDeadline(relativeTo: referenceDate)
            }
            .count

        activeCount = claims
            .filter { $0.status.isOpen }
            .count

        overdueCount = claims
            .filter { claim in
                claim.hasOverdueDeadline(relativeTo: referenceDate)
            }
            .count

        prooflessOpenCount = claims
            .filter { $0.status.isOpen && $0.proofItemsList.isEmpty }
            .count

        expiringSoonClaims = claims
            .filter { claim in
                guard claim.status.isOpen,
                      !Self.isExpired(claim),
                      let deadline = claim.deadline
                else { return false }

                return DateHelpers.daysUntil(deadline, from: referenceDate) <= 30
            }
            .sorted {
                ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }
            .prefix(6)
            .map { $0 }

        nextActionClaim = claims
            .filter(\.status.isOpen)
            .sorted { lhs, rhs in
                let lhsRank = Self.actionRank(for: lhs, referenceDate: referenceDate)
                let rhsRank = Self.actionRank(for: rhs, referenceDate: referenceDate)
                if lhsRank != rhsRank { return lhsRank < rhsRank }

                let lhsDeadline = lhs.deadline ?? .distantFuture
                let rhsDeadline = rhs.deadline ?? .distantFuture
                if lhsDeadline != rhsDeadline { return lhsDeadline < rhsDeadline }

                return CurrencyFormatter.sanitizedAmount(lhs.valueAtRisk) > CurrencyFormatter.sanitizedAmount(rhs.valueAtRisk)
            }
            .first
    }

    static func isExpired(_ claim: Claim) -> Bool {
        claim.status == .expired
    }

    private static func actionRank(for claim: Claim, referenceDate: Date) -> Int {
        if let deadline = claim.deadline {
            let days = DateHelpers.daysUntil(deadline, from: referenceDate)
            if days < 0 { return 0 }
            if days <= 7 { return 1 }
            if days <= 30 { return 3 }
        }

        if claim.proofItemsList.isEmpty { return 2 }
        if claim.deadline == nil { return 4 }
        return 5
    }
}
