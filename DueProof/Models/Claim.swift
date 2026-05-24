import Foundation
import SwiftData

@Model
final class Claim {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: ClaimCategory
    var merchant: String?
    var valueAtRisk: Double
    var deadline: Date?
    var reminderDate: Date?
    var notes: String
    var status: ClaimStatus
    @Relationship(deleteRule: .cascade, inverse: \ProofItem.claim) var proofItems: [ProofItem]
    var createdAt: Date
    var updatedAt: Date
    var recoveredValue: Double
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        category: ClaimCategory,
        merchant: String? = nil,
        valueAtRisk: Double,
        deadline: Date? = nil,
        reminderDate: Date? = nil,
        notes: String = "",
        status: ClaimStatus = .active,
        proofItems: [ProofItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recoveredValue: Double = 0,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.merchant = merchant
        self.valueAtRisk = valueAtRisk
        self.deadline = deadline
        self.reminderDate = reminderDate
        self.notes = notes
        self.status = status
        self.proofItems = proofItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recoveredValue = recoveredValue
        self.completedAt = completedAt
    }

    var isUrgent: Bool {
        guard status.isOpen else { return false }
        guard let deadline else { return false }
        let days = DateHelpers.daysUntil(deadline)
        return days >= 0 && days <= 7
    }

    var daysUntilDeadline: Int? {
        guard let deadline else { return nil }
        return DateHelpers.daysUntil(deadline)
    }

    var isExpired: Bool {
        status == .expired
    }

    var isOverdue: Bool {
        guard status.isOpen, let deadline else { return false }
        return DateHelpers.isPastDeadline(deadline)
    }

    var displayValue: String {
        CurrencyFormatter.string(valueAtRisk)
    }

    var recoveredDisplayValue: String {
        CurrencyFormatter.string(recoveredValue)
    }

    var urgencyLabel: String {
        guard let daysUntilDeadline else {
            return reminderDate == nil ? "No deadline" : "Reminder set"
        }

        if daysUntilDeadline < 0 {
            let overdueDays = abs(daysUntilDeadline)
            return overdueDays == 1 ? "Overdue by 1 day" : "Overdue by \(overdueDays) days"
        } else if daysUntilDeadline == 0 {
            return "Due today"
        } else if daysUntilDeadline == 1 {
            return "Due tomorrow"
        } else if daysUntilDeadline <= 7 {
            return "Due in \(daysUntilDeadline) days"
        } else if let deadline {
            return DateHelpers.shortDate(deadline)
        } else {
            return "No deadline"
        }
    }

    var categoryIcon: String {
        category.iconName
    }

    var categoryDisplayName: String {
        category.displayName
    }

    var statusDisplayName: String {
        effectiveStatus.displayName
    }

    var effectiveStatus: ClaimStatus {
        if isExpired { return .expired }
        if isOverdue { return .overdue }
        if isUrgent { return .urgent }
        return status
    }

    var countsTowardMoneyAtRisk: Bool {
        status.isOpen
    }

    func touch() {
        updatedAt = Date()
    }

    func markRecovered() {
        status = .recovered
        completedAt = Date()
        recoveredValue = valueAtRisk
        touch()
    }

    func markUsed() {
        status = .used
        completedAt = Date()
        touch()
    }

    func markExpired() {
        status = .expired
        touch()
    }

    func markIgnored() {
        status = .ignored
        completedAt = Date()
        touch()
    }
}
