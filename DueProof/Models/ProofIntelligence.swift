import Foundation

struct ProofIntelligence: Codable, Equatable {
    private static let summaryLimit = 500
    private static let warningLimit = 160
    private static let missingFieldLimit = 80
    private static let maximumWarnings = 8
    private static let maximumBarcodeValues = 20

    var merchant: String?
    var category: ClaimCategory?
    var valueAtRisk: Double?
    var purchaseDate: Date?
    var deadline: Date?
    var deadlineIsExplicit: Bool
    var orderNumber: String?
    var serialNumber: String?
    var barcodeValues: [String]
    var confidence: Double
    var warnings: [String]
    var summary: String
    var completeness: ProofCompleteness

    init(
        merchant: String?,
        category: ClaimCategory?,
        valueAtRisk: Double?,
        purchaseDate: Date?,
        deadline: Date?,
        deadlineIsExplicit: Bool,
        orderNumber: String?,
        serialNumber: String? = nil,
        barcodeValues: [String] = [],
        confidence: Double,
        warnings: [String],
        summary: String,
        completeness: ProofCompleteness
    ) {
        self.merchant = merchant
        self.category = category
        self.valueAtRisk = valueAtRisk
        self.purchaseDate = purchaseDate
        self.deadline = deadline
        self.deadlineIsExplicit = deadlineIsExplicit
        self.orderNumber = orderNumber
        self.serialNumber = serialNumber
        self.barcodeValues = barcodeValues
        self.confidence = confidence
        self.warnings = warnings
        self.summary = summary
        self.completeness = completeness
    }

    private enum CodingKeys: String, CodingKey {
        case merchant
        case category
        case valueAtRisk
        case purchaseDate
        case deadline
        case deadlineIsExplicit
        case orderNumber
        case serialNumber
        case barcodeValues
        case confidence
        case warnings
        case summary
        case completeness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        merchant = Self.decodeString(from: container, forKey: .merchant)
        category = Self.decodeCategory(from: container)
        valueAtRisk = Self.decodeDouble(from: container, forKey: .valueAtRisk)
        purchaseDate = Self.decodeDate(from: container, forKey: .purchaseDate)
        deadline = Self.decodeDate(from: container, forKey: .deadline)
        deadlineIsExplicit = Self.decodeBool(from: container, forKey: .deadlineIsExplicit) ?? false
        orderNumber = Self.decodeString(from: container, forKey: .orderNumber)
        serialNumber = Self.decodeString(from: container, forKey: .serialNumber)
        barcodeValues = Self.decodeStringArray(from: container, forKey: .barcodeValues)
        confidence = Self.decodeDouble(from: container, forKey: .confidence) ?? 0
        warnings = Self.decodeStringArray(from: container, forKey: .warnings)
        summary = Self.decodeString(from: container, forKey: .summary) ?? "Proof needs review."
        completeness = Self.decodeCompleteness(from: container) ?? ProofCompleteness(
            score: 0,
            hasMerchant: false,
            hasValue: false,
            hasPurchaseDate: false,
            hasDeadline: false,
            hasReadableText: false,
            missingFields: []
        )
    }

    func encode(to encoder: Encoder) throws {
        let normalized = normalizedForStorage()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(normalized.merchant, forKey: .merchant)
        try container.encodeIfPresent(normalized.category, forKey: .category)
        try container.encodeIfPresent(normalized.valueAtRisk, forKey: .valueAtRisk)
        try container.encodeIfPresent(normalized.purchaseDate, forKey: .purchaseDate)
        try container.encodeIfPresent(normalized.deadline, forKey: .deadline)
        try container.encode(normalized.deadlineIsExplicit, forKey: .deadlineIsExplicit)
        try container.encodeIfPresent(normalized.orderNumber, forKey: .orderNumber)
        try container.encodeIfPresent(normalized.serialNumber, forKey: .serialNumber)
        try container.encode(normalized.barcodeValues, forKey: .barcodeValues)
        try container.encode(normalized.confidence, forKey: .confidence)
        try container.encode(normalized.warnings, forKey: .warnings)
        try container.encode(normalized.summary, forKey: .summary)
        try container.encode(normalized.completeness, forKey: .completeness)
    }

    var deadlineLabel: String {
        guard deadline != nil else { return "No deadline found" }
        return deadlineIsExplicit ? "Deadline found in proof" : "Deadline suggested"
    }

    var primaryIdentifier: String? {
        orderNumber ?? serialNumber ?? barcodeValues.first
    }

    func normalizedForStorage() -> ProofIntelligence {
        let normalizedValue = valueAtRisk.flatMap { value in
            value.isFinite && value >= 0 && value <= CurrencyFormatter.maximumSupportedAmount ? value : nil
        }
        let normalizedPurchaseDate = Self.normalizedDate(purchaseDate)
        let normalizedDeadline = Self.normalizedDate(deadline)
        let normalizedBarcodeValues = Self.normalizedList(
            barcodeValues,
            limit: ClaimTextLimits.reference,
            maximumCount: Self.maximumBarcodeValues
        )
        let normalizedWarnings = Self.normalizedList(
            warnings,
            limit: Self.warningLimit,
            maximumCount: Self.maximumWarnings
        )
        let normalizedMerchant = ClaimTextLimits.optional(merchant, limit: ClaimTextLimits.merchant)
        let normalizedCompleteness = Self.normalizedCompleteness(
            merchant: normalizedMerchant,
            value: normalizedValue,
            purchaseDate: normalizedPurchaseDate,
            deadline: normalizedDeadline,
            hasReadableText: completeness.hasReadableText
        )

        return ProofIntelligence(
            merchant: normalizedMerchant,
            category: category,
            valueAtRisk: normalizedValue,
            purchaseDate: normalizedPurchaseDate,
            deadline: normalizedDeadline,
            deadlineIsExplicit: normalizedDeadline == nil ? false : deadlineIsExplicit,
            orderNumber: ClaimTextLimits.optional(orderNumber, limit: ClaimTextLimits.reference),
            serialNumber: ClaimTextLimits.optional(serialNumber, limit: ClaimTextLimits.reference),
            barcodeValues: normalizedBarcodeValues,
            confidence: confidenceBounded(confidence),
            warnings: normalizedWarnings,
            summary: Self.normalizedRequired(summary, limit: Self.summaryLimit, fallback: "Proof needs review."),
            completeness: normalizedCompleteness
        )
    }

