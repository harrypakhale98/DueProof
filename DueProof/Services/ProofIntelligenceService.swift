import Foundation

final class ProofIntelligenceService {
    static let shared = ProofIntelligenceService()

    private let intelligenceService: OnDeviceIntelligenceService
    private let preferOnDeviceIntelligence: Bool

    init(
        intelligenceService: OnDeviceIntelligenceService = .shared,
        preferOnDeviceIntelligence: Bool = true
    ) {
        self.intelligenceService = intelligenceService
        self.preferOnDeviceIntelligence = preferOnDeviceIntelligence
    }

    func analyze(
        ocrResult: OCRResult,
        categoryHint: ClaimCategory? = nil
    ) async -> ProofIntelligence {
        let text = ocrResult.searchableText
        var intelligence: ProofIntelligence?

        if preferOnDeviceIntelligence {
            intelligence = await intelligenceService.analyzeProof(from: text, categoryHint: categoryHint)
        }

        let fallback = Self.generateFallbackAnalysis(
            from: text,
            categoryHint: categoryHint,
            barcodeValues: ocrResult.barcodes.map(\.value),
            ocrWarnings: ocrResult.warnings
        )

        return normalized(intelligence ?? fallback, fallback: fallback, sourceText: text)
    }

    static func generateFallbackAnalysis(
        from text: String,
        categoryHint: ClaimCategory? = nil,
        barcodeValues: [String] = [],
        ocrWarnings: [String] = []
    ) -> ProofIntelligence {
        let draft = ClaimDraftGenerator.generateFallbackDraft(from: text, ocrWarnings: ocrWarnings)
        let category = draft.category ?? categoryHint
        let explicitDeadline = explicitDeadline(from: text)
        let orderNumber = likelyOrderNumber(from: text)
        let serialNumber = likelySerialNumber(from: text)
        let resolvedBarcodeValues = normalizedBarcodeValues(barcodeValues + barcodeValuesFromText(text))
        let merchant = draft.merchant
        let value = draft.valueAtRisk
        let purchaseDate = draft.purchaseDate
        let deadline = explicitDeadline ?? draft.suggestedDeadline
        let isExplicit = explicitDeadline != nil
        let completeness = completeness(
            merchant: merchant,
            value: value,
            purchaseDate: purchaseDate,
            deadline: deadline,
            hasReadableText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        let warnings = normalizedWarnings(
            ocrWarnings + draft.warnings + (isExplicit || deadline == nil ? [] : ["Deadline is suggested. Confirm the proof before relying on it."])
        )

        return ProofIntelligence(
            merchant: merchant,
            category: category,
            valueAtRisk: value,
            purchaseDate: purchaseDate,
            deadline: deadline,
            deadlineIsExplicit: isExplicit,
            orderNumber: orderNumber,
            serialNumber: serialNumber,
            barcodeValues: resolvedBarcodeValues,
            confidence: fallbackConfidence(
                merchant: merchant,
                value: value,
                purchaseDate: purchaseDate,
                deadline: deadline,
                orderNumber: orderNumber,
                serialNumber: serialNumber,
                barcodeValues: resolvedBarcodeValues
            ),
            warnings: warnings,
            summary: summary(
                merchant: merchant,
                category: category,
                value: value,
                deadline: deadline,
                isExplicit: isExplicit,
                identifier: orderNumber ?? serialNumber ?? resolvedBarcodeValues.first,
                completeness: completeness
            ),
            completeness: completeness
        )
    }

    static func completeness(
        merchant: String?,
        value: Double?,
        purchaseDate: Date?,
        deadline: Date?,
        hasReadableText: Bool
    ) -> ProofCompleteness {
        let hasMerchant = merchant?.isEmpty == false
        let hasValue = value != nil
        let hasPurchaseDate = purchaseDate != nil
        let hasDeadline = deadline != nil
        var missingFields: [String] = []

        if !hasMerchant { missingFields.append("merchant") }
        if !hasValue { missingFields.append("value") }
        if !hasPurchaseDate { missingFields.append("purchase date") }
        if !hasDeadline { missingFields.append("deadline") }
        if !hasReadableText { missingFields.append("readable text") }

        let checks = [hasMerchant, hasValue, hasPurchaseDate, hasDeadline, hasReadableText]
        let score = Double(checks.filter { $0 }.count) / Double(checks.count)

        return ProofCompleteness(
            score: score,
            hasMerchant: hasMerchant,
            hasValue: hasValue,
            hasPurchaseDate: hasPurchaseDate,
            hasDeadline: hasDeadline,
            hasReadableText: hasReadableText,
            missingFields: missingFields
        )
    }

    private func normalized(
        _ intelligence: ProofIntelligence,
        fallback: ProofIntelligence,
        sourceText: String
    ) -> ProofIntelligence {
        let merchant = trimmed(intelligence.merchant) ?? fallback.merchant
        let category = intelligence.category ?? fallback.category
        let value = validValue(intelligence.valueAtRisk) ?? fallback.valueAtRisk
        let purchaseDate = intelligence.purchaseDate ?? fallback.purchaseDate
        let deadline = intelligence.deadline ?? fallback.deadline
        let orderNumber = trimmed(intelligence.orderNumber) ?? fallback.orderNumber
        let serialNumber = trimmed(intelligence.serialNumber) ?? fallback.serialNumber
        let barcodeValues = Self.normalizedBarcodeValues(intelligence.barcodeValues + fallback.barcodeValues)
        let hasReadableText = !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let deadlineIsExplicit = intelligence.deadline == nil ? fallback.deadlineIsExplicit : intelligence.deadlineIsExplicit
        let completeness = Self.completeness(
            merchant: merchant,
            value: value,
            purchaseDate: purchaseDate,
            deadline: deadline,
            hasReadableText: hasReadableText
        )
        let warnings = Self.normalizedWarnings(intelligence.warnings + fallback.warnings)
        let summary = trimmed(intelligence.summary) ?? Self.summary(
            merchant: merchant,
            category: category,
            value: value,
            deadline: deadline,
            isExplicit: deadlineIsExplicit,
            identifier: orderNumber ?? serialNumber ?? barcodeValues.first,
            completeness: completeness
        )

        return ProofIntelligence(
            merchant: merchant,
            category: category,
            valueAtRisk: value,
            purchaseDate: purchaseDate,
            deadline: deadline,
            deadlineIsExplicit: deadlineIsExplicit,
            orderNumber: orderNumber,
            serialNumber: serialNumber,
            barcodeValues: barcodeValues,
            confidence: min(max(intelligence.confidence, fallback.confidence), 1),
            warnings: warnings,
            summary: summary,
            completeness: completeness
        )
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }

    private func validValue(_ value: Double?) -> Double? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func explicitDeadline(from text: String) -> Date? {
        let terms = [
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

        let lines = text.components(separatedBy: .newlines)
        for line in lines where terms.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            if let date = ClaimDraftGenerator.parseFirstDate(line) {
                return date
            }
        }

        return nil
    }

    private static func likelyOrderNumber(from text: String) -> String? {
        let patterns = [
            #"(?i)\b(?:order|invoice|receipt|transaction|confirmation)\s*(?:number|no\.?|#|id)?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{4,})"#,
            #"(?i)\b(?:ord|inv|txn)\s*[:#]\s*([A-Z0-9][A-Z0-9\-]{4,})"#
        ]

        for line in text.components(separatedBy: .newlines) {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, range: range),
                   match.numberOfRanges > 1,
                   let valueRange = Range(match.range(at: 1), in: line) {
                    return String(line[valueRange].prefix(80))
                }
            }
        }

