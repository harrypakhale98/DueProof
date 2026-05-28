import Foundation

struct ClaimSearchIntent: Equatable {
    private static let maximumSearchableTextLength = 20_000

    var text: String
    var categories: Set<ClaimCategory>
    var onlyMissingProof: Bool
    var onlyWithProof: Bool
    var onlyNoDeadline: Bool
    var onlyOverdue: Bool
    var dueWithinDays: Int?
    var minValue: Double?
    var maxValue: Double?

    static let maximumQueryLength = 120

    static func normalizedQuery(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumQueryLength))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func parse(_ query: String) -> ClaimSearchIntent {
        var working = normalizedQuery(query)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        var categories = Set<ClaimCategory>()
        for category in ClaimCategory.allCases {
            for alias in aliases(for: category) where containsPhrase(alias, in: working) {
                categories.insert(category)
                working = removingPhrase(alias, from: working)
            }
        }

        let onlyMissingProof = consumeAny(
            ["missing proof", "no proof", "without proof", "needs proof", "need proof"],
            from: &working
        )
        let onlyWithProof = consumeAny(
            ["with proof", "has proof", "have proof", "proof attached"],
            from: &working
        )
        let onlyNoDeadline = consumeAny(
            ["no deadline", "missing deadline", "without deadline"],
            from: &working
        )
        let onlyOverdue = consumeAny(
            ["overdue", "past due"],
            from: &working
        )

        let dueWithinDays = consumeDueWindow(from: &working)
        let minValue = consumeValue(prefixes: ["over", "above", "more than", "at least"], from: &working)
        let maxValue = consumeValue(prefixes: ["under", "below", "less than", "at most"], from: &working)

        return ClaimSearchIntent(
            text: normalizedText(working),
            categories: categories,
            onlyMissingProof: onlyMissingProof,
            onlyWithProof: onlyWithProof,
            onlyNoDeadline: onlyNoDeadline,
            onlyOverdue: onlyOverdue,
            dueWithinDays: dueWithinDays,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    func matches(_ claim: Claim, referenceDate: Date = Date()) -> Bool {
        if !categories.isEmpty, !categories.contains(claim.category) {
            return false
        }

        if onlyMissingProof, !claim.proofItemsList.isEmpty {
            return false
        }

        if onlyWithProof, claim.proofItemsList.isEmpty {
            return false
        }

        if onlyNoDeadline, claim.deadline?.timeIntervalSinceReferenceDate.isFinite == true {
            return false
        }

        if onlyOverdue, !claim.hasOverdueDeadline(relativeTo: referenceDate) {
            return false
        }

        if let dueWithinDays {
            guard claim.status.isOpen,
                  let deadline = claim.deadline
            else { return false }

            let days = DateHelpers.daysUntil(deadline, from: referenceDate)
            guard days >= 0 && days <= dueWithinDays else { return false }
        }

        let valueAtRisk = CurrencyFormatter.sanitizedAmount(claim.valueAtRisk)

        if let minValue, valueAtRisk < minValue {
            return false
        }

        if let maxValue, valueAtRisk > maxValue {
            return false
        }

        guard !text.isEmpty else { return true }

        let searchableText = Self.searchableText(for: claim)
        return text
            .split(separator: " ")
            .allSatisfy { searchableText.localizedCaseInsensitiveContains(String($0)) }
    }

    private static func searchableText(for claim: Claim) -> String {
        var parts: [String] = []
        var remaining = maximumSearchableTextLength

        func append(_ value: String?, limit: Int) {
            guard remaining > 0 else { return }
            let normalized = ClaimTextLimits.required(value ?? "", limit: limit)
            guard !normalized.isEmpty else { return }
            let bounded = String(normalized.prefix(remaining))
            parts.append(bounded)
            remaining -= min(remaining, bounded.count + 1)
        }

        append(claim.title, limit: ClaimTextLimits.title)
        append(claim.merchant, limit: ClaimTextLimits.merchant)
        append(claim.notes, limit: ClaimTextLimits.notes)
        append(claim.primaryReference, limit: ClaimTextLimits.reference)
        append(claim.policySummary, limit: ClaimTextLimits.policySummary)
        append(claim.actionURL?.absoluteString, limit: ClaimTextLimits.actionURL)
        append(claim.category.displayName, limit: 80)
        append(claim.category.pluralDisplayName, limit: 80)
        append(claim.statusDisplayName, limit: 40)
        append(claim.displayValue, limit: 80)
        append(claim.urgencyLabel, limit: 80)

        for proof in claim.proofItemsList {
            append(proof.displayName, limit: ProofItemTextLimits.displayName)
            append(proof.extractedText, limit: ProofItemTextLimits.extractedText)

            if let intelligence = proof.intelligence?.normalizedForStorage() {
                append(intelligence.summary, limit: 500)
                append(intelligence.merchant, limit: ClaimTextLimits.merchant)
                append(intelligence.category?.displayName, limit: 80)
                append(intelligence.orderNumber, limit: ClaimTextLimits.reference)
                append(intelligence.serialNumber, limit: ClaimTextLimits.reference)
                for barcodeValue in intelligence.barcodeValues {
                    append(barcodeValue, limit: ClaimTextLimits.reference)
                }
                append(intelligence.deadlineLabel, limit: 80)
                for warning in intelligence.warnings {
                    append(warning, limit: 160)
                }
            }
        }

        return parts.joined(separator: " ").lowercased()
    }

    private static func aliases(for category: ClaimCategory) -> [String] {
        switch category {
        case .returnItem:
            ["returns", "return", "refund", "exchange"]
        case .giftCard:
            ["gift cards", "gift card", "giftcard", "giftcards"]
        case .warranty:
            ["warranties", "warranty", "protection plan"]
        case .reimbursement:
            ["reimbursements", "reimbursement", "fsa", "hsa"]
        case .rebate:
            ["rebates", "rebate", "cash back"]
        case .subscription:
            ["subscriptions", "subscription", "trial", "cancel"]
        case .renewal:
            ["renewals", "renewal", "renews"]
        case .document:
            ["documents", "document", "certificate"]
        case .other:
            ["other"]
        }
    }

    private static func consumeDueWindow(from text: inout String) -> Int? {
        let windows: [(phrases: [String], days: Int)] = [
            (["due today", "today"], 0),
            (["due tomorrow", "tomorrow"], 1),
            (["due this week", "this week", "next 7 days"], 7),
            (["due this month", "this month", "next 30 days"], 30)
        ]

        for window in windows {
            if consumeAny(window.phrases, from: &text) {
                return window.days
            }
        }

        if let match = firstMatch(#"\bdue\s+(?:in|within)\s+([0-9]{1,3})\s+days?\b"#, in: text),
           let value = Int(match.value) {
            text = removingRange(match.range, from: text)
            return max(0, min(value, 365))
        }

        return nil
    }

    private static func consumeValue(prefixes: [String], from text: inout String) -> Double? {
        for prefix in prefixes {
            let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
            let pattern = #"\b"# + escapedPrefix + #"\s+\$?([0-9]+(?:[.,][0-9]{1,2})?)\b"#
            guard let match = firstMatch(pattern, in: text),
                  let value = CurrencyFormatter.parse(match.value)
            else { continue }

            text = removingRange(match.range, from: text)
            return value
        }

        return nil
    }

    private static func consumeAny(_ phrases: [String], from text: inout String) -> Bool {
        var didConsume = false
        for phrase in phrases where containsPhrase(phrase, in: text) {
            text = removingPhrase(phrase, from: text)
            didConsume = true
        }
        return didConsume
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        guard let regex = phraseRegex(for: phrase) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func removingPhrase(_ phrase: String, from text: String) -> String {
        guard let regex = phraseRegex(for: phrase) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (range: NSRange, value: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }

        return (match.range, String(text[valueRange]))
    }

    private static func removingRange(_ range: NSRange, from text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var mutableText = text
        mutableText.replaceSubrange(swiftRange, with: " ")
        return mutableText
    }

    private static func phraseRegex(for phrase: String) -> NSRegularExpression? {
        let escaped = phrase
            .split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        guard !escaped.isEmpty else { return nil }
        let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
