import Foundation

struct ClaimDraftValidator {
    static let reviewWarning = "Review suggested details before saving."
    private static let sourceSummaryLimit = 500
    private static let warningLimit = 160
    private static let maximumWarnings = 8

    func validate(_ draft: ClaimDraft, sourceText: String) -> ClaimDraft {
        let sourceText = OCRResult.normalizedSearchableText(sourceText)
        var validated = draft
        validated.title = ClaimTextLimits.optional(validated.title, limit: ClaimTextLimits.title)
        validated.merchant = ClaimTextLimits.optional(validated.merchant, limit: ClaimTextLimits.merchant)
        validated.valueAtRisk = nonNegativeFinite(validated.valueAtRisk)
        validated.purchaseDate = finiteDate(validated.purchaseDate)
        validated.suggestedDeadline = finiteDate(validated.suggestedDeadline)
        validated.reminderDate = finiteDate(validated.reminderDate)
        if let reminderDate = validated.reminderDate,
           let suggestedDeadline = validated.suggestedDeadline,
           reminderDate > suggestedDeadline {
            validated.reminderDate = nil
        }
        validated.notes = ClaimTextLimits.optional(validated.notes, limit: ClaimTextLimits.notes)
        validated.confidence = normalizedConfidence(validated.confidence)
        validated.warnings = Self.normalizedWarnings(validated.warnings)
        validated.sourceSummary = ClaimTextLimits.optional(validated.sourceSummary, limit: Self.sourceSummaryLimit)

        if validated.category == .giftCard,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitExpiration(sourceText) {
            validated.suggestedDeadline = nil
            validated.warnings.insert("Gift cards only get an expiration date when the proof clearly shows one.", at: 0)
        }

        if validated.category == .returnItem,
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.insert("Return deadline is suggested from the purchase date. Confirm the merchant policy before saving.", at: 0)
        }

        if validated.category == .warranty,
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.insert("Warranty deadline is suggested from the purchase date. Confirm the coverage terms before saving.", at: 0)
        }

        if (validated.category == .reimbursement || validated.category == .rebate),
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.insert("Claim deadline is suggested from the purchase date. Confirm the submission window before saving.", at: 0)
        }

        if validated.confidence < 0.45 {
            validated.valueAtRisk = nil
            if validated.category == .other {
                validated.category = nil
            }
            validated.warnings.insert("Only a few details looked reliable, so some fields were left blank.", at: 0)
        }

        validated.warnings = Self.normalizedWarnings(validated.warnings, required: [Self.reviewWarning])
        return validated
    }

    private func sourceHasExplicitExpiration(_ sourceText: String) -> Bool {
        let lowercased = sourceText.lowercased()
        guard lowercased.contains("expire")
            || lowercased.contains("expiration")
            || lowercased.contains("valid thru")
            || lowercased.contains("valid through")
            || lowercased.contains("valid until")
        else {
            return false
        }
        return ClaimDraftGenerator.parseFirstDate(sourceText) != nil
    }

    private func sourceHasExplicitDeadline(_ sourceText: String) -> Bool {
        let lowercased = sourceText.lowercased()
        let deadlineWords = [
            "return by",
            "claim by",
            "submit by",
            "deadline",
            "due date",
            "expires",
            "expiration",
            "valid through",
            "valid thru",
            "valid until",
            "use by",
            "cancel by",
            "renewal date",
            "renews on"
        ]
        return deadlineWords.contains { lowercased.contains($0) }
    }

    private func nonNegativeFinite(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= CurrencyFormatter.maximumSupportedAmount
        else {
            return nil
        }
        return value
    }

    private func finiteDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }

    private func normalizedConfidence(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func normalizedWarnings(_ warnings: [String], required: [String] = []) -> [String] {
        var seen = Set<String>()
        return (required + warnings).compactMap { warning in
            let normalized = ClaimTextLimits.required(warning, limit: Self.warningLimit)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .prefix(Self.maximumWarnings)
        .map { $0 }
    }
}
