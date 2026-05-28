import Foundation

final class ClaimDraftGenerator {
    static let shared = ClaimDraftGenerator()

    private let intelligenceService: OnDeviceIntelligenceService
    private let validator: ClaimDraftValidator
    private let preferOnDeviceIntelligence: Bool

    init(
        intelligenceService: OnDeviceIntelligenceService = .shared,
        validator: ClaimDraftValidator = ClaimDraftValidator(),
        preferOnDeviceIntelligence: Bool = true
    ) {
        self.intelligenceService = intelligenceService
        self.validator = validator
        self.preferOnDeviceIntelligence = preferOnDeviceIntelligence
    }

    func generate(from ocrResult: OCRResult) async -> ClaimDraft {
        let sourceText = OCRResult.normalizedSearchableText(ocrResult.searchableText)
        var draft: ClaimDraft?

        if preferOnDeviceIntelligence {
            draft = await intelligenceService.generateDraft(from: sourceText)
        }

        let resolvedDraft = draft ?? Self.generateFallbackDraft(from: sourceText, ocrWarnings: ocrResult.warnings)
        return validator.validate(resolvedDraft, sourceText: sourceText)
    }

    static func generateFallbackDraft(from text: String, ocrWarnings: [String] = []) -> ClaimDraft {
        let sourceText = OCRResult.normalizedSearchableText(text)
        let lines = normalizedLines(from: sourceText)
        let category = suggestedCategory(from: sourceText)
        let merchant = likelyMerchant(from: lines)
        let purchaseDate = parseFirstDate(sourceText)
        let explicitDeadline = explicitDeadline(from: sourceText)
        let value = preferredDollarAmount(from: lines)
        var warnings = ocrWarnings
        var suggestedDeadline = explicitDeadline

        if suggestedDeadline == nil, let purchaseDate {
            switch category {
            case .returnItem:
                suggestedDeadline = DateHelpers.calendar.date(byAdding: .day, value: 30, to: purchaseDate)
                warnings.append("Return deadline is suggested from the purchase date.")
            case .warranty:
                suggestedDeadline = DateHelpers.calendar.date(byAdding: .year, value: 1, to: purchaseDate)
                warnings.append("Warranty deadline is suggested from the purchase date.")
            case .reimbursement, .rebate:
                suggestedDeadline = DateHelpers.calendar.date(byAdding: .day, value: 30, to: purchaseDate)
                warnings.append("\(category?.displayName ?? "Claim") deadline is suggested from the purchase date.")
            default:
                break
            }
        }

        if value == nil, multipleDollarAmounts(in: lines) {
            warnings.append("Multiple dollar amounts were found. Value was left blank unless a total was clear.")
        }

        let title = title(merchant: merchant, category: category)
        let confidence = confidenceScore(merchant: merchant, category: category, value: value, date: purchaseDate ?? suggestedDeadline)
        let reminder = suggestedDeadline.flatMap { DateHelpers.defaultReminderDate(for: category ?? .other, deadline: $0) }

        return ClaimDraft(
            title: title,
            category: category,
            merchant: merchant,
            valueAtRisk: value,
            purchaseDate: purchaseDate,
            suggestedDeadline: suggestedDeadline,
            reminderDate: reminder,
            notes: nil,
            confidence: confidence,
            warnings: warnings,
            sourceSummary: lines.prefix(4).joined(separator: " ")
        )
    }

    static func parseFirstDate(_ text: String) -> Date? {
        let text = OCRResult.normalizedSearchableText(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    private static func normalizedLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func likelyMerchant(from lines: [String]) -> String? {
        let rejectedTerms = ["receipt", "invoice", "total", "subtotal", "tax", "date", "order", "amount", "payment"]

        return lines.first { line in
            let lowercased = line.lowercased()
            guard !rejectedTerms.contains(where: { lowercased.contains($0) }) else { return false }
            guard line.rangeOfCharacter(from: .letters) != nil else { return false }
            return line.count >= 2 && line.count <= 48
        }
    }

    private static func suggestedCategory(from text: String) -> ClaimCategory? {
        let lowercased = text.lowercased()

        if lowercased.contains("gift card") || lowercased.contains("giftcard") { return .giftCard }
        if lowercased.contains("warranty") || lowercased.contains("protection plan") { return .warranty }
        if lowercased.contains("rebate") || lowercased.contains("cash back") || lowercased.contains("mail in offer") { return .rebate }
        if lowercased.contains("reimbursement") || lowercased.contains("fsa") || lowercased.contains("hsa") || lowercased.contains("claim form") { return .reimbursement }
        if lowercased.contains("trial") || lowercased.contains("subscription") || lowercased.contains("cancel by") { return .subscription }
        if lowercased.contains("renewal") || lowercased.contains("renews") { return .renewal }
        if lowercased.contains("return by") || lowercased.contains("return policy") || lowercased.contains("refund") || lowercased.contains("exchange") { return .returnItem }
        if lowercased.contains("receipt") { return .returnItem }
        if lowercased.contains("document") || lowercased.contains("certificate") { return .document }
        return nil
    }

    private static func explicitDeadline(from text: String) -> Date? {
        let lines = normalizedLines(from: text)
        let deadlineTerms = [
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

        for line in lines where deadlineTerms.contains(where: { line.lowercased().contains($0) }) {
            if let date = parseFirstDate(line) {
                return date
            }
        }

        return nil
    }

    private static func preferredDollarAmount(from lines: [String]) -> Double? {
        let amountLines = lines.compactMap { line -> (line: String, values: [Double])? in
            let values = dollarAmounts(in: line)
            return values.isEmpty ? nil : (line, values)
        }

        let totalKeywords = ["grand total", "order total", "total", "amount due", "balance", "paid"]
        for entry in amountLines {
            let lowercased = entry.line.lowercased()
            guard !lowercased.contains("subtotal") else { continue }

            if totalKeywords.contains(where: { lowercased.range(of: $0, options: [.regularExpression]) != nil }),
               let value = entry.values.last {
                return value
            }
        }

        let allValues = amountLines.flatMap(\.values)
        return allValues.count == 1 ? allValues.first : nil
    }

    private static func multipleDollarAmounts(in lines: [String]) -> Bool {
        lines.flatMap { dollarAmounts(in: $0) }.count > 1
    }

    private static func dollarAmounts(in line: String) -> [Double] {
        let pattern = #"(?i)\$\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

        return regex.matches(in: line, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: line)
            else { return nil }

            guard let value = Double(line[valueRange].replacingOccurrences(of: ",", with: "")),
                  value.isFinite,
                  value <= CurrencyFormatter.maximumSupportedAmount
            else {
                return nil
            }

            return value
        }
    }

    private static func title(merchant: String?, category: ClaimCategory?) -> String? {
        guard let merchant else {
            guard let category else { return nil }
            return category.displayName
        }
        guard let category else { return merchant }
        return "\(merchant) \(category.displayName.lowercased())"
    }

    private static func confidenceScore(
        merchant: String?,
        category: ClaimCategory?,
        value: Double?,
        date: Date?
    ) -> Double {
        var score = 0.25
        if merchant != nil { score += 0.2 }
        if category != nil { score += 0.2 }
        if value != nil { score += 0.2 }
        if date != nil { score += 0.15 }
        return min(score, 0.85)
    }
}
