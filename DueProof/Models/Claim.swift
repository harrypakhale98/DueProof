import Foundation
import SwiftData

enum ClaimTextLimits {
    static let title = 160
    static let merchant = 120
    static let reference = 120
    static let policySummary = 1_500
    static let actionURL = DueProofActionURL.maximumLength
    static let notes = 4_000

    static func required(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    static func optional(_ value: String?, limit: Int) -> String? {
        let normalized = required(value ?? "", limit: limit)
        return normalized.isEmpty ? nil : normalized
    }
}

private enum ClaimStorageDefaults {
    static let fallbackTitle = "Untitled claim"
}

struct ClaimMutationSnapshot {
    private let title: String
    private let category: ClaimCategory
    private let merchant: String?
    private let valueAtRisk: Double
    private let deadline: Date?
    private let reminderDate: Date?
    private let referenceNumber: String?
    private let policySummary: String
    private let actionURLString: String?
    private let notes: String
    private let status: ClaimStatus
    private let proofItems: [ProofItem]
    private let createdAt: Date
    private let updatedAt: Date
    private let recoveredValue: Double
    private let completedAt: Date?

    init(_ claim: Claim) {
        title = claim.title
        category = claim.category
        merchant = claim.merchant
        valueAtRisk = claim.valueAtRisk
        deadline = claim.deadline
        reminderDate = claim.reminderDate
        referenceNumber = claim.referenceNumber
        policySummary = claim.policySummary
        actionURLString = claim.actionURLString
        notes = claim.notes
        status = claim.status
        proofItems = claim.proofItemsList
        createdAt = claim.createdAt
        updatedAt = claim.updatedAt
        recoveredValue = claim.recoveredValue
        completedAt = claim.completedAt
    }

    func restore(to claim: Claim) {
        claim.title = title
        claim.category = category
        claim.merchant = merchant
        claim.valueAtRisk = valueAtRisk
        claim.deadline = deadline
        claim.reminderDate = reminderDate
        claim.referenceNumber = referenceNumber
        claim.policySummary = policySummary
        claim.actionURLString = actionURLString
        claim.notes = notes
        claim.status = status
        claim.proofItemsList = proofItems
        claim.createdAt = createdAt
        claim.updatedAt = updatedAt
        claim.recoveredValue = recoveredValue
        claim.completedAt = completedAt
    }

    func restoreDeletedClaim(_ claim: Claim, into context: ModelContext) {
        context.insert(claim)
        for proofItem in proofItems {
            context.insert(proofItem)
        }
        restore(to: claim)
    }
}

@Model
final class Claim {
    var id: UUID = UUID()
    var title: String = ""
    var category: ClaimCategory = ClaimCategory.other
    var merchant: String?
    var valueAtRisk: Double = 0
    var deadline: Date?
    var reminderDate: Date?
    var referenceNumber: String?
    var policySummary: String = ""
    var actionURLString: String?
    var notes: String = ""
    var status: ClaimStatus = ClaimStatus.active
    @Relationship(deleteRule: .cascade, inverse: \ProofItem.claim) var proofItems: [ProofItem]?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var recoveredValue: Double = 0
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        category: ClaimCategory,
        merchant: String? = nil,
        valueAtRisk: Double,
        deadline: Date? = nil,
        reminderDate: Date? = nil,
        referenceNumber: String? = nil,
        policySummary: String = "",
        actionURLString: String? = nil,
        notes: String = "",
        status: ClaimStatus = .active,
        proofItems: [ProofItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recoveredValue: Double = 0,
        completedAt: Date? = nil
    ) {
        let normalizedTitle = Self.normalizedTitle(title)
        let normalizedStatus = ClaimStatus.normalizedStoredStatus(status)
        let normalizedValueAtRisk = CurrencyFormatter.sanitizedAmount(valueAtRisk)
        let normalizedRecoveredValue = min(
            CurrencyFormatter.sanitizedAmount(recoveredValue),
            normalizedValueAtRisk
        )
        let normalizedDeadline = Self.normalizedDate(deadline)
        let normalizedCreatedAt = Self.normalizedDate(createdAt) ?? Date()
        let normalizedUpdatedAt = Self.normalizedDate(updatedAt) ?? normalizedCreatedAt
        let normalizedCompletedAt = Self.normalizedDate(completedAt)

        self.id = id
        self.title = normalizedTitle
        self.category = category
        self.merchant = ClaimTextLimits.optional(merchant, limit: ClaimTextLimits.merchant)
        self.valueAtRisk = normalizedValueAtRisk
        self.deadline = normalizedDeadline
        self.reminderDate = Self.normalizedReminderDate(
            reminderDate,
            deadline: normalizedDeadline,
            status: normalizedStatus
        )
        self.referenceNumber = ClaimTextLimits.optional(referenceNumber, limit: ClaimTextLimits.reference)
        self.policySummary = ClaimTextLimits.required(policySummary, limit: ClaimTextLimits.policySummary)
        self.actionURLString = Self.normalizedActionURLString(actionURLString)
        self.notes = ClaimTextLimits.required(notes, limit: ClaimTextLimits.notes)
        self.status = normalizedStatus
        self.proofItems = proofItems
        self.createdAt = normalizedCreatedAt
        self.updatedAt = normalizedUpdatedAt
        self.recoveredValue = normalizedStatus == .recovered ? normalizedRecoveredValue : 0
        self.completedAt = normalizedStatus.isComplete ? normalizedCompletedAt : nil
    }