        return nil
    }

    private static func likelySerialNumber(from text: String) -> String? {
        let patterns = [
            #"(?i)\b(?:serial|serial\s*(?:number|no\.?)|s/n|sn)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{3,})"#,
            #"(?i)\b(?:model\s*serial)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{3,})"#
        ]

        for line in text.components(separatedBy: .newlines) {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, range: range),
                   match.numberOfRanges > 1,
                   let valueRange = Range(match.range(at: 1), in: line) {
                    return String(line[valueRange].prefix(80))
                }
            }
        }

        return nil
    }

    private static func barcodeValuesFromText(_ text: String) -> [String] {
        let patterns = [
            #"(?i)\bbarcode\s*(?:[A-Z0-9\- ]+)?\s*[:#]\s*([A-Z0-9][A-Z0-9\-]{5,})"#,
            #"(?i)\b(?:upc|ean|qr)\s*[:#]\s*([A-Z0-9][A-Z0-9\-]{5,})"#
        ]

        return text.components(separatedBy: .newlines).flatMap { line in
            patterns.compactMap { pattern -> String? in
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: line)
                else {
                    return nil
                }
                return String(line[valueRange].prefix(120))
            }
        }
    }

    private static func normalizedBarcodeValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .map { String($0.prefix(120)) }
    }

    private static func fallbackConfidence(
        merchant: String?,
        value: Double?,
        purchaseDate: Date?,
        deadline: Date?,
        orderNumber: String?,
        serialNumber: String?,
        barcodeValues: [String]
    ) -> Double {
        var confidence = 0.2
        if merchant != nil { confidence += 0.18 }
        if value != nil { confidence += 0.18 }
        if purchaseDate != nil { confidence += 0.18 }
        if deadline != nil { confidence += 0.18 }
        if orderNumber != nil { confidence += 0.08 }
        if serialNumber != nil { confidence += 0.06 }
        if !barcodeValues.isEmpty { confidence += 0.06 }
        return min(confidence, 0.82)
    }

    private static func normalizedWarnings(_ warnings: [String]) -> [String] {
        Array(Set(warnings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private static func summary(
        merchant: String?,
        category: ClaimCategory?,
        value: Double?,
        deadline: Date?,
        isExplicit: Bool,
        identifier: String?,
        completeness: ProofCompleteness
    ) -> String {
        let subject = merchant ?? category?.displayName ?? "Proof"
        let valueText = value.map(CurrencyFormatter.string) ?? "no clear value"
        let deadlineText = deadline.map { DateHelpers.deadlineText(for: $0) } ?? "no clear deadline"
        let deadlineSource = isExplicit ? "found in the proof" : "suggested"
        let identifierText = identifier.map { " Identifier: \($0)." } ?? ""

        if completeness.score >= 0.8 {
            return "\(subject) proof includes \(valueText) and a \(deadlineText.lowercased()) deadline \(deadlineSource).\(identifierText)"
        }

        if completeness.missingFields.isEmpty {
            return "\(subject) proof is ready to review.\(identifierText)"
        }

        return "\(subject) proof needs review: missing \(completeness.missingFields.joined(separator: ", ")).\(identifierText)"
    }
}
