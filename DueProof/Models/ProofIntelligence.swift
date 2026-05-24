import Foundation

struct ProofIntelligence: Codable, Equatable {
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

        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        category = try container.decodeIfPresent(ClaimCategory.self, forKey: .category)
        valueAtRisk = try container.decodeIfPresent(Double.self, forKey: .valueAtRisk)
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        deadlineIsExplicit = try container.decodeIfPresent(Bool.self, forKey: .deadlineIsExplicit) ?? false
        orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
        barcodeValues = try container.decodeIfPresent([String].self, forKey: .barcodeValues) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? "Proof needs review."
        completeness = try container.decodeIfPresent(ProofCompleteness.self, forKey: .completeness) ?? ProofCompleteness(
            score: 0,
            hasMerchant: false,
            hasValue: false,
            hasPurchaseDate: false,
            hasDeadline: false,
            hasReadableText: false,
            missingFields: []
        )
    }

    var deadlineLabel: String {
        guard deadline != nil else { return "No deadline found" }
        return deadlineIsExplicit ? "Deadline found in proof" : "Deadline suggested"
    }

    var primaryIdentifier: String? {
        orderNumber ?? serialNumber ?? barcodeValues.first
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
        "\(Int((score * 100).rounded()))%"
    }
}
