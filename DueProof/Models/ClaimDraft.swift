import Foundation

struct ClaimDraft: Equatable {
    var title: String?
    var category: ClaimCategory?
    var merchant: String?
    var valueAtRisk: Double?
    var purchaseDate: Date?
    var suggestedDeadline: Date?
    var reminderDate: Date?
    var notes: String?
    var confidence: Double
    var warnings: [String]
    var sourceSummary: String?

    init(
        title: String? = nil,
        category: ClaimCategory? = nil,
        merchant: String? = nil,
        valueAtRisk: Double? = nil,
        purchaseDate: Date? = nil,
        suggestedDeadline: Date? = nil,
        reminderDate: Date? = nil,
        notes: String? = nil,
        confidence: Double = 0,
        warnings: [String] = [],
        sourceSummary: String? = nil
    ) {
        self.title = title
        self.category = category
        self.merchant = merchant
        self.valueAtRisk = valueAtRisk
        self.purchaseDate = purchaseDate
        self.suggestedDeadline = suggestedDeadline
        self.reminderDate = reminderDate
        self.notes = notes
        self.confidence = confidence
        self.warnings = warnings
        self.sourceSummary = sourceSummary
    }
}