    private static func normalizedDate(_ value: Date?) -> Date? {
        guard let value, value.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return value
    }

    private static func normalizedCompleteness(
        merchant: String?,
        value: Double?,
        purchaseDate: Date?,
        deadline: Date?,
        hasReadableText: Bool
    ) -> ProofCompleteness {
        let hasMerchant = merchant != nil
        let hasValue = value != nil
        let hasPurchaseDate = purchaseDate != nil
        let hasDeadline = deadline != nil
        let checks = [hasMerchant, hasValue, hasPurchaseDate, hasDeadline, hasReadableText]
        let score = Double(checks.filter { $0 }.count) / Double(checks.count)
        var missingFields: [String] = []

        func appendMissing(_ field: String, when isMissing: Bool) {
            guard isMissing, !missingFields.contains(field), missingFields.count < 10 else { return }
            missingFields.append(field)
        }

        appendMissing("merchant", when: !hasMerchant)
        appendMissing("value", when: !hasValue)
        appendMissing("purchase date", when: !hasPurchaseDate)
        appendMissing("deadline", when: !hasDeadline)
        appendMissing("readable text", when: !hasReadableText)

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

    private static func decodeString(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        try? container.decodeIfPresent(String.self, forKey: key)
    }

    private static func decodeStringArray(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String] {
        (try? container.decodeIfPresent([String].self, forKey: key)) ?? []
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        try? container.decodeIfPresent(Double.self, forKey: key)
    }

    private static func decodeBool(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool? {
        try? container.decodeIfPresent(Bool.self, forKey: key)
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        do {
            return normalizedDate(try container.decodeIfPresent(Date.self, forKey: key))
        } catch {
            return nil
        }
    }

    private static func decodeCategory(from container: KeyedDecodingContainer<CodingKeys>) -> ClaimCategory? {
        if let category = try? container.decodeIfPresent(ClaimCategory.self, forKey: .category) {
            return category
        }

        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .category) else {
            return nil
        }

        return ClaimCategory(rawValue: rawValue)
    }

    private static func decodeCompleteness(from container: KeyedDecodingContainer<CodingKeys>) -> ProofCompleteness? {
        try? container.decodeIfPresent(ProofCompleteness.self, forKey: .completeness)
    }

    private func confidenceBounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func normalizedRequired(_ value: String, limit: Int, fallback: String) -> String {
        let normalized = ClaimTextLimits.required(value, limit: limit)
        return normalized.isEmpty ? fallback : normalized
    }

    private static func normalizedList(_ values: [String], limit: Int, maximumCount: Int) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = ClaimTextLimits.required(value, limit: limit)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .prefix(maximumCount)
        .map { $0 }
    }
}

struct ProofCompleteness: Codable, Equatable {
    var score: Double
    var hasMerchant: Bool
    var hasValue: Bool
    var hasPurchaseDate: Bool
    var hasDeadline: Bool
    var hasReadableText: Bool
    var missingFields: [String]

    var displayPercent: String {
        let normalizedScore = score.isFinite ? min(max(score, 0), 1) : 0
        return "\(Int((normalizedScore * 100).rounded()))%"
    }
}

extension ProofCompleteness {
    private enum CodingKeys: String, CodingKey {
        case score
        case hasMerchant
        case hasValue
        case hasPurchaseDate
        case hasDeadline
        case hasReadableText
        case missingFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = (try? container.decodeIfPresent(Double.self, forKey: .score)) ?? 0
        hasMerchant = (try? container.decodeIfPresent(Bool.self, forKey: .hasMerchant)) ?? false
        hasValue = (try? container.decodeIfPresent(Bool.self, forKey: .hasValue)) ?? false
        hasPurchaseDate = (try? container.decodeIfPresent(Bool.self, forKey: .hasPurchaseDate)) ?? false
        hasDeadline = (try? container.decodeIfPresent(Bool.self, forKey: .hasDeadline)) ?? false
        hasReadableText = (try? container.decodeIfPresent(Bool.self, forKey: .hasReadableText)) ?? false
        missingFields = (try? container.decodeIfPresent([String].self, forKey: .missingFields)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        let normalizedScore = score.isFinite ? min(max(score, 0), 1) : 0
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(normalizedScore, forKey: .score)
        try container.encode(hasMerchant, forKey: .hasMerchant)
        try container.encode(hasValue, forKey: .hasValue)
        try container.encode(hasPurchaseDate, forKey: .hasPurchaseDate)
        try container.encode(hasDeadline, forKey: .hasDeadline)
        try container.encode(hasReadableText, forKey: .hasReadableText)
        try container.encode(missingFields, forKey: .missingFields)
    }
}
