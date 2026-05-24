import Foundation

struct ClaimDraftValidator {
    static let reviewWarning = "Review suggested details before saving."

    func validate(_ draft: ClaimDraft, sourceText: String) -> ClaimDraft {
        var validated = draft
        validated.confidence = min(max(validated.confidence, 0), 1)
        validated.warnings = Array(Set(validated.warnings)).sorted()

        if validated.category == .giftCard,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitExpiration(sourceText) {
            validated.suggestedDeadline = nil
            validated.warnings.append("Gift cards only get an expiration date when the proof clearly shows one.")
        }

        if validated.category == .returnItem,
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.append("Return deadline is suggested from the purchase date. Confirm the merchant policy before saving.")
        }

        if validated.category == .warranty,
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.append("Warranty deadline is suggested from the purchase date. Confirm the coverage terms before saving.")
        }

        if (validated.category == .reimbursement || validated.category == .rebate),
           validated.purchaseDate != nil,
           validated.suggestedDeadline != nil,
           !sourceHasExplicitDeadline(sourceText) {
            validated.warnings.append("Claim deadline is suggested from the purchase date. Confirm the submission window before saving.")
        }

        if validated.confidence < 0.45 {
            validated.valueAtRisk = nil
            if validated.category == .other {
                validated.category = nil
            }
            validated.warnings.append("Only a few details looked reliable, so some fields were left blank.")
        }

        validated.warnings.append(Self.reviewWarning)
        validated.warnings = Array(Set(validated.warnings)).sorted()
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
}