    var proofItemsList: [ProofItem] {
        get { proofItems ?? [] }
        set { proofItems = newValue }
    }

    @discardableResult
    func normalizeStoredFields() -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Claim, Value>, to normalizedValue: Value) {
            guard self[keyPath: keyPath] != normalizedValue else { return }
            self[keyPath: keyPath] = normalizedValue
            didChange = true
        }

        let normalizedStatus = ClaimStatus.normalizedStoredStatus(status)
        let normalizedValueAtRisk = CurrencyFormatter.sanitizedAmount(valueAtRisk)
        let normalizedRecoveredValue = min(
            CurrencyFormatter.sanitizedAmount(recoveredValue),
            normalizedValueAtRisk
        )
        let normalizedDeadline = Self.normalizedDate(deadline)
        let normalizedCreatedAt = Self.normalizedDate(createdAt) ?? Date()
        let normalizedUpdatedAt = Self.normalizedDate(updatedAt) ?? normalizedCreatedAt
        let resolvedRecoveredValue = normalizedStatus == .recovered ? normalizedRecoveredValue : 0
        let resolvedCompletedAt = normalizedStatus.isComplete ? Self.normalizedDate(completedAt) : nil

        update(\.title, to: Self.normalizedTitle(title))
        update(\.merchant, to: ClaimTextLimits.optional(merchant, limit: ClaimTextLimits.merchant))
        update(\.valueAtRisk, to: normalizedValueAtRisk)
        update(\.deadline, to: normalizedDeadline)
        update(\.reminderDate, to: Self.normalizedReminderDate(reminderDate, deadline: normalizedDeadline, status: normalizedStatus))
        update(\.referenceNumber, to: ClaimTextLimits.optional(referenceNumber, limit: ClaimTextLimits.reference))
        update(\.policySummary, to: ClaimTextLimits.required(policySummary, limit: ClaimTextLimits.policySummary))
        update(\.actionURLString, to: Self.normalizedActionURLString(actionURLString))
        update(\.notes, to: ClaimTextLimits.required(notes, limit: ClaimTextLimits.notes))
        update(\.status, to: normalizedStatus)
        update(\.createdAt, to: normalizedCreatedAt)
        update(\.updatedAt, to: normalizedUpdatedAt)
        update(\.recoveredValue, to: resolvedRecoveredValue)
        update(\.completedAt, to: resolvedCompletedAt)

        for proof in proofItemsList {
            didChange = proof.normalizeStoredFields() || didChange
        }

        return didChange
    }

    var isUrgent: Bool {
        hasUrgentDeadline(relativeTo: Date())
    }

    func hasUrgentDeadline(relativeTo referenceDate: Date) -> Bool {
        guard status.isOpen else { return false }
        guard let deadline else { return false }
        let days = DateHelpers.daysUntil(deadline, from: referenceDate)
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
        hasOverdueDeadline(relativeTo: Date())
    }

    func hasOverdueDeadline(relativeTo referenceDate: Date) -> Bool {
        guard status.isOpen, let deadline else { return false }
        return DateHelpers.isPastDeadline(deadline, referenceDate: referenceDate)
    }

    var displayValue: String {
        CurrencyFormatter.string(valueAtRisk)
    }

    var recoveredDisplayValue: String {
        CurrencyFormatter.string(recoveredValue)
    }

    var actionURL: URL? {
        DueProofActionURL.url(from: actionURLString)
    }

    static func normalizedActionURLString(_ value: String?) -> String? {
        DueProofActionURL.normalizedString(from: value)
    }

    private static func normalizedTitle(_ value: String) -> String {
        let normalized = ClaimTextLimits.required(value, limit: ClaimTextLimits.title)
        return normalized.isEmpty ? ClaimStorageDefaults.fallbackTitle : normalized
    }

    private static func normalizedReminderDate(_ value: Date?, deadline: Date?, status: ClaimStatus) -> Date? {
        guard status.isOpen else { return nil }
        guard let value = normalizedDate(value) else { return nil }
        if let deadline = normalizedDate(deadline), value > deadline { return nil }
        return value
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }

    var primaryReference: String? {
        if let explicitReference = ClaimTextLimits.optional(referenceNumber, limit: ClaimTextLimits.reference) {
            return explicitReference
        }

        return proofItemsList.compactMap { proof in
            ClaimTextLimits.optional(proof.intelligence?.primaryIdentifier, limit: ClaimTextLimits.reference)
        }.first
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
        return ClaimStatus.normalizedStoredStatus(status)
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
        recoveredValue = CurrencyFormatter.sanitizedAmount(valueAtRisk)
        touch()
    }

    func markUsed() {
        status = .used
        completedAt = Date()
        recoveredValue = 0
        touch()
    }

    func markExpired() {
        status = .expired
        completedAt = Date()
        recoveredValue = 0
        touch()
    }

    func markIgnored() {
        status = .ignored
        completedAt = Date()
        recoveredValue = 0
        touch()
    }
}
